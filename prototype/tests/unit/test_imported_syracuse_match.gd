extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

const MATCH_PATH := "res://assets/generated/matches/syracuse.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	assert_true(bool(definition.get("valid", false)), "Syracuse match validates: %s" % [definition.get("errors", [])])
	assert_equal(String(definition.get("id", "")), "campaign_syracuse", "stable runtime id survives conversion")
	assert_equal(String(definition.get("title", "")), "Сиракузцы", "source mission title survives conversion")
	assert_equal(definition.get("map", {}).get("size"), Vector2i(144, 144), "source map size survives conversion")
	assert_equal(definition.get("players", []).size(), 4, "all four active source players are present")
	assert_equal(int(definition.get("gaps", {}).get("source_object_count", -1)), 2900, "gap ledger owns every source object")
	assert_equal(int(definition.get("gaps", {}).get("runtime_entity_count", -1)), 1968, "all simulation-owned objects enter runtime")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_object_count", -1)), 0, "Syracuse has no unsupported source objects")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_legacy_victory_condition_count", -1)), 0, "Syracuse has no unsupported legacy conditions")
	assert_equal(int(definition.get("gaps", {}).get("source_settings", {}).get("gap_count", -1)), 0, "Syracuse source settings are completely represented")

	assert_source_count(definition, 6, 22, "twenty-two Composite Bowmen")
	assert_source_count(definition, 38, 10, "ten Heavy Cavalry")
	assert_source_count(definition, 360, 6, "six Fire Galleys")
	assert_source_count(definition, 382, 1, "one Hero Archimedes")
	assert_source_count(definition, 383, 8, "eight Mirror Towers")
	assert_equal(definition.get("presentation_markers", []).filter(func(marker): return int(marker.get("source_unit_id", -1)) == 162).size(), 2, "both source flag markers remain presentation-owned")
	assert_true(definition.get("presentation_markers", []).filter(func(marker): return int(marker.get("source_unit_id", -1)) == 162).all(func(marker): return String(marker.get("asset_name", "")) == "graphic_323_p3"), "Syracuse flags use the exact animated source asset")

	var players: Array = definition.get("players", [])
	assert_equal(players.map(func(player): return int(player.get("starting_age_technology_id", -1))), [103, 103, 103, 101], "all source starting ages survive conversion")
	assert_equal(players.map(func(player): return String(player.get("starting_technology_mode", ""))), ["age_start", "post_iron", "post_iron", "age_start"], "Post-Iron semantics remain explicit for both source players")
	var syracuse_ai: Dictionary = players[2].get("source_ai", {})
	assert_true(syracuse_ai.get("unsupported_rule_lines", []).is_empty(), "recognized DEFAULT directive is not mislabeled as unknown syntax")
	assert_equal(syracuse_ai.get("runtime_support", {}).get("pending_rule_directives", []), ["DEFAULT"], "source DEFAULT baseline remains explicit and pending instead of being guessed")
	assert_true(syracuse_ai.get("build_order", []).any(func(entry): return String(entry.get("type", "")) == "building" and String(entry.get("runtime_alias", "")) == "barracks"), "source B entries normalize to data-driven building orders")
	assert_true(syracuse_ai.get("build_order", []).any(func(entry): return String(entry.get("source_opcode", "")) == "T" and not entry.get("source_parameters", []).is_empty()), "source T entries retain their extra legacy parameters without assigning guessed semantics")
	for naval_id in [58, 59, 61, 62, 67, 68, 70]:
		var entries: Array = syracuse_ai.get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == naval_id)
		assert_true(entries.size() == 1 and String(entries[0].get("runtime_semantics", "")) == "implemented", "active Syracuse naval strategic number %d is executable" % naval_id)
	assert_true(not bool(syracuse_ai.get("runtime_support", {}).get("naval_attack_enabled", true)), "zero desired boat attack groups do not activate naval attacks")
	assert_true(not bool(syracuse_ai.get("runtime_support", {}).get("naval_defence_enabled", true)), "zero desired boat defend groups do not activate Dock defence")

	var participants: Array = definition.get("scenario_definition", {}).get("participants", [])
	assert_equal(participants.size(), 3, "all three source victory participants are normalized")
	var roman_condition: Dictionary = participants[0].get("groups", [])[0].get("conditions", [])[0]
	assert_equal(String(roman_condition.get("type", "")), "create_in_area", "Roman objective retains create-in-area semantics")
	assert_equal(int(roman_condition.get("source_unit_id", -1)), 282, "Roman objective requires exact Legion source identity")
	assert_equal(int(roman_condition.get("required_count", -1)), 10, "Roman objective requires ten Legions")
	assert_equal(roman_condition.get("area", []), [74.0, 31.0, 93.0, 48.0], "Roman target area survives conversion")
	for participant in participants.slice(1):
		var condition: Dictionary = participant.get("groups", [])[0].get("conditions", [])[0]
		assert_equal(String(condition.get("type", "")), "destroy_object", "enemy objective is an exact destroy-object condition")
		assert_equal(int(condition.get("target_scenario_object_id", -1)), 5998, "both enemy participants target exact scenario object 5998")
		assert_equal(int(condition.get("target_source_unit_id", -1)), 382, "both enemy participants target Hero Archimedes")
		assert_equal(int(condition.get("target_team", -1)), 3, "Archimedes retains source ownership")

	var archimedes: Array = definition.get("entities", []).filter(func(entity): return int(entity.get("scenario_object_id", -1)) == 5998)
	assert_equal(archimedes.size(), 1, "exact Archimedes target exists once")
	assert_true(archimedes.size() == 1 and String(archimedes[0].get("kind", "")) == "archimedes", "exact target resolves to the dedicated Archimedes archetype")

	if failures.is_empty():
		print("I12-020I imported Syracuse match contract tests passed")
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
