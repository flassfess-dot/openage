extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_homogeneous_unit_queue(catalog)
	test_completion_time_population_block(catalog)
	test_research_is_exclusive(catalog)
	test_building_loss_refunds_only_waiting_orders(catalog)
	test_active_research_is_lost_with_building(catalog)
	test_stop_preserves_active_order(catalog)
	test_active_index_skips_idle_buildings(catalog)
	if failures.is_empty():
		print("P01 RoR production queue semantics tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_homogeneous_unit_queue(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 500)
	world.set_resource_amount(1, 1, 500)
	var building: Dictionary = world.add_building(710, "town_center", Vector2(10, 10), 1)
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "first unit starts the active line")
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "archer") == null, "different unit line cannot join an active queue")
	assert_equal(world.last_production_failure, "different_unit_line_queued", "different unit line has a stable rejection reason")
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "same unit line can add a waiting instance")
	assert_equal(building.get("production_queue", []).size(), 2, "only matching units occupy the queue")
	assert_equal(world.get_resource_amount(1, 0), 400, "both accepted units pay at enqueue, rejected line pays nothing")
	assert_equal(world.get_reserved_population(1), 0, "queued units do not reserve population")


func test_completion_time_population_block(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 500)
	var building: Dictionary = world.add_building(711, "town_center", Vector2(10, 10), 1)
	world.set_population_cap(1, 0)
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "unit may queue while population is full")
	world.update_production(26.0)
	assert_equal(world.get_units().size(), 0, "completed unit waits when population is full")
	var queue: Array = building.get("production_queue", [])
	if not queue.is_empty():
		assert_equal(String(queue[0].get("status", "")), "blocked_population", "ready unit exposes population block")
	world.set_population_cap(1, 1)
	world.update_production(0.05)
	assert_equal(world.get_units().size(), 1, "ready unit spawns after housing becomes available")
	assert_equal(world.get_reserved_population(1), 0, "completion does not release a nonexistent reservation")


func test_research_is_exclusive(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 1000)
	var building: Dictionary = world.add_building(712, "town_center", Vector2(10, 10), 1)
	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "unit queue starts before research request")
	assert_true(world.enqueue_research(int(building["id"]), 1, 101) == null, "research cannot wait behind a unit")
	assert_equal(world.last_research_failure, "building_busy", "busy producer explains research rejection")
	assert_true(world.cancel_production(int(building["id"]), 0), "explicit cancellation frees the producer")
	assert_true(world.enqueue_research(int(building["id"]), 1, 101) != null, "research starts in the idle producer")
	assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") == null, "unit cannot wait behind research")
	assert_equal(world.last_production_failure, "research_in_progress", "active research explains training rejection")
	assert_equal(building.get("production_queue", []).size(), 1, "research is the building's sole active operation")


func test_building_loss_refunds_only_waiting_orders(catalog) -> void:
	for loss_reason in ["destroyed", "converted"]:
		var world = original_world(catalog)
		world.set_resource_amount(1, 0, 500)
		var building: Dictionary = world.add_building(713, "town_center", Vector2(10, 10), 1)
		for _order in range(3):
			assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "%s fixture queues three Clubmen" % loss_reason)
		world.update_production(1.0)
		assert_equal(world.get_resource_amount(1, 0), 350, "%s fixture paid all three unit costs" % loss_reason)
		if loss_reason == "destroyed":
			world.begin_building_destruction(building)
		else:
			assert_true(world.transfer_entity_ownership(building, 2), "building conversion succeeds")
		assert_equal(world.get_resource_amount(1, 0), 450, "%s refunds two waiting orders but loses the active cost" % loss_reason)
		assert_equal(building.get("production_queue", []).size(), 0, "%s clears all orders" % loss_reason)
		assert_equal(world.production_system.active_building_ids, [], "%s removes the lost producer from the active index" % loss_reason)
		assert_equal(world.get_resource_amount(2, 0), 0, "%s never transfers queued resources to the new owner" % loss_reason)


