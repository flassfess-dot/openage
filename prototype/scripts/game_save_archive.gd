class_name RoRGameSaveArchive
extends RefCounted

const ReplaySystem := preload("res://scripts/replay_system.gd")
const FORMAT_VERSION := 1
const SAVE_PATH := "user://saves/quicksave.json"
const MAX_TICK := 20_000_000


static func create(match_path: String, match_definition: Dictionary, tick: int, state_hash: String, replay: Dictionary, ai_states: Array, view_state: Dictionary, controller_state: Dictionary) -> Dictionary:
	var codec := ReplaySystem.new()
	return {
		"format_version": FORMAT_VERSION,
		"match_path": match_path,
		"match_fingerprint": fingerprint(match_definition),
		"tick": tick,
		"state_sha256": state_hash,
		"replay": replay.duplicate(true),
		"ai_states": codec.encode_variant(ai_states),
		"view_state": codec.encode_variant(view_state),
		"controller_state": codec.encode_variant(controller_state),
	}


static func fingerprint(match_definition: Dictionary) -> String:
	var codec := ReplaySystem.new()
	var canonical := JSON.stringify(codec.encode_variant(match_definition))
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(canonical.to_utf8_buffer())
	return hashing.finish().hex_encode()


static func validate(data: Dictionary) -> String:
	if int(data.get("format_version", -1)) != FORMAT_VERSION:
		return "unsupported_version"
	if String(data.get("match_path", "")).is_empty() or String(data.get("match_fingerprint", "")).is_empty():
		return "match_identity_missing"
	var tick := int(data.get("tick", -1))
	if tick < 0 or tick > MAX_TICK:
		return "tick_out_of_range"
	if String(data.get("state_sha256", "")).length() != 64:
		return "state_hash_invalid"
	if not data.get("replay") is Dictionary:
		return "replay_missing"
	var replay := ReplaySystem.new()
	if not replay.load_dictionary(data["replay"]):
		return "replay_invalid"
	if int(replay.simulation_seed) <= 0:
		return "seed_invalid"
	return ""


static func decoded(data: Dictionary) -> Dictionary:
	var error := validate(data)
	if not error.is_empty():
		return {"valid": false, "error": error, "archive": {}}
	var codec := ReplaySystem.new()
	var archive := data.duplicate(true)
	archive["ai_states"] = codec.decode_variant(data.get("ai_states", []))
	archive["view_state"] = codec.decode_variant(data.get("view_state", {}))
	archive["controller_state"] = codec.decode_variant(data.get("controller_state", {}))
	return {"valid": true, "error": "", "archive": archive}


static func read(path: String = SAVE_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "error": "save_not_found", "archive": {}}
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {"valid": false, "error": "json_invalid", "archive": {}}
	return decoded(parsed)


static func write(path: String, archive: Dictionary) -> Error:
	var validation_error := validate(archive)
	if not validation_error.is_empty():
		return ERR_INVALID_DATA
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var temporary_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(archive, "\t"))
	file.flush()
	file.close()
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	if FileAccess.file_exists(absolute_path):
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temporary_path)
			return backup_error
	var replace_error := DirAccess.rename_absolute(temporary_path, absolute_path)
	if replace_error != OK and FileAccess.file_exists(backup_path):
		DirAccess.rename_absolute(backup_path, absolute_path)
	return replace_error
