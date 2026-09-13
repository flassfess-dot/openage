extends SceneTree

const BASELINE_PATH := "res://data/source_ai/default_vc.json"
const SYRACUSE_MATCH_PATH := "res://assets/generated/matches/syracuse.json"
const MITHRIDATES_MATCH_PATH := "res://assets/generated/matches/mithridates.json"
const EXPECTED_ENTRY_SHA256 := "ee2e709bce9538c0ef9a233fab842c03051ed2b6112de62955a52f77b2b8459b"
const EXPECTED_ARCHIVE_SHA256 := "5f18fd552a804bf6d92e52f41e6e68e62b64e716843f462a1e074c824195faed"

var failures: Array[String] = []


func _initialize() -> void:
	var baseline := read_json(BASELINE_PATH)
	assert_equal(int(baseline.get("schema_version", 0)), 1, "DEFAULT.VC catalog schema")
	assert_equal(String(baseline.get("baseline_id", "")), "ror_1_0a_default_vc", "baseline identity")
	assert_equal(String(baseline.get("source_name", "")), "DEFAULT.VC", "source filename")
	assert_equal(String(baseline.get("source_entry_sha256", "")), EXPECTED_ENTRY_SHA256, "source entry hash")
	assert_equal(String(baseline.get("source_archive_sha256", "")), EXPECTED_ARCHIVE_SHA256, "source archive hash")
	assert_equal(String(baseline.get("status", "")), "cataloged_partial_runtime", "catalog does not overclaim executable parity")

	var entries: Array = baseline.get("entries", [])
	assert_equal(entries.size(), 149, "full historic DEFAULT.VC entry count")
	var by_id: Dictionary = {}
	for entry_value in entries:
		if not entry_value is Dictionary:
			failures.append("DEFAULT.VC entry is not a dictionary")
			continue
		var source_id := int(entry_value.get("source_id", -1))
		assert_true(not by_id.has(source_id), "source ID %d is unique" % source_id)
		by_id[source_id] = entry_value
	assert_equal(by_id.size(), 149, "all catalog entries have unique source IDs")
	assert_equal(int(by_id.keys().min()), 0, "catalog minimum source ID")
	assert_equal(int(by_id.keys().max()), 162, "catalog maximum source ID")
	for expected in {
		0: 34,
		16: 4,
		36: 2,
		58: 2,
		77: 4,
		79: 1,
		83: 1,
		88: 2,
		104: 0,
		162: 0,
	}:
		assert_true(by_id.has(expected), "catalog contains source ID %d" % expected)
		if by_id.has(expected):
			assert_equal(int(by_id[expected].get("value", -9999)), int({
				0: 34,
				16: 4,
				36: 2,
				58: 2,
				77: 4,
				79: 1,
				83: 1,
				88: 2,
				104: 0,
				162: 0,
			}[expected]), "catalog value for source ID %d" % expected)

	var syracuse := read_json(SYRACUSE_MATCH_PATH)
	for player_index in [1, 2, 3]:
		assert_directive_status(syracuse, player_index, "DEFAULT", "recognized_pending_baseline")
	assert_build_list_pending(syracuse, 3)

	var mithridates := read_json(MITHRIDATES_MATCH_PATH)
	for player_index in [1, 2]:
		assert_directive_status(mithridates, player_index, "RANDOM", "source_random_default_pending")
	assert_directive_status(mithridates, 4, "DEFAULT", "recognized_pending_baseline")
	assert_build_list_pending(mithridates, 4)

	if failures.is_empty():
		print("I12-020L source DEFAULT.VC baseline catalog tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_directive_status(match_definition: Dictionary, player_index: int, directive_name: String, expected_status: String) -> void:
	var players: Array = match_definition.get("players", [])
	if player_index < 0 or player_index >= players.size():
		failures.append("missing player index %d" % player_index)
		return
	var source_ai: Dictionary = players[player_index].get("source_ai", {})
	var matching: Array = source_ai.get("source_rule_directives", []).filter(
		func(entry): return String(entry.get("name", "")).to_upper() == directive_name
	)
	assert_equal(matching.size(), 1, "player %d preserves %s exactly once" % [player_index, directive_name])
	if matching.size() == 1:
		assert_equal(String(matching[0].get("runtime_status", "")), expected_status, "%s remains evidence-gated" % directive_name)


func assert_build_list_pending(match_definition: Dictionary, player_index: int) -> void:
	var players: Array = match_definition.get("players", [])
	if player_index < 0 or player_index >= players.size():
		failures.append("missing player index %d" % player_index)
		return
	var source_ai: Dictionary = players[player_index].get("source_ai", {})
	assert_equal(String(source_ai.get("build_list_name", "")), "Random", "random build-list name is preserved")
	assert_equal(String(source_ai.get("build_order_status", "")), "source_random_default_pending", "random build-list execution remains pending")


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		failures.append("missing JSON: %s" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		failures.append("invalid JSON: %s" % path)
		return {}
	return parsed


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
