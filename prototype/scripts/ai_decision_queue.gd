class_name RoRAiDecisionQueue
extends RefCounted

# Owner-thread orchestration. All proposals use one frozen simulation boundary
# and are published in player order at the same, predetermined apply tick.
# While workers run, the controller yields without consuming a fixed step.
# At most one observation/capture is prepared per rendered frame.
const Data := preload("res://scripts/isolated_task_data.gd")
const PlanningTask := preload("res://scripts/ai_planning_task.gd")

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

func poll(coordinator, current_source_tick: int, frame_id: int) -> Dictionary:
	if not active:
		return {"ready": true, "planned": false}
	if current_source_tick != source_tick:
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
				record["input"] = captured
				if record["input"].is_empty() or not Data.is_detached(record["input"]):
					error = "ai_capture_not_isolated"
					return {"ready": false, "error": error}
			var request_id: int = coordinator.submit("ai_planning", record["input"], PlanningTask.run, source_tick, apply_tick, {"team": int(record["ai"].team)}, true)
			if request_id >= 0:
				record["request_id"] = request_id
				record["submitted"] = true
			# Capacity exhaustion leaves the captured input queued for a later
			# frame. It never triggers an expensive inline fallback.
			break
	return {"ready": records.all(func(record): return not record["output"].is_empty()), "planned": not records.is_empty()}

func take_ready() -> Array:
	assert(active and error.is_empty() and records.all(func(record): return not record["output"].is_empty()), "AI proposals are not ready")
	var result := records
	records = []
	prepare = Callable()
	active = false
	return result

func cancel(coordinator) -> void:
	for record in records:
		if bool(record["submitted"]) and record["output"].is_empty():
			coordinator.discard(int(record["request_id"]))
	records = []
	prepare = Callable()
	active = false
	source_tick = -1
	apply_tick = -1
	error = ""
