extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

const MATCH_PATH := "res://assets/generated/matches/metaurus.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	assert_true(bool(definition.get("valid", false)), "Metaurus match validates: %s" % [definition.get("errors", [])])
	assert_equal(String(definition.get("id", "")), "campaign_metaurus", "stable runtime id survives generic conversion")
	assert_equal(String(definition.get("title", "")), "Метавр", "source mission title survives generic conversion")
	assert_equal(definition.get("map", {}).get("size"), Vector2i(200, 200), "source map size survives conversion")
	assert_equal(definition.get("players", []).size(), 3, "all three active source players are present")
	assert_equal(int(definition.get("local_team", -1)), 1, "Roman player remains local")
	assert_equal(int(definition.get("gaps", {}).get("source_object_count", -1)), 10761, "gap ledger owns every source object")
	assert_equal(int(definition.get("gaps", {}).get("runtime_entity_count", -1)), 6872, "all simulation-owned objects enter runtime")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_object_count", -1)), 0, "Metaurus has no unsupported source objects")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_legacy_victory_condition_count", -1)), 0, "Metaurus has no unsupported legacy conditions")
	assert_equal(int(definition.get("entities", []).filter(func(entity): return int(entity.get("source_unit_id", -1)) == 362).size()), 5, "five Alligator King source objects use the shared predator vertical")

	var rule_types: Array = definition.get("victory_rules", []).map(func(rule): return String(rule.get("type", "")))
	assert_equal(rule_types, ["conquest", "artifacts", "ruins", "wonder"], "source Standard mode maps to all four classic victory paths")
	var wonder_rule: Dictionary = definition.get("victory_rules", []).filter(func(rule): return String(rule.get("type", "")) == "wonder")[0]
	assert_equal(float(wonder_rule.get("hold_seconds", -1.0)), 900.0, "source 9000-tick countdown becomes fifteen real minutes")
	assert_equal(int(definition.get("source_settings", {}).get("multiplayer_victory_type", -1)), 0, "source Standard victory identity is retained")
	var source_start_ages: Array = definition.get("source_settings", {}).get("player_start_ages", []).slice(0, 3)
	assert_equal(source_start_ages.map(func(value): return int(value)), [2, 2, 2], "all active teams retain Bronze Age source starts")
	assert_equal(int(definition.get("gaps", {}).get("source_settings", {}).get("gap_count", -1)), 0, "Metaurus source settings are completely represented")
	for player_value in definition.get("players", []):
		var player: Dictionary = player_value
		assert_equal(int(player.get("starting_age_technology_id", -1)), 102, "source Bronze Age maps to the shared technology id")

	if failures.is_empty():
		print("I12-020G imported Metaurus match contract tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
