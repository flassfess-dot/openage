extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const MATCH_PATH := "res://assets/generated/matches/pyrrhus-of-epirus.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var catalog := ResourceCatalog.new()
	catalog.load()
	var map_data := MapGenerator.generate(definition)
	var world = configured_world(catalog, map_data)
	MatchBootstrap.apply(world, definition, map_data)
	verify_bootstrap(world)
	verify_conquest_victory(world)
	MatchBootstrap.apply(world, definition, map_data)
	verify_source_defeat(world)
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
	assert_equal(world.get_units().size(), 107, "Pyrrhus creates every source-owned runtime unit")
	assert_equal(world.get_buildings().size(), 325, "Pyrrhus creates every source-owned runtime building")
	assert_equal(world.get_resources().size(), 2918, "Pyrrhus creates every source-owned resource")
	assert_equal(world.victory_objectives.size(), 1, "source Ruins enters the objective system")
	assert_equal(world.get_static_obstructions().size(), 38, "all source cliffs reach navigation")
	assert_equal(world.get_current_age(1), 101, "Rome starts in the source Tool Age")
	assert_equal(world.get_current_age(2), 103, "Macedonians retain Iron as the Post-Iron authoritative age")
	assert_true(world.get_researched_technologies(2).has(37), "Post-Iron completes an allowed Macedonian Iron technology")
	assert_true(not world.is_object_available(2, 276), "source Wonder node restriction survives Post-Iron initialization")
	assert_true(world.is_object_available(2, 39), "Post-Iron exposes Horse Archer from the source AI roster")
	assert_true(world.is_object_available(2, 46), "Post-Iron exposes War Elephant from the source AI roster")

	var targets := roman_town_centers(world)
	assert_equal(targets.size(), 2, "both exact Roman Town Centers enter runtime")
	assert_equal(targets.map(func(building): return int(building.get("scenario_object_id", -1))), [4346, 4347], "target scenario identities survive bootstrap")
	assert_true(targets.all(func(building): return int(building.get("scenario_source_unit_id", -1)) == 109), "immutable source Town Center identity survives age upgrades")


func verify_conquest_victory(world) -> void:
	var controller := GameController.new(world)
	var resign_enemy = Commands.ResignCommand.new(1)
	controller.enqueue_command(resign_enemy, true, 2)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(resign_enemy.sequence_id).get("accepted", false)), "Macedonian resignation crosses the public command boundary")
	assert_true(world.is_battle_over(), "Macedonian resignation completes conquest")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 1, "conquest awards victory to Rome")
	assert_equal(String(world.get_victory_result().get("reason", "")), "conquest", "conquest path retains its reason")


func verify_source_defeat(world) -> void:
	var targets := roman_town_centers(world)
	assert_equal(targets.size(), 2, "source loss targets are available after clean bootstrap")
	if targets.size() != 2:
		return
	world.begin_building_destruction(targets[0])
	world.check_battle_state(1, 2, 0.05)
	assert_true(not world.is_battle_over(), "losing only one protected Town Center does not end the mission")
	world.begin_building_destruction(targets[1])
	world.check_battle_state(1, 2, 0.05)
	assert_true(world.is_battle_over(), "losing both exact protected Town Centers ends the mission")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 2, "source destroy-object condition awards victory to Macedonians")
	assert_equal(String(world.get_victory_result().get("reason", "")), "scenario", "source loss retains the scenario reason")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, 2, 1, {"include_navigation": false, "include_build_sites": false})
	assert_true(bool(presentation.get("match_result", {}).get("over", false)), "source defeat reaches local read-only presentation")
	assert_equal(int(presentation.get("match_result", {}).get("winner_team", -1)), 2, "Roman observer receives the source losing result")


func roman_town_centers(world) -> Array:
	var result: Array = world.get_buildings().filter(func(building): return int(building.get("scenario_object_id", -1)) in [4346, 4347])
	result.sort_custom(func(left, right): return int(left.get("scenario_object_id", -1)) < int(right.get("scenario_object_id", -1)))
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish_test() -> void:
	if failures.is_empty():
		print("I12-020H Pyrrhus bootstrap and outcome vertical tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
