class_name RoRPresentationPublication
extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")

# SimulationSnapshot has already chosen the render/control contract. Never
# project these records a second time: compact buildings omit production_queue,
# and guessing their category loses construction state. Preserve all supplied
# fields, including forest variants and fog metadata.
class ProjectionJob extends RefCounted:
	func capture(source: Dictionary, _detailed: bool) -> Dictionary:
		return RoRIsolatedTaskData.copy(source)

	func run(input: Dictionary) -> Dictionary:
		return {"entities": input["entities"]}

# This detached publication is opt-in. Copying the explored minimap forest and
# validating it every tick adds work after the retained snapshot is already
# ready; it must not be enabled as a runtime optimization.
var buffers: Array = [{}, {}]
var jobs_by_slot: Array = [{}, {}]
var published_slot := -1

func clear() -> void:
	buffers = [{}, {}]
	jobs_by_slot = [{}, {}]
	published_slot = -1

static func capture_entity(source: Dictionary, _detailed: bool) -> Dictionary:
	return Data.copy(source)

static func run(input: Dictionary) -> Dictionary:
	return ProjectionJob.new().run(input)

func publish(snapshot: Dictionary, _selected_ids: Array[int], coordinator) -> Dictionary:
	if not coordinator.is_enabled("presentation"):
		return snapshot
	# Projection is already complete. A worker that merely echoes copied input
	# cannot speed it up; diagnostic detached publication needs no worker barrier.
	var slot := 0 if published_slot != 0 else 1
	buffers[slot] = Data.copy(snapshot)
	published_slot = slot
	return buffers[published_slot]
