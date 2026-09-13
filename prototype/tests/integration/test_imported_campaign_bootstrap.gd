extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const MapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var sample_entities: Array = []
	for source_id in [74, 70, 53]:
		var found: Variant = definition.get("entities", []).filter(func(entity): return int(entity.get("source_unit_id", -1)) == source_id).front()
		assert_true(found is Dictionary, "source object %d is available for bootstrap sample" % source_id)
		if found is Dictionary:
			sample_entities.append(found)
	definition["entities"] = sample_entities

	var catalog := ResourceCatalog.new()
	catalog.load()
	var map_data := MapGenerator.generate(definition)
	var world := SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	MatchBootstrap.apply(world, definition, map_data)

	assert_equal(world.get_units().size(), 1, "campaign unit enters the normal simulation world")
	assert_equal(world.get_buildings().size(), 1, "campaign building enters the normal simulation world")
	assert_equal(world.get_resources().size(), 1, "campaign resource enters the normal simulation world")
	for entity in [world.get_units()[0], world.get_buildings()[0], world.get_resources()[0]]:
		assert_true(int(entity.get("scenario_object_id", -1)) >= 0, "bootstrapped entity keeps scenario object identity")
	assert_equal(int(world.get_units()[0].get("scenario_source_unit_id", -1)), 74, "unit keeps its immutable scenario DAT id")
	assert_equal(int(world.get_units()[0].get("source_unit_id", -1)), 74, "unit keeps its source upgrade variant")
	assert_equal(int(world.get_buildings()[0].get("scenario_source_unit_id", -1)), 70, "building keeps its immutable scenario DAT id")
	assert_equal(int(world.get_buildings()[0].get("source_unit_id", -1)), 154, "Bronze Age start resolves the building to its active DAT variant")
	assert_equal(int(world.get_resources()[0].get("scenario_source_unit_id", -1)), 53, "resource keeps its immutable scenario DAT id")
	assert_equal(int(world.get_resources()[0].get("source_unit_id", -1)), 53, "resource keeps its source variant id")
	assert_equal(world.get_units()[0].get("kind"), "clubman", "source variant still uses the shared logical archetype")
	assert_equal(world.get_resources()[0].get("kind"), "deep_fish", "source fish variant still uses the shared logical archetype")

	if failures.is_empty():
		print("I12-020B imported campaign bootstrap tests passed")
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
