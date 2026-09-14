extends SceneTree

const ScenarioDefinition := preload("res://scripts/scenario_definition.gd")
const ScenarioSystem := preload("res://scripts/scenario_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_valid_contract()
	test_invalid_contract()
	test_destroy_object_lifecycle()
	test_destroy_count_lifecycle()
	test_bring_object_to_area_lifecycle()
	test_inactive_participant_cannot_complete()
	test_create_unit_in_area_lifecycle()
	if failures.is_empty():
		print("I12-020C ScenarioDefinition contract tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_valid_contract() -> void:
	var result := ScenarioDefinition.normalize({
		"schema_version": 1,
		"participants": [{
			"team": 1,
			"completion_mode": "any",
			"groups": [{
				"id": "roman_towers",
				"mode": "all",
				"conditions": [
					{"id": "tower_1", "type": "create_in_area", "team": 1, "source_unit_id": 199, "kind": "tower", "required_count": 1, "area": [1, 2, 5, 7]},
					{"id": "defeat_2", "type": "destroy_player", "target_team": 2},
					{"id": "destroy_tc", "type": "destroy_object", "target_scenario_object_id": 42, "target_source_unit_id": 109, "target_team": 2},
				],
			}],
		}],
	}, {1: true, 2: true}, Vector2i(20, 20))
	assert_equal(result.get("errors", []), [], "valid scenario contract has no errors")
	assert_equal(result.get("value", {}).get("participants", [])[0].get("groups", [])[0].get("conditions", [])[0].get("area"), [1.0, 2.0, 5.0, 7.0], "areas normalize to deterministic floats")


func test_invalid_contract() -> void:
	var result := ScenarioDefinition.normalize({
		"schema_version": 2,
		"participants": [{
			"team": 3,
			"completion_mode": "sometimes",
			"groups": [{
				"id": "duplicate",
				"mode": "all",
				"conditions": [
					{"id": "duplicate", "type": "create_in_area", "team": 1, "source_unit_id": -1, "kind": "", "required_count": 0, "area": [8, 8, 4, 30]},
					{"id": "unknown", "type": "unsupported"},
				],
			}],
		}],
	}, {1: true, 2: true}, Vector2i(20, 20))
	var errors: Array = result.get("errors", [])
	assert_true(errors.has("scenario_schema_version_unsupported"), "schema version is validated")
	assert_true(errors.has("scenario_participant_team_unknown:3"), "participant team is validated")
	assert_true(errors.has("scenario_participant_mode_invalid:3"), "participant mode is validated")
	assert_true(errors.has("scenario_condition_id_duplicate:duplicate"), "condition and group ids share one unique namespace")
	assert_true(errors.has("scenario_condition_object_unknown:duplicate"), "source object identity is required")
	assert_true(errors.has("scenario_condition_count_invalid:duplicate"), "positive count is required")
	assert_true(errors.has("scenario_condition_area_inverted:duplicate"), "inverted areas are rejected")
	assert_true(errors.has("scenario_condition_area_out_of_bounds:duplicate"), "areas are bounded by the map")
	assert_true(errors.has("scenario_condition_type_unsupported:unknown"), "unknown condition types are explicit errors")


func test_destroy_object_lifecycle() -> void:
	var system := ScenarioSystem.new()
	system.configure({
		"schema_version": 1,
		"participants": [{
			"team": 1,
			"completion_mode": "any",
			"groups": [{
				"id": "destroy_targets",
				"mode": "all",
				"conditions": [{"id": "destroy_42", "type": "destroy_object", "target_scenario_object_id": 42, "target_source_unit_id": 109, "target_team": 2}],
			}],
		}],
	})
	var target := {"scenario_object_id": 42, "team": 2, "hp": 100.0}
	var active := system.update({"units": [], "buildings": [target], "resources": [], "objectives": [], "player_states": {}})
	assert_true(not bool(active.get("result", {}).get("over", false)), "living source target keeps destroy-object scenario active")
	target["hp"] = 0.0
	var completed := system.update({"units": [], "buildings": [target], "resources": [], "objectives": [], "player_states": {}})
	assert_true(bool(completed.get("result", {}).get("over", false)), "destroyed source target completes scenario condition")
	assert_equal(int(completed.get("result", {}).get("winner_team", -1)), 1, "destroy-object condition awards the declared participant")


func test_create_unit_in_area_lifecycle() -> void:
	var system := ScenarioSystem.new()
	system.configure({
		"schema_version": 1,
		"participants": [{
			"team": 1,
			"completion_mode": "any",
			"groups": [{
				"id": "legion_goal",
				"mode": "all",
				"conditions": [{"id": "legion_area", "type": "create_in_area", "team": 1, "source_unit_id": 282, "kind": "swordsman", "required_count": 2, "area": [4.0, 4.0, 8.0, 8.0]}],
			}],
		}],
	})
	var first := {"source_unit_id": 282, "kind": "swordsman", "team": 1, "hp": 100.0, "pos": Vector2(5.0, 5.0)}
	var second := {"source_unit_id": 282, "kind": "swordsman", "team": 1, "hp": 100.0, "pos": Vector2(7.0, 7.0)}
	var active := system.update({"units": [first], "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {}})
	assert_true(not bool(active.get("result", {}).get("over", false)), "one qualifying unit keeps a two-unit area goal active")
	var completed := system.update({"units": [first, second], "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {}})
	assert_true(bool(completed.get("result", {}).get("over", false)), "qualifying units complete create-in-area conditions")
	assert_equal(int(completed.get("result", {}).get("winner_team", -1)), 1, "unit area condition awards the declared participant")


func test_destroy_count_lifecycle() -> void:
	var system := ScenarioSystem.new()
	system.configure({
		"schema_version": 1,
		"participants": [{"team": 1, "completion_mode": "any", "groups": [{
			"id": "destroy_slingers",
			"mode": "all",
			"conditions": [{"id": "destroy_three", "type": "destroy_count", "target_team": 2, "target_source_unit_id": 347, "target_scenario_object_ids": [10, 11, 12], "required_count": 3}],
		}]}],
	})
	var targets := [
		{"scenario_object_id": 10, "team": 2, "hp": 35.0},
		{"scenario_object_id": 11, "team": 2, "hp": 0.0},
		{"scenario_object_id": 12, "team": 2, "hp": 35.0},
	]
	var active := system.update({"units": targets, "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {}})
	assert_true(not bool(active.get("result", {}).get("over", false)), "a living source target keeps DestroyMultiple active")
	assert_equal(int(system.canonical_state().get("condition_states", {}).get("destroy_three", {}).get("current", -1)), 1, "destroy-count reports source-owned progress")
	targets[0]["hp"] = 0.0
	targets[2]["hp"] = 0.0
	var completed := system.update({"units": targets, "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {}})
	assert_true(bool(completed.get("result", {}).get("over", false)), "destroying the declared source object set completes DestroyMultiple")


func test_bring_object_to_area_lifecycle() -> void:
	var system := ScenarioSystem.new()
	system.configure({
		"schema_version": 1,
		"participants": [{"team": 1, "completion_mode": "any", "groups": [{
			"id": "bring_artifact",
			"mode": "all",
			"conditions": [{"id": "artifact_area", "type": "bring_object_to_area", "target_scenario_object_id": 6477, "target_source_unit_id": 159, "area": [39.0, 29.0, 53.0, 45.0]}],
		}]}],
	})
	var artifact := {"scenario_object_id": 6477, "team": 1, "hp": 1.0, "pos": Vector2(116.0, 85.0)}
	var active := system.update({"units": [artifact], "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {}})
	assert_true(not bool(active.get("result", {}).get("over", false)), "artifact outside its source area keeps BringToArea active")
	artifact["pos"] = Vector2(45.0, 35.0)
	var completed := system.update({"units": [artifact], "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {}})
	assert_true(bool(completed.get("result", {}).get("over", false)), "the exact source artifact inside its area completes BringToArea")


func test_inactive_participant_cannot_complete() -> void:
	var system := ScenarioSystem.new()
	system.configure({
		"schema_version": 1,
		"participants": [{"team": 1, "completion_mode": "any", "groups": [{
			"id": "already_satisfied",
			"mode": "all",
			"conditions": [{"id": "empty_target_set", "type": "destroy_count", "target_team": 2, "target_source_unit_id": 347, "target_scenario_object_ids": [10], "required_count": 1}],
		}]}],
	})
	var update := system.update({"units": [], "buildings": [], "resource_nodes": [], "objectives": [], "player_states": {1: {"status": "resigned"}}})
	assert_true(not bool(update.get("result", {}).get("over", false)), "a resigned participant cannot win through an already-satisfied scenario condition")
	assert_true(not update.get("events", []).any(func(event): return String(event.get("type", "")) == "scenario_completed"), "inactive participant emits no scenario completion event")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
