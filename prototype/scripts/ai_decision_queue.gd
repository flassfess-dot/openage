class_name RoRAiDecisionQueue
extends RefCounted

# Each observer samples at fixed simulation ticks and publishes its orders at
# a fixed deadline. Independent opponents can plan during the same time span.
const Data := preload("res://scripts/isolated_task_data.gd")
const PlanningTask := preload("res://scripts/ai_planning_task.gd")
const LOOKAHEAD_TICKS := 8
const STATE_VERSION := 4
const MAX_INPUT_BYTES := 64 * 1024 * 1024
const PREPARATION_BUDGET_USEC := 7000

var records: Array = []
var executors: Dictionary = {}
var source_tick := -1
var apply_tick := -1
var prepare: Callable
var prepare_navigation: Callable
var prepare_sites: Callable
var last_prepared_frame := -1
var preparation_usec_left := 0
var preparation_budget_usec := PREPARATION_BUDGET_USEC
var error := ""
var active := false

func begin(players: Array, source: int, target: int, capture: Callable) -> void:
	assert(not active, "AI decision batch must be consumed or cancelled first")
	error = ""
	for player in players:
		schedule(player, source, target, capture)

func schedule(ai, source: int, target: int, capture: Callable, split_observation: bool = false) -> void:
	var facts_tick := mini(source + 1, target - 1) if split_observation else source
	records.append({"ai":ai, "source":source, "facts_tick":facts_tick, "target":target, "split":split_observation,
		"navigation":null, "request_id":-1, "input":{}, "output":{}, "submitted":false})
	prepare = capture
	active = true
	source_tick = source if source_tick < 0 else mini(source_tick, source)
	apply_tick = target if apply_tick < 0 else mini(apply_tick, target)

func record_for(ai) -> Dictionary:
	for record in records:
		if record["ai"] == ai: return record
	return {}

func is_prepared() -> bool:
	return active and records.all(func(record): return bool(record["submitted"]))

func has_runnable_capture() -> bool:
	# Runtime publications complete on their scheduled tick. Only an older
	# in-flight decision restored at its source can have more slices ready.
	return records.any(func(record): return not bool(record["split"]) and record["input"].is_empty())

func poll(coordinator, current_source_tick: int, frame_id: int, probe: Variant = null) -> Dictionary:
	if not active:
		return {"ready": true, "planned": false}
	if current_source_tick < source_tick or current_source_tick >= apply_tick:
		error = "ai_source_tick_changed"
		return {"ready": false, "error": error}
	for record in records:
		if not bool(record["submitted"]) or not record["output"].is_empty():
			continue
		var collected: Dictionary = coordinator.collect_for_tick(int(record["request_id"]), int(record["target"]), {"team": int(record["ai"].team)})
		match String(collected["status"]):
			"ready":
				record["output"] = collected["result"]["data"]
				if probe != null:
					probe.observe_microseconds("ai.worker.action", int(collected["result"].get("action_us", 0)))
					probe.observe_microseconds("ai.worker.validation", int(collected["result"].get("validation_us", 0)))
					for stage in collected["result"].get("stages_us", {}):
						probe.observe_microseconds("ai.worker." + stage, int(collected["result"].stages_us[stage]))
				if not bool(record["output"].get("valid", false)):
					error = "ai_invalid_proposal"
			"stale", "missing", "failed":
				error = "ai_planning_failed"
	if not error.is_empty():
		return {"ready": false, "error": error}
	if last_prepared_frame != frame_id:
		last_prepared_frame = frame_id
		preparation_usec_left = preparation_budget_usec
	for record in records:
		if bool(record["submitted"]): continue
		var staged := bool(record["split"])
		var target := int(record["target"])
		var facts_tick := int(record["facts_tick"])
		if record["input"].is_empty() and (current_source_tick > facts_tick or (staged and record["navigation"] == null and current_source_tick != int(record["source"]))):
			error = "ai_source_tick_changed"
			break
		if not staged and preparation_usec_left <= 0: continue
		var started := Time.get_ticks_usec()
		if record["input"].is_empty():
			if staged and record["navigation"] == null:
				var observation: Dictionary = prepare_navigation.call(record["ai"], target)
				record["navigation"] = observation["navigation"]
			if current_source_tick < facts_tick: continue
			var captured: Dictionary = prepare.call(record["ai"], target)
			if bool(captured.get("pending", false)):
				preparation_usec_left = 0
				continue
			var seal_started := Time.get_ticks_usec() if probe != null else 0
			if staged:
				# The runtime publisher validated and sealed this exact input.
				record["input"] = captured
			else:
				record["input"] = Data.seal(Data.capture_frozen(captured)) if not captured.is_empty() else {}
			if probe != null: probe.observe_microseconds("presentation.ai.seal", Time.get_ticks_usec() - seal_started)
			if record["input"].is_empty():
				error = "ai_capture_not_isolated"
				break
			record["navigation"] = null
		if staged and record["input"]["snapshot"].has("_pending_build_site_kinds"):
			var site_tick := mini(int(record["source"]) + 2, target - 1)
			if current_source_tick < site_tick: continue
			if current_source_tick > site_tick:
				error = "ai_source_tick_changed"
				break
			record["input"] = prepare_sites.call(record["ai"], record["input"], current_source_tick)
			if record["input"].is_empty():
				error = "ai_capture_not_isolated"
				break
		var player_key: int = record["ai"].get_instance_id()
		if not executors.has(player_key):
			if executors.size() >= 8: executors.erase(executors.keys()[0])
			executors[player_key] = PlanningTask.Executor.new()
		var executor = executors[player_key]
		if coordinator.is_enabled("ai_planning"):
			var request_id: int = coordinator.submit("ai_planning", record["input"], executor.run, facts_tick, target, {"team":int(record["ai"].team)}, true)
			if request_id >= 0:
				record["request_id"] = request_id
				record["submitted"] = true
		else:
			record["output"] = executor.run(record["input"])
			record["submitted"] = true
			if not bool(record["output"].get("valid", false)):
				error = "ai_invalid_proposal"
		if not staged: preparation_usec_left -= Time.get_ticks_usec() - started
	if not error.is_empty():
		return {"ready": false, "error": error}
	return {"ready": records.all(func(record): return int(record["target"]) > apply_tick or not record["output"].is_empty()), "planned": not records.is_empty()}

