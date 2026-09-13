extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	test_original_worker_contract(catalog)
	test_unique_approach_slots(catalog)
	test_complete_gather_cycle(catalog)

	if failures.is_empty():
		print("S-007 gather cycle tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_worker_contract(catalog) -> void:
	var villager: Dictionary = catalog.object_catalog_data.get("objects", {}).get("13:83", {})
	var forager: Dictionary = catalog.object_catalog_data.get("objects", {}).get("13:120", {})
	assert_float(float(villager.get("resources", {}).get("capacity", -1.0)), 0.0, "idle Villager source has no task inventory")
	assert_float(float(forager.get("resources", {}).get("capacity", 0.0)), 10.0, "Forager task form supplies original carry capacity")
	assert_equal(forager.get("resources", {}).get("drop_site_ids", []), [109.0, 68.0], "Forager task form supplies original drop-site links")
	assert_equal(catalog.unit_animation_frames("villager", "forager_work").size(), 135, "original forager work frames loaded")
	assert_equal(catalog.unit_animation_frames("villager", "lumberjack_work").size(), 75, "original lumber work frames loaded")
	assert_equal(catalog.unit_animation_frames("villager", "forager_carry").size(), 75, "original food carry frames loaded")
	assert_equal(catalog.unit_animation_frames("villager", "lumberjack_carry").size(), 75, "original wood carry frames loaded")
	assert_float(catalog.get_graphic_descriptor("villager", "forager_work").frame_duration, 0.12, "foraging descriptor uses original graphic timing")
	assert_float(catalog.get_graphic_descriptor("villager", "lumberjack_work").frame_duration, 0.1, "lumber descriptor uses original graphic timing")


func test_unique_approach_slots(catalog) -> void:
	var world = original_world(catalog)
	var resource: Dictionary = world.add_resource("tree", Vector2(8.0, 8.0), 30)
	var first: Dictionary = world.add_unit(1, "villager", Vector2(6.8, 7.7), false)
	var second: Dictionary = world.add_unit(1, "villager", Vector2(6.8, 8.3), false)
	world.assign_command_gather([first, second], int(resource["id"]))
	assert_true(first["resource_approach_slot"] is Vector2, "first worker receives approach slot")
	assert_true(second["resource_approach_slot"] is Vector2, "second worker receives approach slot")
	assert_true(Vector2(first["resource_approach_slot"]).distance_squared_to(second["resource_approach_slot"]) >= 0.09, "workers receive distinct approach slots")
	world.halt_unit(first, "test_stop")
	assert_equal(first["resource_approach_slot"], null, "stop releases resource approach slot")


func test_complete_gather_cycle(catalog) -> void:
	var world = original_world(catalog)
	world.add_building(900, "town_center", Vector2(12.0, 12.0), 1)
	var tree: Dictionary = world.add_resource("tree", Vector2(7.0, 7.5), 12)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(6.3, 7.5), false)
	var starting_wood: int = world.get_wood()
	world.assign_command_gather([worker], int(tree["id"]))
	var saw_work := false
	var saw_carry := false
	var saw_full_inventory := false
	var stockpile_before_first_deposit := true
	for unused in range(2400):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		saw_work = saw_work or worker["anim_state"] == AnimationController.GATHER
		saw_carry = saw_carry or worker["anim_state"] == AnimationController.CARRY
		saw_full_inventory = saw_full_inventory or is_equal_approx(float(worker["carried_amount"]), 10.0)
		if int(worker.get("deposit_cycles", 0)) == 0 and world.get_wood() != starting_wood:
			stockpile_before_first_deposit = false
		if int(worker.get("deposit_cycles", 0)) >= 2 and worker["task"] == "idle":
			break
	assert_true(saw_work, "worker enters work animation state at resource")
	assert_true(saw_carry, "full worker enters carry animation state on return")
	assert_true(saw_full_inventory, "inventory fills to original capacity")
	assert_true(stockpile_before_first_deposit, "resource is not credited remotely")
	assert_equal(world.get_wood(), starting_wood + 12, "two trips deposit exact depleted resource amount")
	assert_equal(tree["amount"], 0, "resource depletes after repeated cycle")
	assert_equal(worker["task"], "idle", "worker completes when source is depleted")
	assert_equal(roundi(worker["carried_amount"]), 0, "last partial load is deposited")
	assert_true(int(worker.get("deposit_cycles", 0)) >= 2, "worker returns to source and repeats cycle")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	return world


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
