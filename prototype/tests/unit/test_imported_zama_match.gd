extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

const MATCH_PATH := "res://assets/generated/matches/zama.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	assert_true(bool(definition.get("valid", false)), "Zama match validates: %s" % [definition.get("errors", [])])
	assert_equal(String(definition.get("id", "")), "campaign_zama", "stable runtime id survives conversion")
	assert_equal(String(definition.get("title", "")), "Зама", "source mission title survives conversion")
	assert_equal(definition.get("map", {}).get("size"), Vector2i(200, 200), "source map size survives conversion")
	assert_equal(definition.get("players", []).size(), 2, "both active source players are present")
	assert_equal(int(definition.get("local_team", -1)), 1, "Roman player remains local")
	assert_equal(int(definition.get("gaps", {}).get("source_object_count", -1)), 10645, "gap ledger owns every source object")
	assert_equal(int(definition.get("gaps", {}).get("runtime_entity_count", -1)), 6534, "all simulation-owned objects enter runtime")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_object_count", -1)), 0, "Zama has no unsupported source objects")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_legacy_victory_condition_count", -1)), 0, "Zama has no unsupported legacy conditions")
	assert_equal(int(definition.get("gaps", {}).get("source_settings", {}).get("gap_count", -1)), 0, "Zama source settings are completely represented")

	assert_source_count(definition, 6, 7, "seven Composite Bowmen reuse the shared source variant")
	assert_source_count(definition, 38, 8, "eight Heavy Cavalry reuse the shared source variant")
	assert_source_count(definition, 39, 11, "eleven Horse Archers retain exact source identity")
	assert_source_count(definition, 345, 6, "six Armored Elephants reuse the shared source archetype")
	var flags: Array = definition.get("presentation_markers", []).filter(func(marker): return int(marker.get("source_unit_id", -1)) == 330)
	assert_equal(flags.size(), 12, "all twelve source army flags remain presentation-owned")
	assert_equal(flags.filter(func(marker): return String(marker.get("asset_name", "")) == "graphic_322_p1").size(), 4, "four Roman flags use player-one colors")
	assert_equal(flags.filter(func(marker): return String(marker.get("asset_name", "")) == "graphic_322_p2").size(), 8, "eight Carthaginian flags use player-two colors")

	var players: Array = definition.get("players", [])
	assert_equal(players.map(func(player): return int(player.get("starting_age_technology_id", -1))), [103, 103], "both source starts resolve to Iron Age")
	assert_equal(players.map(func(player): return String(player.get("starting_technology_mode", ""))), ["age_start", "post_iron"], "Carthaginian Post-Iron semantics remain explicit")
	assert_equal(definition.get("scenario_definition", {}).get("participants", []).size(), 0, "Zama has no invented legacy objectives")
	var rule_types: Array = definition.get("victory_rules", []).map(func(rule): return String(rule.get("type", "")))
	assert_equal(rule_types, ["conquest", "artifacts", "ruins", "wonder"], "source Standard mode maps to all four classic victory paths")
	assert_true(definition.get("victory_rules", []).all(func(rule): return String(rule.get("type", "")) == "conquest" or float(rule.get("hold_seconds", -1.0)) == 900.0), "all timed Standard paths retain the source fifteen-minute countdown")

	if failures.is_empty():
		print("I12-020J imported Zama match contract tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_source_count(definition: Dictionary, source_unit_id: int, expected: int, context: String) -> void:
	var count: int = definition.get("entities", []).filter(func(entity): return int(entity.get("source_unit_id", -1)) == source_unit_id).size()
	assert_equal(count, expected, context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
