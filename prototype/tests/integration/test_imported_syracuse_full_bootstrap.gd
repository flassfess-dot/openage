extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const MATCH_PATH := "res://assets/generated/matches/syracuse.json"

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
	verify_archimedes_defeat(world)
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
	assert_equal(world.get_units().size(), 165, "Syracuse creates every source-owned runtime unit")
	assert_equal(world.get_buildings().size(), 522, "Syracuse creates every source-owned runtime building")
	assert_equal(world.get_resources().size(), 1281, "Syracuse creates every source-owned resource")
	assert_equal(world.get_static_obstructions().size(), 199, "all source cliffs and obstructions reach navigation")
	assert_equal(world.get_current_age(1), 103, "Rome starts in the source Iron Age")
	assert_equal(world.get_current_age(2), 103, "Carthage retains Iron as the Post-Iron authoritative age")
	assert_equal(world.get_current_age(3), 103, "Syracuse retains Iron as the Post-Iron authoritative age")
	assert_equal(world.get_current_age(4), 101, "Greek reinforcements start in the source Tool Age")
	assert_true(world.get_researched_technologies(2).has(37), "first Post-Iron player receives allowed Iron technologies")
	assert_true(world.get_researched_technologies(3).has(37), "second Post-Iron player receives allowed Iron technologies")
	assert_source_count(world.get_units(), 6, 22, "all Composite Bowmen retain exact source identity")
	assert_source_count(world.get_units(), 38, 10, "all Heavy Cavalry retain exact source identity")
	assert_source_count(world.get_units(), 360, 6, "all Fire Galleys retain exact source identity")
	assert_source_count(world.get_buildings(), 383, 8, "all Mirror Towers retain exact source identity")
	var targets := archimedes_targets(world)
	assert_equal(targets.size(), 1, "exact Archimedes target enters runtime once")
	assert_true(targets.size() == 1 and int(targets[0].get("scenario_source_unit_id", -1)) == 382, "immutable Archimedes source identity survives bootstrap")


func verify_source_victory(world) -> void:
	for index in range(9):
		add_legion(world, Vector2(75.0 + float(index), 32.0))
	world.check_battle_state(1, 2, 0.05)
	assert_true(not world.is_battle_over(), "nine Legions inside the source area do not complete the mission")
	add_legion(world, Vector2(84.0, 32.0))
	world.check_battle_state(1, 2, 0.05)
	assert_true(world.is_battle_over(), "ten exact Legions inside the source area complete the mission")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 1, "source create-in-area condition awards victory to Rome")
	assert_equal(String(world.get_victory_result().get("reason", "")), "scenario", "Roman source victory retains the scenario reason")


func verify_archimedes_defeat(world) -> void:
	var targets := archimedes_targets(world)
	assert_equal(targets.size(), 1, "Archimedes is available after clean bootstrap")
	if targets.size() != 1:
		return
	world.begin_death(targets[0])
	world.check_battle_state(1, 2, 0.05)
	assert_true(world.is_battle_over(), "losing exact Hero Archimedes ends the mission")
	assert_equal(int(world.get_victory_result().get("winner_team", -1)), 2, "deterministic source participant order awards the shared objective to team 2")
	assert_equal(String(world.get_victory_result().get("reason", "")), "scenario", "Archimedes defeat retains the scenario reason")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, 2, 1, {"include_navigation": false, "include_build_sites": false})
	assert_true(bool(presentation.get("match_result", {}).get("over", false)), "source defeat reaches local read-only presentation")
	assert_equal(int(presentation.get("match_result", {}).get("winner_team", -1)), 2, "Roman observer receives the source losing result")


func add_legion(world, position: Vector2) -> void:
	var legion: Dictionary = world.add_unit(1, "swordsman", position, false)
	world.apply_unit_upgrade_to_entity(legion, 282)


func archimedes_targets(world) -> Array:
	return world.get_units().filter(func(unit): return int(unit.get("scenario_object_id", -1)) == 5998)


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
		print("I12-020I Syracuse bootstrap and outcome vertical tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
