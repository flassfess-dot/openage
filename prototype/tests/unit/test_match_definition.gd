extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json()
	assert_true(bool(definition.get("valid", false)), "shipped prototype match validates: %s" % [definition.get("errors", [])])
	assert_equal(definition["map"]["size"], Vector2i(24, 24), "map size is normalized to Vector2i")
	assert_equal(definition.get("local_team"), 1, "single human player becomes local observer")
	assert_equal(definition.get("players", []).size(), 2, "match declares both players")
	assert_equal(definition.get("entities", []).size(), 12, "static start entities are data driven")

	var invalid := MatchDefinition.normalize({
		"map": {"size": [4, 4]},
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13, "start": [2, 2]},
			{"team": 1, "controller": "oracle", "civilization_id": -1, "start": [99, 99]},
		],
	})
	assert_true(not bool(invalid.get("valid", true)), "invalid external match is rejected")
	assert_true(invalid.get("errors", []).has("map_size_out_of_range"), "invalid size reports stable reason")
	assert_true(invalid.get("errors", []).has("player_team_duplicate:1"), "duplicate team reports stable reason")

	var missing_source_ai := MatchDefinition.normalize({
		"map": {"size": [24, 24]},
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13, "start": [2, 2]},
			{"team": 2, "controller": "ai", "civilization_id": 1, "start": [20, 20], "ai": {"enabled": true, "profile": "source_campaign_v1"}},
		],
	})
	assert_true(missing_source_ai.get("errors", []).has("source_ai_contract_required:2"), "source campaign profile cannot run without an imported contract")

	var invalid_technology_contract := MatchDefinition.normalize({
		"map": {"size": [24, 24]},
		"players": [
			{
				"team": 1,
				"controller": "human",
				"civilization_id": 13,
				"start": [2, 2],
				"starting_age_technology_id": 102,
				"starting_technology_mode": "post_iron",
				"disabled_technology_nodes": [
					{"slot": 20, "node": "", "kind": "age", "technology_id": 999},
					{"slot": 0, "node": "granary", "kind": "building", "source_object_id": -1},
				],
			},
			{"team": 2, "controller": "ai", "civilization_id": 1, "start": [20, 20]},
		],
	})
	assert_true(invalid_technology_contract.get("errors", []).has("player_post_iron_requires_iron_age:1"), "Post-Iron mode requires the Iron Age source node")
	assert_true(invalid_technology_contract.get("errors", []).has("player_disabled_technology_node_slot_invalid:1"), "classic disabled nodes use the fixed 16-slot contract")
	assert_true(invalid_technology_contract.get("errors", []).has("player_disabled_technology_node_name_missing:1"), "disabled technology nodes require an identity")
	assert_true(invalid_technology_contract.get("errors", []).has("player_disabled_technology_age_invalid:1"), "disabled age nodes accept only classic age technologies")
	assert_true(invalid_technology_contract.get("errors", []).has("player_disabled_technology_building_invalid:1"), "disabled building nodes require a source object")

	if failures.is_empty():
		print("I11-001 match definition tests passed")
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
