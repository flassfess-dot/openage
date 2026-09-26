extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var ordinary = new_world(catalog, false)
	var full_tree = new_world(catalog, true)
	assert_true(ordinary.technology_system.is_technology_disabled(1, 37), "ordinary Roman tree retains its source technology exclusion")
	assert_true(not full_tree.technology_system.is_technology_disabled(1, 37), "Full Tech Tree lifts the civilization technology exclusion")
	assert_true(not full_tree.is_object_available(1, 360), "Fire Galley remains excluded even under Full Tech Tree")
	full_tree.grant_technology(1, 118)
	assert_true(not full_tree.is_object_available(1, 360), "Fire Galley cannot be restored by its automatic availability technology")
	assert_equal(full_tree.technology_system.trade_profit_multiplier(1), ordinary.technology_system.trade_profit_multiplier(1), "Full Tech Tree does not erase civilization identity")
	if failures.is_empty():
		print("P09 Full Tech Tree rule tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func new_world(catalog, full_tech_tree: bool):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.full_tech_tree_enabled = full_tech_tree
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.reset_game()
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