func gate(status: Dictionary, next_tick: int) -> Dictionary:
	if status.has("error"):
		return {"ready": false, "planned": active}
	for record in records:
		if not bool(record["split"]) and record["input"].is_empty():
			return {"ready":false, "planned":true}
	if next_tick < apply_tick:
		# This poll has not committed AI state or enqueued gameplay commands.
		# It is safe to repeat if the controller yields the rendered frame.
		return {"ready": true, "planned": false, "can_defer": true}
	return status

func take_ready() -> Array:
	var result := records.filter(func(record): return int(record["target"]) == apply_tick)
	assert(active and error.is_empty() and result.all(func(record): return not record["output"].is_empty()), "AI proposals are not ready")
	records = records.filter(func(record): return int(record["target"]) > apply_tick)
	result.sort_custom(func(a,b): return int(a["ai"].team) < int(b["ai"].team))
	source_tick = -1
	apply_tick = -1
	active = not records.is_empty()
	for record in records:
		source_tick = int(record["source"]) if source_tick < 0 else mini(source_tick, int(record["source"]))
		apply_tick = int(record["target"]) if apply_tick < 0 else mini(apply_tick, int(record["target"]))
	if not active: prepare = Callable()
	return result

func save_view() -> Dictionary:
	if not active:
		return {}
	var saved: Array = []
	for record in records:
		# Capture scalar deadlines and retain the immutable input roots. Jobs
		# can finish or be removed immediately after this owner boundary.
		var row := {"team":int(record["ai"].team), "source":record["source"], "target":record["target"],
			"facts_tick":record["facts_tick"], "split":record["split"], "input":record["input"], "navigation":record["navigation"], "plan":null}
		if not record["output"].is_empty():
			# Its authoritative decision is already known. The full fog, placement
			# and actor observations can be dropped from this save immediately.
			row["plan"] = {"state":record["input"]["state"], "output":record["output"].duplicate(true)}
			row["input"] = {}
		saved.append(row)
	return {"version": STATE_VERSION, "source_tick": source_tick, "apply_tick": apply_tick, "records": saved}

static func encode_save_view(view: Dictionary) -> Dictionary:
	if view.is_empty(): return {}
	var encoded := view.duplicate()
	var rows: Array = []
	for record in view["records"]:
		var row: Dictionary = record.duplicate()
		for field in ["input","navigation","plan"]:
			var value: Variant = record[field]
			row[field] = ""
			if value == null or (field == "input" and value.is_empty()): continue
			var bytes := var_to_bytes(value)
			if bytes.size() >= 16384:
				var compressed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
				if not compressed.is_empty() and compressed.size() < bytes.size():
					row[field + "_bytes"] = bytes.size()
					bytes = compressed
			row[field] = Marshalls.raw_to_base64(bytes)
		rows.append(row)
	encoded["records"] = rows
	return encoded

func canonical_state() -> Dictionary:
	return encode_save_view(save_view())

static func _decode_observation(row: Dictionary, field: String, version: int) -> Variant:
	var raw := Marshalls.base64_to_raw(row[field])
	if version >= 4 and row.has(field + "_bytes"):
		var size := int(row[field + "_bytes"])
		if size < 1 or size > MAX_INPUT_BYTES: return null
		raw = raw.decompress(size, FileAccess.COMPRESSION_ZSTD)
		if raw.size() != size: return null
	if raw.is_empty() or raw.size() > MAX_INPUT_BYTES: return null
	return bytes_to_var(raw)

