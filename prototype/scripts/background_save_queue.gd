class_name RoRBackgroundSaveQueue
extends RefCounted

const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const SaveTask := preload("res://scripts/background_save_task.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const MAX_WAITING := 1
var coordinator := Coordinator.new()
var waiting: Array = []
var active_request := -1
var active_input: Dictionary = {}
var completed: Array = []
var writer: FileWriter

class FileWriter extends RefCounted:
	var input: Dictionary
	var validate_capture := false
	var status := SaveTask.Progress.new()

	func run(_envelope: Dictionary) -> Dictionary:
		if validate_capture:
			status.update("capture")
			if not Data.is_detached(input):
				var error := {"error":int(ERR_INVALID_DATA), "detail":"capture_not_isolated"}
				input = {}
				return error
		var result := SaveTask.run(input, status.update)
		input = {}
		return result

func enqueue(input: Dictionary) -> bool:
	if waiting.size() >= MAX_WAITING or not Data.is_detached(input): return false
	return _enqueue_owned(Data.copy(input), false)

# Exclusive transfer from MatchLifecycle.capture_save. Other callers own their
# input after enqueue() returns, including if the job is still in the queue.
func enqueue_captured(input: Dictionary) -> bool:
	if waiting.size() >= MAX_WAITING: return false
	return _enqueue_owned(input, true)

func _enqueue_owned(input: Dictionary, validate_capture: bool) -> bool:
	var job := FileWriter.new()
	job.input = input
	job.validate_capture = validate_capture
	waiting.append(job)
	_start_next()
	return true

func progress() -> Dictionary:
	if active_request < 0 or writer == null: return {}
	var current := writer.status.read()
	current["kind"] = active_input["kind"]
	current["slot_name"] = active_input["slot_name"]
	return current

func _start_next() -> void:
	if active_request >= 0 or waiting.is_empty():
		return
	writer = waiting.pop_front()
	writer.status.update("queued")
	active_input = {"path":writer.input["path"],"slot_name":writer.input["slot_name"],"tick":writer.input["tick"],"kind":writer.input.get("kind","manual")}
	active_request = coordinator.submit("save", {}, writer.run, int(active_input["tick"]), int(active_input["tick"]), {}, true)
	if active_request < 0:
		# Worker rejection is an explicit failure, never synchronous I/O in poll.
		completed.append(active_input.merged({"error":ERR_BUSY}))
		active_input = {}
		writer = null
		_start_next()

func poll() -> Array:
	if active_request >= 0 and coordinator.is_ready(active_request):
		var result := coordinator.collect(active_request)
		completed.append(active_input.merged(result.get("data", {"error":ERR_INVALID_DATA}), true))
		active_request = -1
		active_input = {}
		writer = null
		_start_next()
	var result := completed
	completed = []
	return result

func drain() -> Array:
	while active_request >= 0 or not waiting.is_empty():
		if active_request >= 0:
			var result := coordinator.collect(active_request, true)
			completed.append(active_input.merged(result.get("data", {"error":ERR_INVALID_DATA}), true))
			active_request = -1
			active_input = {}
			writer = null
		_start_next()
	return poll()

func shutdown() -> void:
	drain()
	coordinator.shutdown()
