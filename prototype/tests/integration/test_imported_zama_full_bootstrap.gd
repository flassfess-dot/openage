extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const MATCH_PATH := "res://assets/generated/matches/zama.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var catalog := ResourceCatalog.new()
	catalog.load()
	var map_data := MapGenerator.generate(definition)
	var world = configured_world(catalog, map_data)
	MatchBootstrap.apply(world, definition, map_data)
	verify_bootstrap(world)
	verify_wonder_victory(world)
	MatchBootstrap.apply(world, definition, map_data)
	verify_conquest_victory(world)
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
	assert_equal(world.get_units().size(), 109, "Zama creates every source-owned runtime unit")
	assert_equal(world.get_buildings().size(), 255, "Zama creates every source-owned runtime building")
	assert_equal(world.get_resources().size(), 6170, "Zama creates every source-owned resource")
	assert_equal(world.get_static_obstructions().size(), 96, "all source cliffs reach navigation")
	assert_equal(world.get_current_age(1), 103, "Rome starts in source Iron Age")
	assert_equal(world.get_current_age(2), 103, "Carthage retains Iron as the Post-Iron authoritative age")
	assert_true(world.get_researched_technologies(2).has(37), "Post-Iron completes an allowed Carthaginian Iron technology")
	assert_source_count(world.get_units(), 6, 7, "all Composite Bowmen retain exact source identity")
	assert_source_count(world.get_units(), 38, 8, "all Heavy Cavalry retain exact source identity")
	assert_source_count(world.get_units(), 39, 11, "all Horse Archers retain exact source identity")
	assert_source_count(world.get_units(), 345, 6, "all Armored Elephants retain exact source identity")


func verify_wonder_victory(world) -> void:
	world.create_building(1, "wonder", Vector2(100.0, 100.0), true)
	world.check_battle_state(1, 2, 899.95)
	assert_true(not world.is_battle_over(), "completed Wonder does not win before the source countdown")
	world.check_battle_state(1, 2, 0.05)
	assert_true(world.is_battle_over(), "completed Wonder wins after the full source countdown")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 1, "Wonder path awards victory to Rome")
	assert_equal(String(world.get_victory_result().get("reason", "")), "wonder", "Wonder path retains its victory reason")


func verify_conquest_victory(world) -> void:
	var controller := GameController.new(world)
	var resign_enemy = Commands.ResignCommand.new(1)
	controller.enqueue_command(resign_enemy, true, 2)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(resign_enemy.sequence_id).get("accepted", false)), "Carthaginian resignation crosses the public command boundary")
	assert_true(world.is_battle_over(), "Carthaginian resignation completes conquest")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 1, "conquest awards victory to Rome")
	assert_equal(String(world.get_victory_result().get("reason", "")), "conquest", "conquest path retains its reason")


func verify_local_defeat(world) -> void:
	var controller := GameController.new(world)
	var resign_rome = Commands.ResignCommand.new(1)
	controller.enqueue_command(resign_rome, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(resign_rome.sequence_id).get("accepted", false)), "Roman resignation crosses the public command boundary")
	assert_true(world.is_battle_over(), "Roman resignation ends the match")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 2, "remaining Carthaginian side wins deterministically")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, controller.tick_index, 1, {"include_navigation": false, "include_build_sites": false})
	assert_true(bool(presentation.get("match_result", {}).get("over", false)), "defeat reaches local read-only presentation")
	assert_true(int(presentation.get("match_result", {}).get("winner_team", 1)) != 1, "Roman observer receives a losing result")


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
		print("I12-020J Zama bootstrap and outcome vertical tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
