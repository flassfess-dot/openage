extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var priest: Dictionary = world.add_unit(1, "priest", Vector2(4, 4), false)
	var ordinary: Dictionary = world.add_unit(2, "clubman", Vector2(6, 4), false)
	var ship: Dictionary = world.add_unit(2, "scout_ship", Vector2(6, 6), false)
	world.apply_unit_upgrade_to_entity(ship, 20, false)
	var chariot: Dictionary = world.add_unit(2, "chariot", Vector2(6, 8), false)
	assert_equal(String(ordinary["components"]["conversion_resistance"]["class"]), "ordinary", "ordinary target owns its normalized conversion class")
	assert_equal(String(ship["components"]["conversion_resistance"]["class"]), "ship", "ship target owns its normalized conversion class")
	assert_equal(int(ship.get("source_unit_id", -1)), 20, "War Galley fixture uses the upgraded source unit")
	assert_equal(String(chariot["components"]["conversion_resistance"]["class"]), "chariot", "chariot target owns its normalized conversion class")
	assert_near(world.conversion_system.resistance_multiplier(priest, ordinary), 1.0, "ordinary target keeps neutral resistance")
	# The two legacy defaults are provisional until the original-game matrix
	# distinguishes their exact values. Separate target policy fields already
	# permit them to vary independently without touching conversion logic.
	ship["components"]["conversion_resistance"]["chance_multiplier"] = 0.2
	chariot["components"]["conversion_resistance"]["chance_multiplier"] = 0.4
	ship["components"]["conversion_resistance"]["civilization_multiplier"] = 0.5
	chariot["components"]["conversion_resistance"]["civilization_multiplier"] = 0.75
	assert_near(world.conversion_system.resistance_multiplier(priest, ship), 0.1, "ship and civilization modifiers compose")
	assert_near(world.conversion_system.resistance_multiplier(priest, chariot), 0.3, "chariot and civilization modifiers compose independently")
	if failures.is_empty():
		print("P03 target conversion resistance policy tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, context: String) -> void:
	if absf(actual - expected) > 0.0001:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
