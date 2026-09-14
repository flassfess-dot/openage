extends SceneTree

const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")

const TEST_PATH := "res://qa/e3-save-archive-test.json"

var failures: Array[String] = []


func _initialize() -> void:
	cleanup()
	var replay := ReplaySystem.new()
	replay.begin(41721)
	var definition := {"id": "prototype", "players": [{"team": 1, "civilization_id": 13}]}
	var archive := GameSaveArchive.create(
		"res://data/matches/prototype_match.json",
		definition,
		12,
		"a".repeat(64),
		replay.to_dictionary(),
		[{"team": 2, "anchor": Vector2(4.5, 8.5)}],
		{"view_offset": Vector2(100, 200), "selection": [3]},
		{"speed": 1.5, "paused": false}
	)
	assert_equal(GameSaveArchive.validate(archive), "", "valid archive satisfies the versioned contract")
	assert_equal(GameSaveArchive.fingerprint(definition), GameSaveArchive.fingerprint(definition.duplicate(true)), "match fingerprint is deterministic")
	assert_equal(GameSaveArchive.write(TEST_PATH, archive), OK, "valid archive is written atomically")
	var loaded: Dictionary = GameSaveArchive.read(TEST_PATH)
	assert_true(bool(loaded.get("valid", false)), "written archive reads back")
	var decoded: Dictionary = loaded.get("archive", {})
	assert_equal(decoded.get("view_state", {}).get("view_offset"), Vector2(100, 200), "view vectors survive JSON round trip")
	assert_equal(decoded.get("ai_states", [])[0].get("anchor"), Vector2(4.5, 8.5), "AI vectors survive JSON round trip")

	var invalid := archive.duplicate(true)
	invalid["format_version"] = 99
	assert_equal(GameSaveArchive.validate(invalid), "unsupported_version", "unknown save versions fail closed")
	invalid = archive.duplicate(true)
	invalid["state_sha256"] = "short"
	assert_equal(GameSaveArchive.validate(invalid), "state_hash_invalid", "truncated state hash is rejected")
	cleanup()

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


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
