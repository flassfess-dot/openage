extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	var world = configured_world(catalog)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(6.0, 8.0), false)
	var town_center: Dictionary = world.add_building(700, "town_center", Vector2(20.0, 20.0), 1)
	var granary: Dictionary = world.add_building(701, "granary", Vector2(6.0, 12.0), 1)
	var storage_pit: Dictionary = world.add_building(702, "storage_pit", Vector2(11.0, 8.0), 1)

	world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, 0), false)
	worker["carried_resource_type_id"] = 0
	assert_equal(int(world.nearest_dropoff(worker)["id"]), int(granary["id"]), "food chooses nearby Granary instead of Town Center")
	world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, 1), false)
	worker["carried_resource_type_id"] = 1
	assert_equal(int(world.nearest_dropoff(worker)["id"]), int(storage_pit["id"]), "wood chooses nearby Storage Pit instead of Granary")
	world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, 3), false)
	worker["carried_resource_type_id"] = 3
	assert_equal(int(world.nearest_dropoff(worker)["id"]), int(storage_pit["id"]), "gold uses the same data-driven Storage Pit policy")
	assert_true(int(town_center["id"]) != int(world.nearest_dropoff(worker)["id"]), "more distant universal Town Center remains a fallback")
	var tied_storage_pit: Dictionary = world.add_building(699, "storage_pit", Vector2(6.0, 3.0), 1)
	assert_equal(int(world.nearest_dropoff(worker)["id"]), int(tied_storage_pit["id"]), "equidistant drop sites keep the stable lower-ID tie break")

	if failures.is_empty():
		print("I8-004 drop-site policy tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(28, 28))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
