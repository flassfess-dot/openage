extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

const MATCH_PATH := "res://assets/generated/matches/pyrrhus-of-epirus.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	assert_true(bool(definition.get("valid", false)), "Pyrrhus match validates: %s" % [definition.get("errors", [])])
	assert_equal(String(definition.get("id", "")), "campaign_pyrrhus_of_epirus", "stable runtime id survives conversion")
	assert_equal(String(definition.get("title", "")), "Пирр Эпирский", "source mission title survives conversion")
	assert_equal(definition.get("map", {}).get("size"), Vector2i(144, 144), "source map size survives conversion")
	assert_equal(definition.get("players", []).size(), 2, "both active source players are present")
	assert_equal(int(definition.get("gaps", {}).get("source_object_count", -1)), 3809, "gap ledger owns every source object")
	assert_equal(int(definition.get("gaps", {}).get("runtime_entity_count", -1)), 3351, "all simulation-owned objects enter runtime")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_object_count", -1)), 0, "Pyrrhus has no unsupported source objects")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_legacy_victory_condition_count", -1)), 0, "Pyrrhus has no unsupported legacy conditions")
	assert_equal(int(definition.get("gaps", {}).get("source_settings", {}).get("gap_count", -1)), 0, "Pyrrhus source settings are completely represented")

	assert_source_count(definition, 25, 6, "six Elephant Archers")
	assert_source_count(definition, 283, 4, "four Cataphracts")
	assert_source_count(definition, 345, 6, "six Armored Elephants")
	assert_source_count(definition, 158, 1, "one Ruins objective")
	assert_true(definition.get("static_obstructions", []).any(func(item): return int(item.get("graphic_id", -1)) == 115 and String(item.get("asset_name", "")) == "graphic_115"), "source cliff graphic 115 is available as an exact asset")

	var enemy: Dictionary = definition.get("players", [])[1]
	assert_equal(int(enemy.get("starting_age_technology_id", -1)), 103, "Post-Iron uses Iron as the authoritative age")
	assert_equal(String(enemy.get("starting_technology_mode", "")), "post_iron", "source Post-Iron semantic is explicit")
	assert_equal(enemy.get("disabled_technology_nodes", []).size(), 1, "one classic technology-tree node is disabled")
	var disabled_node: Dictionary = enemy.get("disabled_technology_nodes", [])[0]
	assert_equal(int(disabled_node.get("slot", -1)), 15, "classic slot 15 identity is retained")
	assert_equal(String(disabled_node.get("node", "")), "wonder", "classic slot 15 maps to Wonder")
	assert_equal(int(disabled_node.get("source_object_id", -1)), 276, "Wonder source object identity is retained")
	var enemy_source_ai: Dictionary = enemy.get("source_ai", {})
	assert_true(bool(enemy_source_ai.get("runtime_support", {}).get("naval_attack_enabled", false)), "Pyrrhus source profile enables its two boat attack groups")
	for naval_id in [58, 59, 60, 61, 62, 63]:
		var entries: Array = enemy_source_ai.get("strategic_numbers", []).filter(func(entry): return int(entry.get("source_id", -1)) == naval_id)
		assert_true(entries.size() == 1 and String(entries[0].get("runtime_semantics", "")) == "implemented", "Pyrrhus naval strategic number %d is executable" % naval_id)

	var participant: Dictionary = definition.get("scenario_definition", {}).get("participants", [])[0]
	assert_equal(int(participant.get("team", -1)), 2, "Macedonian source participant owns the loss condition")
	var conditions: Array = participant.get("groups", [])[0].get("conditions", [])
	assert_equal(conditions.size(), 2, "both Roman Town Centers are required loss targets")
	assert_equal(conditions.map(func(condition): return int(condition.get("target_scenario_object_id", -1))), [4346, 4347], "exact scenario object IDs drive the loss condition")
	assert_true(conditions.all(func(condition): return String(condition.get("type", "")) == "destroy_object" and int(condition.get("target_source_unit_id", -1)) == 109 and int(condition.get("target_team", -1)) == 1), "both loss targets are typed Roman Town Centers")

	if failures.is_empty():
		print("I12-020H imported Pyrrhus match contract tests passed")
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
