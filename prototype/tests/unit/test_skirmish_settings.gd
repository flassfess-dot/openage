extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var source_catalog := SkirmishSettings.catalog()
	assert_true(bool(source_catalog.get("valid", false)), "the versioned skirmish catalog loads")
	assert_equal(source_catalog.get("civilizations", []).size(), 16, "all Rise of Rome civilizations are selectable")

	var defaults := SkirmishSettings.default_settings()
	var first := SkirmishSettings.build(defaults)
	var second := SkirmishSettings.build(defaults)
	assert_true(bool(first.get("valid", false)), "default skirmish builds: %s" % [first.get("errors", [])])
	if not bool(first.get("valid", false)):
		_finish("E5-002 skirmish settings tests passed")
		return
	assert_equal(first.get("identity"), second.get("identity"), "the same settings produce stable save identity")
	var definition: Dictionary = first.get("definition", {})
	assert_true(bool(definition.get("valid", false)), "generated match passes the ordinary match validator")
	assert_equal(definition.get("players", []).size(), 2, "default match has two active players")
	assert_equal(definition.get("entities", []).size(), 8, "each player starts with a town center and three villagers")
	var first_start := Vector2(definition.get("players", [])[0].get("start", Vector2.ZERO))
	var first_villagers: Array = definition.get("entities", []).filter(func(entity): return String(entity.get("category", "")) == "unit" and int(entity.get("team", 0)) == 1)
	assert_true(first_villagers.all(func(entity): return Vector2(entity.get("position", Vector2.ZERO)).distance_to(first_start) >= 3.0), "starting villagers spawn outside the Town Center navigation footprint")
	for entity_value in definition.get("entities", []):
		var entity: Dictionary = entity_value
		var exclusion_radius := int(entity.get("resource_exclusion_radius_cells", 0))
		if exclusion_radius <= 0:
			continue
		var entity_cell := Vector2i(Vector2(entity.get("position", Vector2.ZERO)))
		for resource_value in first.get("map_data", {}).get("resources", []):
			var resource_cell := Vector2i(Vector2(resource_value.get("position", Vector2.ZERO)))
			assert_true(maxi(absi(resource_cell.x - entity_cell.x), absi(resource_cell.y - entity_cell.y)) > exclusion_radius, "generated resources preserve the declared starting-entity clearance")
	assert_equal(int(definition.get("players", [])[0].get("starting_age_technology_id", -1)), 100, "Stone Age is represented by the authoritative age technology")
	assert_equal(int(definition.get("players", [])[0].get("population_limit", -1)), 50, "population limit reaches the match definition")
	var human_ai: Dictionary = definition.get("players", [])[0].get("ai", {})
	var opponent_ai: Dictionary = definition.get("players", [])[1].get("ai", {})
	assert_true(not bool(human_ai.get("enabled", true)), "the local human retains the shared policy data without activating AI")
	assert_true(bool(opponent_ai.get("enabled", false)), "the AI player is enabled through the generated definition")
	assert_equal(String(opponent_ai.get("profile", "")), "skirmish_policy_v1", "generated skirmish selects the versioned AI policy")
	assert_equal(String(opponent_ai.get("difficulty_id", "")), "standard", "default AI difficulty reaches every generated player")
	assert_equal(int(opponent_ai.get("initial_attack_delay_ticks", 0)), 40, "generated player receives the policy attack delay")
	assert_equal(int(opponent_ai.get("minimum_attack_group_size", 0)), 3, "generated player receives the policy group threshold")
	assert_true(String(first.get("identity", "")).begins_with("generated://skirmish/"), "generated matches have a stable non-file identity")
	assert_true(bool(first.get("map_quality", {}).get("valid", false)), "default map passes generation guarantees before launch")

	var team_settings := defaults.duplicate(true)
	team_settings["players"][1]["alliance_id"] = 1
	var allied := SkirmishSettings.build(team_settings)
	assert_equal(allied.get("definition", {}).get("alliances", []), [[1, 2]], "shared alliance IDs become mutual runtime alliances")

	var large_settings := defaults.duplicate(true)
	large_settings["map_size_id"] = "giant"
	large_settings["map_type_id"] = "coastal"
	large_settings["resource_preset_id"] = "high"
	large_settings["starting_age_id"] = "bronze"
	large_settings["ai_difficulty_id"] = "hard"
	large_settings["population_limit"] = 500
	large_settings["victory_mode_id"] = "score_60"
	for index in range(8):
		large_settings["players"][index]["enabled"] = true
		large_settings["players"][index]["controller"] = "human" if index == 0 else "ai"
	var large := SkirmishSettings.build(large_settings)
	assert_true(bool(large.get("valid", false)), "eight-player extended match builds: %s" % [large.get("errors", [])])
	var large_definition: Dictionary = large.get("definition", {})
	assert_equal(large_definition.get("map", {}).get("size"), Vector2i(200, 200), "selected map dimensions reach the generated definition")
	assert_equal(large_definition.get("players", []).size(), 8, "all eight player slots survive generation")
	assert_equal(int(large_definition.get("players", [])[7].get("color_index", -1)), 8, "player colour is independent explicit data")
	assert_equal(int(large_definition.get("players", [])[0].get("starting_resources", {}).get("gold", -1)), 500, "resource preset reaches every player")
	assert_equal(int(large_definition.get("players", [])[0].get("starting_age_technology_id", -1)), 102, "starting age reaches every player")
	assert_equal(int(large_definition.get("players", [])[7].get("ai", {}).get("military_interval_ticks", 0)), 10, "selected hard AI cadence reaches generated opponents")
	assert_equal(String(large_definition.get("victory_rules", [])[0].get("type", "")), "score", "victory selection reaches the runtime rule")

	var invalid := defaults.duplicate(true)
	invalid["players"][1]["color_index"] = 1
	invalid["players"][0]["controller"] = "ai"
	var rejected := SkirmishSettings.build(invalid)
	assert_true(not bool(rejected.get("valid", true)), "ambiguous settings are rejected before launch")
	assert_true(rejected.get("errors", []).has("skirmish_player_color_invalid:1"), "duplicate player colour has a stable error")
	assert_true(rejected.get("errors", []).has("skirmish_local_human_count_invalid"), "a local match requires exactly one human")

	var overcrowded := defaults.duplicate(true)
	overcrowded["map_size_id"] = "compact"
	for index in range(8):
		overcrowded["players"][index]["enabled"] = true
		overcrowded["players"][index]["controller"] = "human" if index == 0 else "ai"
	var overcrowded_result := SkirmishSettings.build(overcrowded)
	assert_true(overcrowded_result.get("errors", []).has("skirmish_map_player_capacity_exceeded"), "map capacity rejects crowded starts before generation")

	_finish("E5-002 skirmish settings tests passed")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
