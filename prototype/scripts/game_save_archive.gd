class_name RoRGameSaveArchive
extends RefCounted

const ReplaySystem := preload("res://scripts/replay_system.gd")
const DecisionQueue := preload("res://scripts/ai_decision_queue.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const SoundCueHistory := preload("res://scripts/sound_cue_history.gd")
const FORMAT_VERSION := 8
const CHECKPOINT_FORMAT_VERSION := FORMAT_VERSION
const SAVE_PATH := "user://saves/quicksave.json"
const AUTOSAVE_PATH := "user://saves/autosave.json"
const AUTOSAVE_NAME := "Автосохранение"
const NAMED_SAVE_DIRECTORY := "user://saves/named"
const MAX_SLOT_NAME_LENGTH := 64
const MAX_TICK := 20_000_000
const REQUIRED_FEATURES := ["incremental_runtime_v2", "world_checkpoint", "population_points", "order_queues", "fog_memory", "sound_cue_history", "match_rules", "adaptive_ai_v1", "gates_v1", "competitive_ai_v2", "resource_ledger_v1", "team_intents_v1"]


static func create(match_path: String, match_definition: Dictionary, tick: int, _state_hash: String, replay: Dictionary, ai_states: Array, view_state: Dictionary, controller_state: Dictionary, slot_name: String = "Быстрое сохранение", checkpoint: Dictionary = {}, owns_replay: bool = false) -> Dictionary:
	if checkpoint.is_empty():
		push_error("Current save format requires a checkpoint")
		return {}
	var codec := ReplaySystem.new()
	if controller_state.has("_ai_decision_view"):
		controller_state = controller_state.duplicate()
		controller_state["ai_decisions"] = DecisionQueue.encode_save_view(controller_state["_ai_decision_view"])
		controller_state.erase("_ai_decision_view")
	var saved_view := view_state.duplicate(true)
	if not saved_view.has("sound_cue_history"):
		saved_view["sound_cue_history"] = SoundCueHistory.empty_state()
	var settings: Dictionary = match_definition.get("skirmish_settings", {})
	var map: Dictionary = match_definition.get("map", {})
	var result := {
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
		"state_sha256": String(checkpoint["sha256"]),
		"replay": replay if owns_replay else replay.duplicate(true),
		# Pending plans compare against the exact captured AI state on restore.
		"ai_states": ai_states.map(func(state): return codec.encode_exact_variant(state)),
		"view_state": codec.encode_variant(saved_view),
		"controller_state": codec.encode_variant(controller_state),
	}
	result["checkpoint"] = checkpoint
	return result


static func fingerprint(match_definition: Dictionary) -> String:
	var codec := ReplaySystem.new()
	var canonical := JSON.stringify(codec.encode_variant(match_definition))
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(canonical.to_utf8_buffer())
	return hashing.finish().hex_encode()


static func validate(data: Dictionary) -> String:
	var version := int(data.get("format_version", -1))
	if version != FORMAT_VERSION:
		return "unsupported_version"
	var features: Variant = data.get("schema_features", [])
	if not features is Array or not REQUIRED_FEATURES.all(func(feature): return feature in features):
		return "schema_features_missing"
	var blob: Variant = data.get("checkpoint")
	if not blob is Dictionary or int(blob.get("version", -1)) != Checkpoint.VERSION or String(blob.get("sha256", "")).length() != 64 or String(blob.get("data", "")).is_empty():
		return "checkpoint_invalid"
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
	if not ReplaySystem.valid_dictionary(data["replay"]):
		return "replay_invalid"
	if int(data["replay"].get("simulation_seed", 1)) <= 0:
		return "seed_invalid"
	return ""


static func decoded(data: Dictionary) -> Dictionary:
	var error := validate(data)
	if not error.is_empty():
		return {"valid": false, "error": error, "archive": {}}
	var codec := ReplaySystem.new()
	var archive := data.duplicate(true)
	archive["ai_states"] = codec.decode_variant(data.get("ai_states", []))
	if not archive["ai_states"].all(func(state): return state is Dictionary):
		return {"valid": false, "error": "ai_state_invalid", "archive": {}}
	archive["view_state"] = codec.decode_variant(data.get("view_state", {}))
	archive["controller_state"] = codec.decode_variant(data.get("controller_state", {}))
	return {"valid": true, "error": "", "archive": archive}


static func read(path: String = SAVE_PATH) -> Dictionary:
	# Earlier writers could be interrupted after moving the committed slot to
	# .bak. Recover that complete archive only when the primary file is absent.
	var stored_path := path if FileAccess.file_exists(path) else path + ".bak"
	var file := FileAccess.open(stored_path, FileAccess.READ)
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
	if not valid_slot_name(name) or normalized_slot_name(name) == AUTOSAVE_NAME:
		return ""
	return "%s/slot_%s.json" % [directory, fingerprint({"slot_name": normalized_slot_name(name)}).substr(0, 24)]


const HEADER_BYTES := 4096
const LEGACY_SCAN_BYTES := 128 * 1024


# Previous writers indented and sorted the JSON. Its top-level members have
# exactly one tab. A JSON string cannot contain this literal newline + tab.
static func _legacy_fields(bytes: PackedByteArray, summary: Dictionary) -> void:
	var text := bytes.get_string_from_ascii() # One character per byte, including non-ASCII bytes.
	for field in ["format_version", "tick"]:
		if summary.has(field): continue
		var prefix := "\n\t\"%s\": " % field
		var start := text.find(prefix)
		if start < 0: continue
		start += prefix.length()
		var end := text.find(",", start)
		if end < 0 or end - start > 20: continue
		var number := text.substr(start, end - start)
		if number.is_valid_int(): summary[field] = number.to_int()
	if summary.has("metadata"): return
	var marker := "\n\t\"metadata\": "
	var start := text.find(marker)
	if start < 0: return
	start += marker.length()
	var end := text.find("\n\t}", start)
	if end < 0: return
	var metadata: Variant = JSON.parse_string(bytes.slice(start, end + 3).get_string_from_utf8())
	if metadata is Dictionary: summary["metadata"] = metadata


static func _slot_summary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var length := file.get_length()
	var first := file.get_buffer(mini(length, HEADER_BYTES))
	var end := first.find(10)
	if end >= 0 and first.size() > 2 and first[1] == 34:
		var header := first.slice(0, end).get_string_from_utf8()
		if header.begins_with("{\"format_version\":") and header.ends_with(","):
			var parsed: Variant = JSON.parse_string(header.left(-1) + "}")
			if parsed is Dictionary and parsed.has("metadata") and parsed.has("tick"): return parsed
	if first.size() > 3 and first[0] == 123 and first[1] == 10 and first[2] == 9:
		var summary := {}
		_legacy_fields(first, summary)
		# All supported historical writers placed the tick near the end, and
		# metadata after the large checkpoint/AI fields. Stop as soon as known.
		var right := length
		while not summary.has("format_version") or (int(summary["format_version"]) == FORMAT_VERSION and summary.size() < 3):
			if right <= first.size(): break
			var left := maxi(0, right - LEGACY_SCAN_BYTES)
			file.seek(left)
			_legacy_fields(file.get_buffer(right - left), summary)
			if left == 0: break
			right = left + HEADER_BYTES
		if summary.has("format_version") and (int(summary["format_version"]) != FORMAT_VERSION or summary.size() == 3): return summary
	# Other valid JSON layouts (e.g. an externally reformatted legacy save).
	file.seek(0)
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary: return {}
	return {"format_version":data.get("format_version", -1), "metadata":data.get("metadata", {}), "tick":data.get("tick", 0)}


static func list_named_saves(directory_path: String = NAMED_SAVE_DIRECTORY) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return result
	for stored_filename in directory.get_files():
		var filename := String(stored_filename).trim_suffix(".bak") if String(stored_filename).ends_with(".json.bak") else String(stored_filename)
		if not filename.begins_with("slot_") or not filename.ends_with(".json"):
			continue
		var path := "%s/%s" % [directory_path, filename]
		if stored_filename != filename and FileAccess.file_exists(path): continue
		var parsed := _slot_summary(directory_path.path_join(stored_filename))
		if int(parsed.get("format_version", -1)) != FORMAT_VERSION: continue
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


static func list_saves(named_directory: String = NAMED_SAVE_DIRECTORY, quick_path: String = SAVE_PATH, autosave_path: String = AUTOSAVE_PATH) -> Array[Dictionary]:
	var entries := list_named_saves(named_directory)
	for path in [autosave_path, quick_path]:
		var stored_path: String = path if FileAccess.file_exists(path) else path + ".bak"
		if not FileAccess.file_exists(stored_path): continue
		var data := _slot_summary(stored_path)
		if int(data.get("format_version", -1)) == FORMAT_VERSION and data.get("metadata") is Dictionary:
			var metadata: Dictionary = data["metadata"]
			entries.append({"path": path, "slot_name": AUTOSAVE_NAME if path == autosave_path else "Быстрое сохранение", "saved_at_unix": int(metadata.get("saved_at_unix", 0)), "tick": int(data.get("tick", 0)), "quicksave": path == quick_path, "autosave": path == autosave_path})
	entries.sort_custom(func(left, right):
		if int(left["saved_at_unix"]) != int(right["saved_at_unix"]):
			return int(left["saved_at_unix"]) > int(right["saved_at_unix"])
		return String(left["slot_name"]) < String(right["slot_name"])
	)
	return entries

static func commit_autosave(staging_path: String, target_path: String = AUTOSAVE_PATH, preserve_previous: bool = false) -> Error:
	# Rename in the same directory replaces the destination atomically. Never
	# remove/move the previous slot before the complete new file is in place.
	if not ClassDB.class_exists("RoRSaveFileKernel"): return ERR_UNAVAILABLE
	var kernel = ClassDB.instantiate("RoRSaveFileKernel")
	var source := ProjectSettings.globalize_path(staging_path)
	var destination := ProjectSettings.globalize_path(target_path)
	if preserve_previous and FileAccess.file_exists(destination):
		if not FileAccess.file_exists(source) or source == destination or source.get_base_dir() != destination.get_base_dir(): return ERR_INVALID_PARAMETER
		var backup_stage := destination + ".%d-%d.bak.tmp" % [OS.get_process_id(), kernel.get_instance_id()]
		# Published slot files are only ever replaced, never edited in place.
		# A link holds the previous version even after its main name is replaced.
		if not kernel.has_method("link_for_backup") or not kernel.link_for_backup(destination, backup_stage):
			var copy_error := DirAccess.copy_absolute(destination, backup_stage)
			if copy_error != OK:
				DirAccess.remove_absolute(backup_stage)
				return copy_error
		var backup_error: Error = kernel.replace_atomic(backup_stage, destination + ".bak")
		# POSIX rename may keep the source if both names already link to the
		# same previous version (e.g. after a retry).
		if FileAccess.file_exists(backup_stage): DirAccess.remove_absolute(backup_stage)
		if backup_error != OK: return backup_error
	return kernel.replace_atomic(source, destination)

static func with_autosave_result(entries: Array[Dictionary], result: Dictionary) -> Array[Dictionary]:
	var automatic := result.duplicate()
	automatic["kind"] = "autosave"
	return with_save_result(entries, automatic)


static func with_save_result(entries: Array[Dictionary], result: Dictionary) -> Array[Dictionary]:
	# Completion updates a cached menu model; it must not reread every archive
	# on the render thread just because an automatic write finished.
	var updated: Array[Dictionary] = []
	var path := String(result["path"])
	var automatic: bool = result.get("kind") == "autosave" or path == AUTOSAVE_PATH
	var quick: bool = result.get("kind") == "quick" or path == SAVE_PATH
	for entry in entries:
		if String(entry.get("path", "")) != path and not (automatic and entry.get("autosave", false)): updated.append(entry)
	updated.append({"path":path, "slot_name":AUTOSAVE_NAME if automatic else "Быстрое сохранение" if quick else String(result["slot_name"]),
		"saved_at_unix":int(result.get("saved_at_unix", 0)), "tick":int(result["tick"]), "autosave":automatic, "quicksave":quick,
		"map_type_id":String(result.get("map_type_id", "")), "victory_mode_id":String(result.get("victory_mode_id", "")), "format_version":FORMAT_VERSION})
	updated.sort_custom(func(a, b):
		if int(a.get("saved_at_unix", 0)) != int(b.get("saved_at_unix", 0)): return int(a.get("saved_at_unix", 0)) > int(b.get("saved_at_unix", 0))
		return String(a.get("slot_name", "")) < String(b.get("slot_name", ""))
	)
	return updated

static func error_message(error: String) -> String:
	if error.begins_with("state_hash_mismatch"):
		return "Состояние сохранения не совпало с записью команд"
	match error:
		"load_worker_unavailable", "load_worker_failed": return "Не удалось подготовить загрузку. Повторите попытку"
		"load_cancelled": return "Загрузка отменена"
		"catalogs_unavailable": return "Не удалось прочитать игровые данные"
		"save_busy": return "Дождитесь завершения текущего сохранения"
		"capture_not_isolated": return "Не удалось подготовить согласованное сохранение"
		"checkpoint_invalid":
			return "Сохранение повреждено: не удалось восстановить состояние мира"
		"save_not_found": return "Сохранение не найдено"
		"unsupported_version": return "Старый формат сохранения не поддерживается. Начните новую игру"
		"metadata_invalid", "schema_features_missing", "state_sections_missing", "json_invalid", "replay_invalid", "state_hash_invalid", "sound_cue_history_invalid": return "Сохранение повреждено или неполно"
		"match_path_mismatch", "match_fingerprint_mismatch": return "Сохранение относится к другой игре или настройкам матча"
		"slot_name_invalid": return "Введите имя сохранения длиной до 64 символов"
		"slot_name_reserved": return "Это имя используется автосохранением. Введите другое имя"
		_: return "Не удалось загрузить или сохранить игру (%s)" % error


static func write(path: String, archive: Dictionary, _atomic_replace: bool = true, progress: Callable = Callable(), preserve_previous: bool = false) -> Error:
	var validation_error := validate(archive)
	if not validation_error.is_empty():
		return ERR_INVALID_DATA
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK:
		return directory_error
	var handle := RefCounted.new()
	var temporary_path := absolute_path + ".%d-%d.tmp" % [OS.get_process_id(), handle.get_instance_id()]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var header := {"format_version":archive["format_version"], "tick":archive["tick"], "metadata":archive["metadata"]}
	var remaining: Array = archive.keys().filter(func(field): return not header.has(field))
	var total := remaining.size() + 1
	if progress.is_valid(): progress.call("writing", 0, total)
	var stored := file.store_string(JSON.stringify(header, "", false, true).left(-1) + ",\n")
	for i in range(remaining.size()):
		if not stored: break
		var field: String = remaining[i]
		# Write a section at a time so the whole UTF-32 JSON and UTF-8 file
		# buffer are never materialized together. Numeric precision stays exact.
		stored = file.store_string(JSON.stringify(field) + ":") and file.store_string(JSON.stringify(archive[field], "", false, true))
		stored = stored and file.store_string("}" if i + 1 == remaining.size() else ",\n")
		if stored and progress.is_valid(): progress.call("writing", i + 2, total)
	var write_error := file.get_error() if stored else ERR_FILE_CANT_WRITE
	file.flush()
	if write_error == OK: write_error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary_path)
		return write_error
	if progress.is_valid(): progress.call("committing", 0, 0)
	var result := commit_autosave(temporary_path, absolute_path, preserve_previous)
	if result != OK: DirAccess.remove_absolute(temporary_path)
	return result
