class_name RoRAiDecisionQueue
extends RefCounted

# Capture at a fixed source boundary, calculate while simulation advances, and
# publish in player order at a predetermined target. Only incomplete capture
# or an unfinished job at its deadline may hold a fixed step.
const Data := preload("res://scripts/isolated_task_data.gd")
const PlanningTask := preload("res://scripts/ai_planning_task.gd")
const LOOKAHEAD_TICKS := 8
const STATE_VERSION := 2
const MAX_INPUT_BYTES := 64 * 1024 * 1024

var records: Array = []
var source_tick := -1
var apply_tick := -1
var prepare: Callable
var last_prepared_frame := -1
var error := ""
var active := false

func begin(players: Array, source: int, target: int, capture: Callable) -> void:
	assert(not active, "AI decision batch must be consumed or cancelled first")
	source_tick = source
	apply_tick = target
	prepare = capture
	# Preserve the frame budget across adjacent decision batches.
	error = ""
	active = true
	records = []
	for player in players:
		records.append({"ai": player, "request_id": -1, "input": {}, "output": {}, "submitted": false})

func is_prepared() -> bool:
	return active and records.all(func(record): return bool(record["submitted"]))

func poll(coordinator, current_source_tick: int, frame_id: int, probe: Variant = null) -> Dictionary:
	if not active:
		return {"ready": true, "planned": false}
	var needs_capture: bool = records.any(func(record): return record["input"].is_empty())
	if current_source_tick < source_tick or current_source_tick >= apply_tick or (needs_capture and current_source_tick != source_tick):
		error = "ai_source_tick_changed"
		return {"ready": false, "error": error}
	for record in records:
		if not bool(record["submitted"]) or not record["output"].is_empty():
			continue
		var collected: Dictionary = coordinator.collect_for_tick(int(record["request_id"]), apply_tick, {"team": int(record["ai"].team)})
		match String(collected["status"]):
			"ready":
				record["output"] = collected["result"]["data"]
				if not bool(record["output"].get("valid", false)):
					error = "ai_invalid_proposal"
			"stale", "missing", "failed":
				error = "ai_planning_failed"
	if not error.is_empty():
		return {"ready": false, "error": error}
	if last_prepared_frame != frame_id:
		for record in records:
			if bool(record["submitted"]):
				continue
			last_prepared_frame = frame_id
			if record["input"].is_empty():
				var captured: Dictionary = prepare.call(record["ai"], apply_tick)
				if bool(captured.get("pending", false)):
					return {"ready": false, "planned": true}
				var seal_started := Time.get_ticks_usec() if probe != null else 0
				record["input"] = Data.seal(captured) if not captured.is_empty() else {}
				if probe != null:
					probe.observe_microseconds("presentation.ai.seal", Time.get_ticks_usec() - seal_started)
				if record["input"].is_empty():
					error = "ai_capture_not_isolated"
					return {"ready": false, "error": error}
			if not coordinator.is_enabled("ai_planning"):
				# The reference path uses exactly the same snapshot and target.
				record["output"] = PlanningTask.run(record["input"])
				record["submitted"] = true
				if not bool(record["output"].get("valid", false)):
					error = "ai_invalid_proposal"
			else:
				var request_id: int = coordinator.submit("ai_planning", record["input"], PlanningTask.run, source_tick, apply_tick, {"team": int(record["ai"].team)}, true)
				if request_id >= 0:
					record["request_id"] = request_id
					record["submitted"] = true
			# Capacity exhaustion keeps the input queued without inline work.
			break
	if not error.is_empty():
		return {"ready": false, "error": error}
	return {"ready": records.all(func(record): return not record["output"].is_empty()), "planned": not records.is_empty()}

func gate(status: Dictionary, next_tick: int) -> Dictionary:
	if status.has("error") or not is_prepared():
		return {"ready": false, "planned": active}
	if next_tick < apply_tick:
		return {"ready": true, "planned": false}
	return status

func take_ready() -> Array:
	assert(active and error.is_empty() and records.all(func(record): return not record["output"].is_empty()), "AI proposals are not ready")
	var result := records
	records = []
	prepare = Callable()
	active = false
	return result

func canonical_state() -> Dictionary:
	if not active:
		return {}
	var saved: Array = []
	for record in records:
		# Binary Variant encoding preserves vector/packed-array types and numeric
		# keys through the save archive's JSON layer. Objects are never encoded.
		var blob := "" if record["input"].is_empty() else Marshalls.raw_to_base64(var_to_bytes(record["input"]))
		saved.append({"team": int(record["ai"].team), "input": blob})
	return {"version": STATE_VERSION, "source_tick": source_tick, "apply_tick": apply_tick, "records": saved}

func restore_state(data: Dictionary, players: Array, current_tick: int, capture: Callable) -> bool:
	if active:
		return false
	if data.is_empty():
		return true
	if int(data.get("version", -1)) != STATE_VERSION or not data.get("records") is Array:
		return false
	var source := int(data.get("source_tick", -1))
	var target := int(data.get("apply_tick", -1))
	if source < 0 or source > current_tick or target <= current_tick or target - source > LOOKAHEAD_TICKS or data["records"].size() > players.size():
		return false
	var restored: Array = []
	var seen: Dictionary = {}
	var total_bytes := 0
	for row in data["records"]:
		if not row is Dictionary or not row.get("input") is String:
			return false
		var team := int(row.get("team", -1))
		var matches: Array = players.filter(func(player): return int(player.team) == team)
		if matches.size() != 1 or seen.has(team):
			return false
		seen[team] = true
		var blob: String = row["input"]
		total_bytes += blob.length()
		if total_bytes > MAX_INPUT_BYTES * 4 / 3:
			return false
		var input: Dictionary = {}
		if blob.is_empty():
			if source != current_tick:
				return false
		else:
			var decoded: Variant = bytes_to_var(Marshalls.base64_to_raw(blob))
			if not decoded is Dictionary or not decoded.get("definition") is Dictionary or not decoded.get("snapshot") is Dictionary:
				return false
			if int(decoded.get("tick", -1)) != target or decoded["definition"] != PlanningTask.capture(matches[0], {}, target)["definition"] or decoded.get("state") != matches[0].canonical_state():
				return false
			if int(decoded["snapshot"].get("observer_team", -1)) != team or int(decoded["snapshot"].get("tick", -1)) != source:
				return false
			input = Data.seal(decoded)
			if input.is_empty():
				return false
		restored.append({"ai": matches[0], "request_id": -1, "input": input, "output": {}, "submitted": false})
	if restored.is_empty() or restored.size() > players.size():
		return false
	source_tick = source
	apply_tick = target
	prepare = capture
	last_prepared_frame = -1
	error = ""
	records = restored
	active = true
	return true

func cancel(coordinator) -> void:
	for record in records:
		if bool(record["submitted"]) and record["output"].is_empty() and int(record["request_id"]) >= 0:
			coordinator.discard(int(record["request_id"]))
	records = []
	prepare = Callable()
	active = false
	source_tick = -1
	apply_tick = -1
	error = ""
