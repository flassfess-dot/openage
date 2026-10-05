class_name RoRIsolatedTaskCoordinator
extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")
const MAX_PENDING := 8
const MAX_WORKERS := 4

# Only the owner mutates pending, generation and request IDs. Each Job owns its
# input/result; results are read only after Godot's completion barrier.
class Job extends RefCounted:
	var envelope: Dictionary = {}
	var input: Dictionary = {}
	var action: Callable
	var result: Dictionary = {}
	var task_id := -1

	func run() -> void:
		var started := Time.get_ticks_usec()
		var value: Variant = action.call(input)
		if value is Dictionary and RoRIsolatedTaskData.is_detached(value):
			result = {"envelope": envelope, "ok": true, "data": value, "worker_us": Time.get_ticks_usec() - started}
		else:
			result = {"envelope": envelope, "ok": false, "data": {}, "worker_us": Time.get_ticks_usec() - started}

var enabled := true
var generation := 1
var next_request_id := 1
var pending: Dictionary = {}
var subsystem_enabled: Dictionary = {}
var rejected_count := 0
var stale_count := 0
var last_metrics: Dictionary = {}
var abandoned: Dictionary = {}

func _init() -> void:
	enabled = bool(ProjectSettings.get_setting("ror_threading/enabled", true))
	for subsystem in ["ai_observation", "ai_planning", "presentation", "navigation_prepare", "navigation_paths", "movement", "animation_loading", "save"]:
		subsystem_enabled[subsystem] = bool(ProjectSettings.get_setting("ror_threading/" + subsystem, subsystem != "presentation"))
	if "--ror-sequential" in OS.get_cmdline_user_args():
		enabled = false

func is_enabled(subsystem: String) -> bool:
	return enabled and bool(subsystem_enabled.get(subsystem, true))

func configure(flags: Dictionary) -> void:
	shutdown()
	subsystem_enabled = flags.duplicate()

func submit(kind: String, input: Dictionary, action: Callable, source_tick: int = -1, apply_tick: int = -1, revisions: Dictionary = {}, take_ownership: bool = false) -> int:
	reap_abandoned()
	if source_tick >= 0 and apply_tick >= 0 and apply_tick < source_tick:
		rejected_count += 1
		return -1
	if not is_enabled(kind) or pending.size() >= MAX_PENDING or not action.is_valid() or not Data.is_detached(input) or not Data.is_detached(revisions):
		rejected_count += 1
		return -1
	var request_id := next_request_id
	next_request_id += 1
	var job := Job.new()
	job.envelope = {"kind": kind, "request_id": request_id, "generation": generation, "source_tick": source_tick, "apply_tick": apply_tick, "revisions": Data.copy(revisions)}
	job.input = input if take_ownership else Data.copy(input)
	job.action = action
	job.task_id = WorkerThreadPool.add_task(job.run, false, "RoR " + kind)
	if job.task_id < 0:
		rejected_count += 1
		return -1
	pending[request_id] = job
	return request_id

func is_ready(request_id: int) -> bool:
	return pending.has(request_id) and WorkerThreadPool.is_task_completed(pending[request_id].task_id)

func collect(request_id: int, wait: bool = false, revisions: Dictionary = {}) -> Dictionary:
	if not pending.has(request_id):
		return {}
	var job: Job = pending[request_id]
	if not wait and not WorkerThreadPool.is_task_completed(job.task_id):
		return {}
	var started := Time.get_ticks_usec()
	var error := WorkerThreadPool.wait_for_task_completion(job.task_id)
	pending.erase(request_id)
	last_metrics = {"wait_us": Time.get_ticks_usec() - started, "worker_us": int(job.result.get("worker_us", 0))}
	var discarded := abandoned.has(request_id)
	abandoned.erase(request_id)
	if discarded or int(job.envelope["generation"]) != generation or (not revisions.is_empty() and revisions != job.envelope["revisions"]):
		stale_count += 1
		return {}
	if error != OK or not bool(job.result.get("ok", false)):
		return {}
	return job.result

# Polling never waits for unfinished work. The apply tick is part of the
# contract, rather than informational metadata in the job envelope.
func collect_for_tick(request_id: int, current_tick: int, revisions: Dictionary = {}) -> Dictionary:
	if not pending.has(request_id):
		return {"status": "missing"}
	var job: Job = pending[request_id]
	var apply_tick := int(job.envelope.get("apply_tick", -1))
	if int(job.envelope["generation"]) != generation or (not revisions.is_empty() and revisions != job.envelope["revisions"]) or (apply_tick >= 0 and current_tick > apply_tick):
		discard(request_id)
		return {"status": "stale"}
	if apply_tick >= 0 and current_tick < apply_tick:
		return {"status": "future"}
	if not is_ready(request_id):
		return {"status": "pending"}
	var result := collect(request_id, false, revisions)
	return {"status": "ready", "result": result} if not result.is_empty() else {"status": "failed"}


func discard(request_id: int) -> void:
	if pending.has(request_id):
		abandoned[request_id] = true
	reap_abandoned()


func reap_abandoned() -> void:
	for request_id in abandoned.keys():
		if not pending.has(request_id):
			abandoned.erase(request_id)
		elif is_ready(int(request_id)):
			collect(int(request_id))


# Authoritative movement/path/build batches deliberately share a same-tick
# barrier. Advisory jobs use collect_for_tick() and yield to the frame loop.
# Process bounded waves and collect by input index, never by completion order.
# Invalid worker results fall back at the same simulation barrier.
func run_ordered(kind: String, inputs: Array, action: Callable, tick: int = -1, take_ownership: bool = false) -> Array:
	var results: Array = []
	var width := mini(MAX_WORKERS, maxi(1, OS.get_processor_count() - 2))
	for first in range(0, inputs.size(), width):
		var requests: Array[int] = []
		var end := mini(first + width, inputs.size())
		for index in range(first, end):
			requests.append(submit(kind, inputs[index], action, tick, tick, {}, take_ownership))
		for index in range(first, end):
			var request_id := requests[index - first]
			var collected := collect(request_id, true) if request_id >= 0 else {}
			if collected.is_empty():
				results.append(action.call(inputs[index]))
			else:
				results.append(collected["data"])
	return results

func invalidate() -> void:
	generation += 1
	# Invalidation discards publication; it does not stop executing Callables.
	# Completed obsolete tasks can be reaped without blocking.
	for request_id in pending.keys():
		if is_ready(int(request_id)):
			collect(int(request_id))

func shutdown() -> void:
	generation += 1
	for request_id in pending.keys():
		collect(int(request_id), true)
	pending.clear()
	abandoned.clear()
