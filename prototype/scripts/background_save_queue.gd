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

func enqueue(input: Dictionary) -> bool:
	if not Data.is_detached(input) or waiting.size() >= MAX_WAITING:
		return false
	waiting.append(input)
	_start_next()
	return true

func _start_next() -> void:
	if active_request >= 0 or waiting.is_empty():
		return
	active_input = waiting.pop_front()
	active_request = coordinator.submit("save", active_input, SaveTask.run, int(active_input["tick"]), int(active_input["tick"]), {}, true)
	if active_request < 0:
		# Worker rejection is an explicit failure, never synchronous I/O in poll.
		completed.append({"error": ERR_BUSY, "path": active_input["path"], "slot_name": active_input["slot_name"], "tick": active_input["tick"]})
		active_input = {}
		_start_next()

func poll() -> Array:
	if active_request >= 0 and coordinator.is_ready(active_request):
		var result := coordinator.collect(active_request)
		if result.is_empty():
			completed.append({"error": ERR_INVALID_DATA, "path": active_input["path"], "slot_name": active_input["slot_name"], "tick": active_input["tick"]})
		else:
			completed.append(result["data"])
		active_request = -1
		active_input = {}
		_start_next()
	var result := completed
	completed = []
	return result

func drain() -> Array:
	while active_request >= 0 or not waiting.is_empty():
		if active_request >= 0:
			var result := coordinator.collect(active_request, true)
			completed.append(result["data"] if not result.is_empty() else {"error": ERR_INVALID_DATA, "path": active_input["path"], "slot_name": active_input["slot_name"], "tick": active_input["tick"]})
			active_request = -1
			active_input = {}
		_start_next()
	return poll()

func shutdown() -> void:
	drain()
	coordinator.shutdown()