func test_active_research_is_lost_with_building(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 1000)
	var building: Dictionary = world.add_building(714, "town_center", Vector2(10, 10), 1)
	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	assert_true(world.enqueue_research(int(building["id"]), 1, 101) != null, "active research starts before building loss")
	world.update_production(1.0)
	world.begin_building_destruction(building)
	assert_equal(world.get_resource_amount(1, 0), 500, "destroyed building loses the active research cost")
	assert_true(not world.technology_system.is_researching(1, 101), "building loss clears the active research marker")
	assert_equal(world.production_system.active_building_ids, [], "destroyed research producer leaves the active index")


func test_stop_preserves_active_order(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 500)
	var building: Dictionary = world.add_building(715, "town_center", Vector2(10, 10), 1)
	for _order in range(3):
		assert_true(world.enqueue_unit_production(int(building["id"]), 1, "clubman") != null, "Stop fixture queues three units")
	world.update_production(1.0)
	var active_id := int(building["production_queue"][0]["id"])
	var controller = GameController.new(world)
	var stop = Commands.StopCommand.new(1, [int(building["id"])])
	controller.enqueue_command(stop, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(stop.sequence_id).get("accepted", false)), "building Stop uses the public command path")
	assert_equal(building.get("production_queue", []).size(), 1, "Stop clears waiting orders only")
	assert_equal(int(building["production_queue"][0]["id"]), active_id, "Stop preserves the active order")
	assert_true(float(building["production_queue"][0]["progress"]) > 1.0, "active order continues after Stop")
	assert_equal(world.get_resource_amount(1, 0), 450, "Stop refunds both waiting orders")
	var stop_refunds := controller.events_after().filter(func(event): return String(event.get("type", "")) == "production_cancelled" and String(event.get("payload", {}).get("reason", "")) == "stop")
	assert_equal(stop_refunds.size(), 2, "Stop publishes one cancellation per waiting order")
	var foreign = world.add_building(716, "town_center", Vector2(15, 10), 2)
	world.set_resource_amount(2, 0, 100)
	assert_true(world.enqueue_unit_production(int(foreign["id"]), 2, "clubman") != null, "foreign fixture has an active order")
	assert_true(world.enqueue_unit_production(int(foreign["id"]), 2, "clubman") != null, "foreign fixture has a waiting order")
	var unauthorized = Commands.StopCommand.new(controller.tick_index + 1, [int(foreign["id"])])
	controller.enqueue_command(unauthorized, true, 1)
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_true(not bool(controller.get_command_result(unauthorized.sequence_id).get("accepted", false)), "issuer cannot Stop a foreign building")
	assert_equal(foreign.get("production_queue", []).size(), 2, "rejected foreign Stop leaves the queue untouched")


func test_active_index_skips_idle_buildings(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 500)
	var first: Dictionary = world.add_building(720, "town_center", Vector2(7, 10), 1)
	var second: Dictionary = world.add_building(721, "town_center", Vector2(14, 10), 1)
	for index in range(8):
		world.add_building(730 + index, "granary", Vector2(2 + index, 3), 1)
	assert_equal(world.production_system.active_building_ids, [], "idle buildings do not enter the per-tick production index")
	world.set_population_cap(1, 0)
	assert_true(world.enqueue_unit_production(int(second["id"]), 1, "clubman") != null, "later producer starts first")
	assert_true(world.enqueue_unit_production(int(first["id"]), 1, "clubman") != null, "earlier producer starts second")
	assert_equal(world.production_system.active_building_ids, [720, 721], "active producers retain world creation order")
	world.update_production(26.0)
	assert_equal(world.production_system.active_building_ids, [720, 721], "population-blocked producers remain active without visiting idle buildings")
	assert_equal(String(first["production_queue"][0].get("status", "")), "blocked_population", "first completed order waits for capacity")
	assert_equal(String(second["production_queue"][0].get("status", "")), "blocked_population", "second completed order waits for capacity")
	assert_true(world.cancel_production(720, 0), "cancelling the first blocked order succeeds")
	assert_equal(world.production_system.active_building_ids, [721], "cancellation removes only the emptied producer")
	assert_true(world.cancel_production(721, 0), "cancelling the second blocked order succeeds")
	assert_equal(world.production_system.active_building_ids, [], "no producers remain after both queues empty")


func original_world(catalog):
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
