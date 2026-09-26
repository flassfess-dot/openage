extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_original_production_contract(catalog)
	test_queue_completion_and_rally(catalog)
	test_default_rally_keeps_valid_exit(catalog)
	test_same_line_cancel_refund(catalog)

	if failures.is_empty():
		print("S-009 production queue tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_production_contract(catalog) -> void:
	var clubman: Dictionary = catalog.gamespec_data.get("units", {}).get("clubman", {})
	var archer: Dictionary = catalog.gamespec_data.get("units", {}).get("archer", {})
	assert_equal(int(clubman.get("creation_time", 0)), 26, "original Clubman creation time")
	assert_equal(int(clubman.get("resource_cost", [])[0].get("amount", 0)), 50, "original Clubman food cost")
	assert_equal(int(archer.get("resource_cost", [])[0].get("amount", 0)), 40, "original Bowman food cost")
	assert_equal(int(archer.get("resource_cost", [])[1].get("amount", 0)), 20, "original Bowman wood cost")


func test_queue_completion_and_rally(catalog) -> void:
	var world = original_world(catalog)
	world.food = 500
	world.wood = 500
	var building: Dictionary = world.add_building(700, "town_center", Vector2(10.0, 10.0), 1)
	var rally := Vector2(15.0, 12.0)
	world.set_rally_point(int(building["id"]), rally)
	var order: Variant = world.enqueue_unit_production(int(building["id"]), 1, "clubman")
	assert_true(order != null, "valid production request enters queue")
	assert_equal(world.get_food(), 450, "unit cost is deducted on enqueue")
	assert_equal(world.get_units().size(), 0, "enqueue does not spawn immediately")
	world.update_production(25.9)
	assert_equal(world.get_units().size(), 0, "unit remains queued before original duration")
	assert_true(float(building["production_progress"]) > 0.99, "building exposes production progress")
	world.update_production(0.1)
	assert_equal(world.get_units().size(), 1, "unit spawns when duration completes")
	var trained: Dictionary = world.get_units()[0]
	assert_equal(trained["kind"], "clubman", "queue spawns requested unit kind")
	assert_true(trained["pos"].distance_to(building["pos"]) > 1.5, "spawn slot lies outside building footprint")
	assert_equal(trained["destination"], rally, "new unit receives current rally point")
	assert_equal(world.get_population(1), 1, "completed unit consumes population")
	assert_equal(building["production_queue"].size(), 0, "completed item leaves queue")


func test_same_line_cancel_refund(catalog) -> void:
	var world = original_world(catalog)
	world.food = 500
	world.wood = 500
	var building: Dictionary = world.add_building(701, "town_center", Vector2(10.0, 10.0), 1)
	var first: Variant = world.enqueue_unit_production(int(building["id"]), 1, "archer")
	var second: Variant = world.enqueue_unit_production(int(building["id"]), 1, "archer")
	assert_true(first != null and second != null, "multiple instances of one unit line can queue")
	assert_equal(world.get_food(), 420, "queue deducts food for both entries")
	assert_equal(world.get_wood(), 460, "queue deducts wood for both entries")
	world.update_production(1.0)
	assert_float(float(building["production_queue"][1]["progress"]), 0.0, "only queue head advances")
	assert_true(world.cancel_production(int(building["id"]), 0), "queued item can be cancelled")
	assert_equal(world.get_food(), 460, "cancel refunds one archer food cost")
	assert_equal(world.get_wood(), 480, "cancel refunds one archer wood cost")
	assert_true(world.cancel_production(int(building["id"]), 0), "remaining item can be cancelled")
	assert_equal(world.get_food(), 500, "all cancelled costs fully refunded")
	assert_equal(world.get_wood(), 500, "all cancelled wood costs fully refunded")


func test_default_rally_keeps_valid_exit(catalog) -> void:
	var world = original_world(catalog)
	world.food = 500
	var building: Dictionary = world.add_building(702, "town_center", Vector2(10.0, 10.0), 1)
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "default-rally production enters the queue")
	world.update_production(26.0)
	var trained: Dictionary = world.get_units()[0]
	assert_equal(trained.get("task"), "idle", "default rally leaves the trained unit at its valid exit slot")
	assert_equal(trained.get("diagnostic_reason"), "", "default rally never orders a path into the blocked building center")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
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
