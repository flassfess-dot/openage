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
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var priest: Dictionary = world.add_unit(1, "priest", Vector2(5, 5), false)
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(6, 5), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(7, 5), false)
	world.add_unit(2, "clubman", Vector2(20, 20), false)
	first["hp"] = float(first["max_hp"]) - 0.2
	second["hp"] = float(second["max_hp"]) - 2.0
	first["components"]["health"]["current"] = first["hp"]
	second["components"]["health"]["current"] = second["hp"]
	world.update_fog_of_war()
	assert_equal(world.assign_command_heal([priest], int(first["id"])), "", "first explicit healing order is accepted")
	var chained := false
	for _step in range(200):
		world.advance(0.05, 1, 2)
		if String(priest.get("task", "")) == "heal" and int(priest.get("target_id", -1)) == int(second["id"]):
			chained = true
			break
	assert_true(chained, "completed healing chains to nearby injured ally")
	assert_near(float(first["hp"]), float(first["max_hp"]), "first ally reaches full health before chain")
	assert_true(float(second["hp"]) < float(second["max_hp"]), "second ally remains a distinct target")
	if failures.is_empty():
		print("P04 bounded priest auto-heal chain tests passed")
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


func assert_near(actual: float, expected: float, context: String) -> void:
	if absf(actual - expected) > 0.0001:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
