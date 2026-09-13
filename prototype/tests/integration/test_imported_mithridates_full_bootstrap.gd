extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const MATCH_PATH := "res://assets/generated/matches/mithridates.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var catalog := ResourceCatalog.new()
	catalog.load()
	var map_data := MapGenerator.generate(definition)
	var world = configured_world(catalog, map_data)
	MatchBootstrap.apply(world, definition, map_data)
	verify_bootstrap(world)
	verify_source_victory(world)
	MatchBootstrap.apply(world, definition, map_data)
	verify_local_defeat(world)
	finish_test()


func configured_world(catalog, map_data: Dictionary):
	var world := SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func verify_bootstrap(world) -> void:
	assert_equal(world.get_units().size(), 126, "Mithridates creates every source-owned runtime unit")
	assert_equal(world.get_buildings().size(), 542, "Mithridates creates every source-owned runtime building")
	assert_equal(world.get_resources().size(), 7819, "Mithridates creates every source-owned resource")
	assert_equal(world.get_static_obstructions().size(), 132, "all source cliffs reach navigation")
	var expected_ages := {1: 103, 2: 102, 3: 103, 4: 103, 5: 103}
	for team in expected_ages:
		assert_equal(world.get_current_age(team), expected_ages[team], "team %d starts in its source age" % team)
	assert_true(not world.is_object_available(2, 109), "source Town Center node restriction survives bootstrap")
	assert_true(world.get_researched_technologies(3).has(37), "Post-Iron completes an allowed Iron technology")
	assert_source_count(world.get_units(), 20, 9, "nine War Galleys retain exact source identity")
	assert_source_count(world.get_units(), 21, 6, "six Triremes retain exact source identity")
	assert_source_count(world.get_units(), 250, 7, "seven Catapult Triremes retain exact source identity")
	assert_source_count(world.get_units(), 283, 1, "one Cataphract retains exact source identity")
	var targets := wonder_targets(world)
	assert_equal(targets.size(), 1, "exact enemy Wonder target enters runtime once")
	assert_true(targets.size() == 1 and int(targets[0].get("scenario_source_unit_id", -1)) == 276, "immutable Wonder source identity survives bootstrap")


func verify_source_victory(world) -> void:
	var targets := wonder_targets(world)
	assert_equal(targets.size(), 1, "source Wonder target is available after bootstrap")
	if targets.size() != 1:
		return
	world.begin_building_destruction(targets[0])
	world.check_battle_state(1, 2, 0.05)
	assert_true(world.is_battle_over(), "destroying exact enemy Wonder completes the source objective")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 1, "source objective awards victory to Rome")
	assert_equal(String(world.get_victory_result().get("reason", "")), "scenario", "source objective retains the scenario reason")


func verify_local_defeat(world) -> void:
	var controller := GameController.new(world)
	var resignations: Array = []
	for team in [1, 3, 4, 5]:
		var command = Commands.ResignCommand.new(1)
		resignations.append({"team": team, "command": command})
		controller.enqueue_command(command, true, team)
	controller.advance_frame(0.05, 1, 2)
	for resignation_value in resignations:
		var resignation: Dictionary = resignation_value
		assert_true(bool(controller.get_command_result(resignation["command"].sequence_id).get("accepted", false)), "team %d resignation crosses the public command boundary" % int(resignation["team"]))
	assert_true(world.is_battle_over(), "resignations leave one active enemy team")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 2, "remaining enemy alliance wins deterministically")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, controller.tick_index, 1, {"include_navigation": false, "include_build_sites": false})
	assert_true(bool(presentation.get("match_result", {}).get("over", false)), "defeat reaches local read-only presentation")
	assert_true(int(presentation.get("match_result", {}).get("winner_team", 1)) != 1, "Roman observer receives a losing result")


func wonder_targets(world) -> Array:
	return world.get_buildings().filter(func(building): return int(building.get("scenario_object_id", -1)) == 10755)


func assert_source_count(entities: Array, source_unit_id: int, expected: int, context: String) -> void:
	var count: int = entities.filter(func(entity): return int(entity.get("source_unit_id", -1)) == source_unit_id).size()
	assert_equal(count, expected, context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish_test() -> void:
	if failures.is_empty():
		print("I12-020K Mithridates bootstrap and outcome vertical tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
