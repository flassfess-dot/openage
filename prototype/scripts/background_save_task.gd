class_name RoRBackgroundSaveTask
extends RefCounted

const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Archive := preload("res://scripts/game_save_archive.gd")

static func run(input: Dictionary) -> Dictionary:
	var archive := Archive.create(String(input["match_path"]), input["definition"], int(input["tick"]), String(input["state_hash"]), input["replay"], input["ai_states"], input["view"], input["controller"], String(input["slot_name"]), Checkpoint.pack(input["checkpoint"]))
	var error := Archive.write(String(input["path"]), archive)
	return {"error": int(error), "path": input["path"], "slot_name": input["slot_name"], "tick": input["tick"]}
