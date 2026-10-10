class_name RoRBackgroundSaveTask
extends RefCounted

const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Archive := preload("res://scripts/game_save_archive.gd")

static func run(input: Dictionary) -> Dictionary:
	var packed: Dictionary = Checkpoint.pack(input["checkpoint"])
	if packed.is_empty(): return {"error": int(ERR_INVALID_DATA), "path": input["path"], "slot_name": input["slot_name"], "tick": input["tick"]}
	var archive := Archive.create(String(input["match_path"]), input["definition"], int(input["tick"]), String(packed["sha256"]), input["replay"], input["ai_states"], input["view"], input["controller"], String(input["slot_name"]), packed)
	var error := Archive.write(String(input["path"]), archive)
	return {"error": int(error), "path": input["path"], "slot_name": input["slot_name"], "tick": input["tick"]}
