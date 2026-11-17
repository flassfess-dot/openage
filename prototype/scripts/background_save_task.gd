class_name RoRBackgroundSaveTask
extends RefCounted

const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Archive := preload("res://scripts/game_save_archive.gd")

class Progress extends RefCounted:
	var mutex := Mutex.new()
	var state: Dictionary = {}

	func update(stage: String, completed: int = 0, total: int = 0) -> void:
		mutex.lock()
		state = {"stage":stage, "completed":completed, "total":total}
		mutex.unlock()

	func read() -> Dictionary:
		mutex.lock()
		var current := state
		mutex.unlock()
		return current.duplicate()

static func run(input: Dictionary, progress: Callable = Callable()) -> Dictionary:
	var result := {"kind":input.get("kind", "manual"), "path":input["path"], "slot_name":input["slot_name"], "tick":input["tick"]}
	var packed: Dictionary = Checkpoint.pack(input["checkpoint"], progress)
	if packed.is_empty():
		result["error"] = int(ERR_INVALID_DATA)
		return result
	var archive := Archive.create(String(input["match_path"]), input["definition"], int(input["tick"]), String(packed["sha256"]), input["replay"], input["ai_states"], input["view"], input["controller"], String(input["slot_name"]), packed, true)
	var error := Archive.write(String(input["path"]), archive, bool(input.get("atomic_replace", false)), progress, not input.get("_stage_for_commit", false))
	result["error"] = int(error)
	result.merge(archive.get("metadata", {}))
	return result
