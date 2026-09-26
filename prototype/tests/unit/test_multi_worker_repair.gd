extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var split := fixture(catalog)
	var combined := fixture(catalog)
	var split_world = split["world"]
	var combined_world = combined["world"]
	var initial_stock: int = int(split_world.get_resource_amount(1, 1))
	var first: float = float(split_world.advance_repair(split["workers"][0], split["target"], 5.0))
	var second: float = float(split_world.advance_repair(split["workers"][1], split["target"], 5.0))
	var whole: float = float(combined_world.advance_repair(combined["workers"][0], combined["target"], 10.0))
	assert_near(first + second, whole, "two workers sum their repair progress")
	assert_near(float(split["target"]["hp"]), float(combined["target"]["hp"]), "split and single repair restore equal HP")
	assert_equal(initial_stock - split_world.get_resource_amount(1, 1), initial_stock - combined_world.get_resource_amount(1, 1), "shared target pays the same cost once")
	split_world.set_resource_amount(1, 1, 0)
	var progress_before := float(split["target"]["hp"])
	for _step in range(100):
		split_world.advance_repair(split["workers"][0], split["target"], 5.0)
	assert_true(float(split["target"]["hp"]) < float(split["target"]["max_hp"]), "exhausted stock cannot complete large repair for free")
	assert_true(float(split["target"]["hp"]) >= progress_before, "lack of stock does not reverse repair")
	finish()


func fixture(catalog) -> Dictionary:
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_resource_amount(1, 1, 200)
	world.set_resource_amount(1, 2, 200)
	var target: Dictionary = world.add_building(700, "town_center", Vector2(12, 12), 1)
	target["hp"] = float(target["max_hp"]) - 100.0
	return {"world": world, "target": target, "workers": [world.add_unit(1, "villager", Vector2(7, 9), false), world.add_unit(1, "villager", Vector2(7, 10), false)]}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, context: String) -> void:
	if absf(actual - expected) > 0.0001:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P04 multi-worker repair passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