func restore_state(data: Dictionary, players: Array, current_tick: int, capture: Callable) -> bool:
	if active:
		return false
	if data.is_empty():
		return true
	var version := int(data.get("version", -1))
	if version not in [2, 3, STATE_VERSION] or not data.get("records") is Array:
		return false
	var source := int(data.get("source_tick", -1))
	var target := int(data.get("apply_tick", -1))
	if source < 0 or source > current_tick or target <= current_tick or data["records"].size() > mini(8, players.size()):
		return false
	var restored: Array = []
	var seen: Dictionary = {}
	var total_bytes := 0
	for row in data["records"]:
		if not row is Dictionary or not row.get("input") is String:
			return false
		if version >= 3 and not row.get("navigation") is String: return false
		if version >= 4 and not row.get("plan") is String: return false
		var team := int(row.get("team", -1))
		var matches: Array = players.filter(func(player): return int(player.team) == team)
		if matches.size() != 1 or seen.has(team):
			return false
		seen[team] = true
		var observation_tick := int(row.get("source", source)) if version >= 3 else source
		var facts_tick := int(row.get("facts_tick", source)) if version >= 3 else source
		var deadline := int(row.get("target", target)) if version >= 3 else target
		var split := bool(row.get("split", false)) if version >= 3 else false
		if observation_tick < source or observation_tick > current_tick or deadline < target or deadline <= current_tick or deadline - observation_tick > LOOKAHEAD_TICKS:
			return false
		if facts_tick != (mini(observation_tick + 1, deadline - 1) if split else observation_tick):
			return false
		var blob: String = row["input"]
		var navigation_blob := String(row.get("navigation", "")) if version >= 3 else ""
		var plan_blob := String(row.get("plan", "")) if version >= 4 else ""
		var encoded_size := blob.length() + navigation_blob.length() + plan_blob.length()
		total_bytes += encoded_size
		# Independently scheduled teams can now hold several complete map
		# observations. The old single-batch budget applies per team in v3.
		if encoded_size > MAX_INPUT_BYTES * 4 / 3 or (version == 2 and total_bytes > MAX_INPUT_BYTES * 4 / 3):
			return false
		var input: Dictionary = {}
		var navigation: Variant = null
		var output: Dictionary = {}
		if not plan_blob.is_empty():
			if not blob.is_empty() or not navigation_blob.is_empty() or facts_tick > current_tick: return false
			var plan: Variant = _decode_observation(row, "plan", version)
			if not plan is Dictionary or plan.get("state") != matches[0].canonical_state() or not plan.get("output") is Dictionary:
				return false
			output = plan["output"]
			if not bool(output.get("valid",false)) or not output.get("state") is Dictionary or int(output["state"].get("team",-1)) != team or not output.get("commands") is Array:
				return false
			var metadata: Variant = output.get("command_metadata",[])
			if not metadata is Array or not metadata.all(func(item): return item is Dictionary):
				return false
			if not output["commands"].all(func(command): return command is Dictionary and int(command.get("tick",-1)) >= deadline):
				return false
			input = {"state":plan["state"], "tick":deadline, "snapshot":{"observer_team":team, "tick":facts_tick}}
		elif blob.is_empty():
			if facts_tick < current_tick or (navigation_blob.is_empty() and observation_tick != current_tick):
				return false
			if not navigation_blob.is_empty():
				if not split: return false
				navigation = _decode_observation(row, "navigation", version)
				if not navigation is Dictionary or not Data.freeze_detached(navigation): return false
		else:
			if not navigation_blob.is_empty() or facts_tick > current_tick:
				return false
			var decoded: Variant = _decode_observation(row, "input", version)
			if not decoded is Dictionary or not decoded.get("definition") is Dictionary or not decoded.get("snapshot") is Dictionary:
				return false
			if int(decoded.get("tick", -1)) != deadline or decoded["definition"] != PlanningTask.capture(matches[0], {}, deadline)["definition"] or decoded.get("state") != matches[0].canonical_state():
				return false
			if int(decoded["snapshot"].get("observer_team", -1)) != team or int(decoded["snapshot"].get("tick", -1)) != facts_tick:
				return false
			if decoded["snapshot"].has("_pending_build_site_kinds") and (not split or current_tick > mini(observation_tick + 2, deadline - 1)):
				return false
			input = Data.seal(decoded)
			if input.is_empty():
				return false
		restored.append({"ai":matches[0], "source":observation_tick, "facts_tick":facts_tick, "target":deadline,
			"split":split, "navigation":navigation, "request_id":-1, "input":input, "output":output, "submitted":not output.is_empty()})
	if restored.is_empty() or restored.size() > players.size():
		return false
	if not restored.any(func(record): return int(record["source"]) == source) or not restored.any(func(record): return int(record["target"]) == target):
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
	executors.clear()
	for record in records:
		if bool(record["submitted"]) and record["output"].is_empty() and int(record["request_id"]) >= 0:
			coordinator.discard(int(record["request_id"]))
	records = []
	prepare = Callable()
	active = false
	source_tick = -1
	apply_tick = -1
	error = ""
