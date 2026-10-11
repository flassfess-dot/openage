extends SceneTree

const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")

const TEST_PATH := "res://qa/e3-save-archive-test.json"
const TEST_NAMED_DIRECTORY := "res://qa/e3-named-save-tests"

var failures: Array[String] = []


func _initialize() -> void:
	cleanup()
	var replay := ReplaySystem.new()
	replay.begin(41721)
	var definition := {"id": "prototype", "players": [{"team": 1, "civilization_id": 13}]}
	var world := World.new(Vector2i(16, 16))
	var controller := Controller.new(world)
	controller.tick_index = 12
	var checkpoint := Checkpoint.pack(Checkpoint.capture(world, controller, definition, {"size": world.map_size}))
	var archive := GameSaveArchive.create(
		"res://data/matches/prototype_match.json",
		definition,
		12,
		"a".repeat(64),
		replay.to_dictionary(),
		[{"team": 2, "anchor": Vector2(4.5, 8.5)}],
		{"view_offset": Vector2(100, 200), "selection": [3]},
		{"speed": 1.5, "paused": false},
		"Быстрое сохранение",
		checkpoint
	)
	assert_equal(GameSaveArchive.validate(archive), "", "valid archive satisfies the versioned contract")
	assert_equal(int(archive.get("format_version", 0)), GameSaveArchive.FORMAT_VERSION, "new save uses the current checkpoint schema")
	for feature in ["population_points", "order_queues", "fog_memory", "sound_cue_history", "match_rules"]:
		assert_true(feature in archive.get("schema_features", []), "save schema declares %s" % feature)
	assert_true(archive.get("view_state", {}).has("sound_cue_history"), "archive always includes sound-cue history state")
	assert_equal(String(archive.get("metadata", {}).get("slot_name", "")), "Быстрое сохранение", "quick save keeps its dedicated metadata name")
	assert_equal(GameSaveArchive.fingerprint(definition), GameSaveArchive.fingerprint(definition.duplicate(true)), "match fingerprint is deterministic")
	assert_equal(GameSaveArchive.write(TEST_PATH, archive), OK, "valid archive is written atomically")
	var loaded: Dictionary = GameSaveArchive.read(TEST_PATH)
	assert_true(bool(loaded.get("valid", false)), "written archive reads back")
	var decoded: Dictionary = loaded.get("archive", {})
	assert_equal(decoded.get("view_state", {}).get("view_offset"), Vector2(100, 200), "view vectors survive JSON round trip")
	assert_equal(decoded.get("ai_states", [])[0].get("anchor"), Vector2(4.5, 8.5), "AI vectors survive JSON round trip")
	assert_equal(Checkpoint.unpack(decoded.get("checkpoint", {}))["controller"]["tick"], 12, "checkpoint retains the exact saved tick through JSON")
	var first_path: String = GameSaveArchive.named_path("Рим", TEST_NAMED_DIRECTORY)
	var second_path: String = GameSaveArchive.named_path("Карфаген", TEST_NAMED_DIRECTORY)
	assert_true(first_path != second_path and first_path.begins_with(TEST_NAMED_DIRECTORY + "/"), "distinct names receive path-safe stable slots")
	assert_equal(GameSaveArchive.named_path(" Рим ", TEST_NAMED_DIRECTORY), first_path, "trimming a slot name targets the same named save")
	assert_equal(GameSaveArchive.named_path("", TEST_NAMED_DIRECTORY), "", "empty slot name is rejected")
	assert_equal(GameSaveArchive.write(first_path, GameSaveArchive.create("res://data/matches/prototype_match.json", definition, 12, "a".repeat(64), replay.to_dictionary(), [], {}, {}, "Рим", checkpoint)), OK, "first named save writes")
	controller.tick_index = 14
	var second_checkpoint := Checkpoint.pack(Checkpoint.capture(world, controller, definition, {"size": world.map_size}))
	assert_equal(GameSaveArchive.write(second_path, GameSaveArchive.create("res://data/matches/prototype_match.json", definition, 14, "b".repeat(64), replay.to_dictionary(), [], {}, {}, "Карфаген", second_checkpoint)), OK, "second named save writes without replacing the first")
	var named: Array[Dictionary] = GameSaveArchive.list_named_saves(TEST_NAMED_DIRECTORY)
	assert_equal(named.size(), 2, "named save catalog lists both slots")
	assert_true(named.any(func(entry): return String(entry.get("slot_name", "")) == "Рим" and int(entry.get("tick", 0)) == 12), "named save catalog exposes first slot metadata")
	assert_true(named.any(func(entry): return String(entry.get("slot_name", "")) == "Карфаген" and int(entry.get("tick", 0)) == 14), "named save catalog exposes second slot metadata")
	assert_true(bool(GameSaveArchive.read(TEST_PATH).get("valid", false)), "named saves leave the quick-save path intact")

	var invalid := archive.duplicate(true)
	invalid["format_version"] = 1
	assert_equal(GameSaveArchive.validate(invalid), "unsupported_version", "pre-fixed-point saves fail explicitly instead of mismatching on replay")
	invalid["format_version"] = 2
	assert_equal(GameSaveArchive.validate(invalid), "unsupported_version", "previous save schema receives an explicit compatibility refusal")
	assert_true(GameSaveArchive.error_message("unsupported_version").contains("Старый формат"), "compatibility refusal is understandable in the menu")
	invalid = archive.duplicate(true)
	invalid["format_version"] = 99
	assert_equal(GameSaveArchive.validate(invalid), "unsupported_version", "unknown save versions fail closed")
	invalid = archive.duplicate(true)
	invalid.erase("checkpoint")
	assert_equal(GameSaveArchive.validate(invalid), "checkpoint_invalid", "a current archive requires its checkpoint")
	invalid = archive.duplicate(true)
	invalid["state_sha256"] = "short"
	assert_equal(GameSaveArchive.validate(invalid), "state_hash_invalid", "truncated state hash is rejected")
	invalid = archive.duplicate(true)
	invalid["schema_features"].erase("fog_memory")
	assert_equal(GameSaveArchive.validate(invalid), "schema_features_missing", "incomplete schema contract fails closed")
	cleanup()
	world.shutdown_derived_state()

	if failures.is_empty():
		print("E3 versioned game save archive tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for name in ["Рим", "Карфаген"]:
		var slot_path: String = GameSaveArchive.named_path(name, TEST_NAMED_DIRECTORY)
		for suffix in ["", ".tmp", ".bak"]:
			var absolute_slot: String = ProjectSettings.globalize_path(slot_path + suffix)
			if FileAccess.file_exists(absolute_slot):
				DirAccess.remove_absolute(absolute_slot)
	var absolute_directory: String = ProjectSettings.globalize_path(TEST_NAMED_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
