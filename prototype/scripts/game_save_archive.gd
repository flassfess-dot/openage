class_name RoRGameSaveArchive
extends RefCounted

const ReplaySystem := preload("res://scripts/replay_system.gd")
const SoundCueHistory := preload("res://scripts/sound_cue_history.gd")
const FORMAT_VERSION := 3
const SAVE_PATH := "user://saves/quicksave.json"
const NAMED_SAVE_DIRECTORY := "user://saves/named"
const MAX_SLOT_NAME_LENGTH := 64
const MAX_TICK := 20_000_000
const REQUIRED_FEATURES := ["population_points", "order_queues", "fog_memory", "sound_cue_history", "match_rules"]


static func create(match_path: String, match_definition: Dictionary, tick: int, state_hash: String, replay: Dictionary, ai_states: Array, view_state: Dictionary, controller_state: Dictionary, slot_name: String = "Быстрое сохранение") -> Dictionary:
	var codec := ReplaySystem.new()
	var saved_view := view_state.duplicate(true)
	if not saved_view.has("sound_cue_history"):
		saved_view["sound_cue_history"] = SoundCueHistory.empty_state()
	var settings: Dictionary = match_definition.get("skirmish_settings", {})
	var map: Dictionary = match_definition.get("map", {})
	return {
		"format_version": FORMAT_VERSION,
		"schema_features": REQUIRED_FEATURES.duplicate(),
		"metadata": {
			"slot_name": normalized_slot_name(slot_name),
			"saved_at_unix": int(Time.get_unix_time_from_system()),
			"map_type_id": String(settings.get("map_type_id", map.get("type_id", ""))),
			"victory_mode_id": String(settings.get("victory_mode_id", "")),
		},
		"match_path": match_path,
		"match_fingerprint": fingerprint(match_definition),
		"tick": tick,
		"state_sha256": state_hash,
		"replay": replay.duplicate(true),
		"ai_states": codec.encode_variant(ai_states),
		"view_state": codec.encode_variant(saved_view),
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
	var version := int(data.get("format_version", -1))
	if version == 2:
		return "legacy_version_2_unsupported"
	if version != FORMAT_VERSION:
		return "unsupported_version"
	var features: Variant = data.get("schema_features", [])
	if not features is Array or not REQUIRED_FEATURES.all(func(feature): return feature in features):
		return "schema_features_missing"
	var metadata: Variant = data.get("metadata")
	if not metadata is Dictionary or not valid_slot_name(String(metadata.get("slot_name", ""))) or int(metadata.get("saved_at_unix", 0)) <= 0:
		return "metadata_invalid"
	if String(data.get("match_path", "")).is_empty() or String(data.get("match_fingerprint", "")).is_empty():
		return "match_identity_missing"
	var tick := int(data.get("tick", -1))
	if tick < 0 or tick > MAX_TICK:
		return "tick_out_of_range"
	if String(data.get("state_sha256", "")).length() != 64:
		return "state_hash_invalid"
	if not data.get("replay") is Dictionary:
		return "replay_missing"
	if not data.get("ai_states") is Array or not data.get("view_state") is Dictionary or not data.get("controller_state") is Dictionary:
		return "state_sections_missing"
	if not data["view_state"].has("sound_cue_history"):
		return "state_sections_missing"
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


static func normalized_slot_name(name: String) -> String:
	return name.strip_edges()


static func valid_slot_name(name: String) -> bool:
	var normalized := normalized_slot_name(name)
	return not normalized.is_empty() and normalized.length() <= MAX_SLOT_NAME_LENGTH and not normalized.contains("\n") and not normalized.contains("\r") and not normalized.contains("\t")


static func named_path(name: String, directory: String = NAMED_SAVE_DIRECTORY) -> String:
	if not valid_slot_name(name):
		return ""
	return "%s/slot_%s.json" % [directory, fingerprint({"slot_name": normalized_slot_name(name)}).substr(0, 24)]


static func list_named_saves(directory_path: String = NAMED_SAVE_DIRECTORY) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	for filename in directory.get_files():
		if not filename.begins_with("slot_") or not filename.ends_with(".json"):
			continue
		var path := "%s/%s" % [directory_path, filename]
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		if not parsed is Dictionary:
			continue
		var metadata: Variant = parsed.get("metadata", {})
		if not metadata is Dictionary or not valid_slot_name(String(metadata.get("slot_name", ""))):
			continue
		result.append({
			"path": path,
			"slot_name": String(metadata.get("slot_name", "")),
			"saved_at_unix": int(metadata.get("saved_at_unix", 0)),
			"tick": int(parsed.get("tick", 0)),
			"map_type_id": String(metadata.get("map_type_id", "")),
			"victory_mode_id": String(metadata.get("victory_mode_id", "")),
			"format_version": int(parsed.get("format_version", -1)),
		})
	result.sort_custom(func(left, right):
		if int(left["saved_at_unix"]) != int(right["saved_at_unix"]):
			return int(left["saved_at_unix"]) > int(right["saved_at_unix"])
		return String(left["slot_name"]) < String(right["slot_name"])
	)
	return result


static func error_message(error: String) -> String:
	if error.begins_with("state_hash_mismatch"):
		return "Состояние сохранения не совпало с записью команд"
	match error:
		"save_not_found": return "Сохранение не найдено"
		"legacy_version_2_unsupported": return "Сохранение старого формата: начните новую игру или используйте сохранение версии 3"
		"unsupported_version": return "Версия сохранения не поддерживается"
		"metadata_invalid", "schema_features_missing", "state_sections_missing", "json_invalid", "replay_invalid", "state_hash_invalid", "sound_cue_history_invalid": return "Сохранение повреждено или неполно"
		"match_path_mismatch", "match_fingerprint_mismatch": return "Сохранение относится к другой игре или настройкам матча"
		"slot_name_invalid": return "Введите имя сохранения длиной до 64 символов"
		_: return "Не удалось загрузить или сохранить игру (%s)" % error


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
