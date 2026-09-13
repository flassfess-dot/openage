extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	var world = configured_world(catalog)
	assert_equal(world.get_population_cap(1), 50, "compatibility cap remains until a housing provider exists")
	var town_center: Dictionary = world.add_building(700, "town_center", Vector2(12.0, 12.0), 1)
	assert_equal(int(town_center.get("population_support", 0)), 4, "Town Center support comes from source storage resource 4")
	assert_equal(world.get_population_cap(1), 4, "completed Town Center activates housing model")
	var house: Dictionary = world.add_building(701, "house", Vector2(6.0, 12.0), 1)
	assert_equal(world.get_population_cap(1), 8, "completed House adds four population capacity")
	world.set_population_cap(1, 6)
	assert_equal(world.get_population_cap(1), 6, "global match limit caps available housing")
	world.begin_building_destruction(house)
	assert_equal(world.economy_system.get_population_housing(1), 4, "destroyed House removes its housing contribution")
	assert_equal(world.get_population_cap(1), 4, "effective cap follows surviving providers")

	var foundation: Dictionary = world.add_building(702, "house", Vector2(18.0, 12.0), 1, false)
	assert_equal(world.get_population_cap(1), 4, "foundation does not provide population")
	world.complete_foundation(foundation)
	assert_equal(world.get_population_cap(1), 6, "completed foundation provides housing up to match limit")

	if failures.is_empty():
		print("I8-005 population support tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
