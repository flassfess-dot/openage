extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_conquest(catalog)
	test_allied_conquest(catalog)
	test_artifacts_and_ruins(catalog)
	test_wonder_and_score(catalog)
	test_scenario_conditions(catalog)
	if failures.is_empty():
		print("S-012 victory mode tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_conquest(catalog) -> void:
	var world = original_world(catalog)
	world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(8.0, 8.0), false)
	enemy["hp"] = 0.0
	world.check_battle_state(1, 2)
	assert_equal(world.get_victory_result()["reason"], "conquest", "default conquest condition")
	assert_equal(world.get_victory_result()["winner_team"], 1, "conquest winner")
	assert_equal(world.get_victory_result()["winner_teams"], [1], "solo conquest preserves an explicit winning side")


func test_allied_conquest(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.configure_players([
		{"team": 1, "controller": "human"},
		{"team": 2, "controller": "ai"},
		{"team": 3, "controller": "ai"},
		{"team": 4, "controller": "ai"},
	])
	world.set_alliance(1, 2, true)
	world.set_alliance(3, 4, true)
	world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	world.add_unit(2, "clubman", Vector2(5.0, 4.0), false)
	world.check_battle_state(2, 3)
	var result: Dictionary = world.get_victory_result()
	assert_equal(result.get("winner_team"), 1, "allied conquest keeps the lowest stable team as compatibility winner")
	assert_equal(result.get("winner_teams"), [1, 2], "all mutually allied survivors share conquest victory")
	assert_equal(result.get("loser_teams"), [3, 4], "eliminated opposing alliance is the losing side")
	assert_equal(world.player_registry.status(1), "victorious", "first ally is finalized as victorious")
	assert_equal(world.player_registry.status(2), "victorious", "second ally is finalized as victorious")
	assert_true(world.get_last_battle_message().begins_with("ПОБЕДА"), "local member of the winning alliance receives victory presentation")


func test_artifacts_and_ruins(catalog) -> void:
	var world = original_world(catalog)
	world.configure_victory_rules([{"type": "artifacts", "required_count": 2, "hold_seconds": 1.0}])
	world.add_victory_object("artifact", Vector2(3.0, 3.0), 1)
	world.add_victory_object("artifact", Vector2(4.0, 3.0), 1)
	world.check_battle_state(1, 2, 0.5)
	assert_true(not world.is_battle_over(), "artifact timer must finish")
	world.check_battle_state(1, 2, 0.5)
	assert_equal(world.get_victory_result()["reason"], "artifacts", "artifact hold victory")

	world.configure_victory_rules([{"type": "ruins", "required_count": 1, "hold_seconds": 0.0}])
	world.add_victory_object("ruin", Vector2(5.0, 3.0), 2)
	world.check_battle_state(1, 2)
	assert_equal(world.get_victory_result()["winner_team"], 2, "ruin ownership victory")


func test_wonder_and_score(catalog) -> void:
	var world = original_world(catalog)
	world.configure_victory_rules([{"type": "wonder", "hold_seconds": 2.0}])
	var wonder: Dictionary = world.add_victory_object("wonder", Vector2(10.0, 10.0), 1, false)
	world.check_battle_state(1, 2, 2.0)
	assert_true(not world.is_battle_over(), "unfinished wonder does not count")
	world.set_victory_object_completed(int(wonder["id"]), true)
	world.check_battle_state(1, 2, 1.0)
	assert_true(not world.is_battle_over(), "wonder timer is continuous after completion")
	world.check_battle_state(1, 2, 1.0)
	assert_equal(world.get_victory_result()["reason"], "wonder", "wonder hold victory")

	world.configure_victory_rules([{"type": "score", "score_limit": 500}])
	world.set_score(1, 499)
	world.check_battle_state(1, 2)
	assert_true(not world.is_battle_over(), "score below limit")
	world.add_score(1, 1)
	world.check_battle_state(1, 2)
	assert_equal(world.get_victory_result()["reason"], "score", "score limit victory")


func test_scenario_conditions(catalog) -> void:
	var world = original_world(catalog)
	world.grant_technology(1, 11)
	world.set_resource_amount(1, 0, 300)
	world.configure_victory_rules([{
		"type": "scenario",
		"winner_team": 1,
		"conditions": [
			{"type": "technology", "technology_id": 11},
			{"type": "resource", "resource_id": 0, "amount": 300},
			{"type": "elapsed", "seconds": 1.0},
		],
	}])
	world.check_battle_state(1, 2, 0.5)
	assert_true(not world.is_battle_over(), "all scenario predicates are required")
	world.check_battle_state(1, 2, 0.5)
	assert_equal(world.get_victory_result()["reason"], "scenario", "scenario condition victory")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
