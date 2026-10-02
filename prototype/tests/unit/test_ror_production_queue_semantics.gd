extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	test_mixed_unit_queue(catalog)
	test_completion_time_population_block(catalog)
	test_mixed_research_queue(catalog)
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


func test_mixed_unit_queue(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 500)
	world.set_resource_amount(1, 1, 500)
	var building: Dictionary = world.add_building(710, "town_center", Vector2(10, 10), 1)
	for kind in ["clubman", "archer", "clubman"]:
		assert_true(world.enqueue_unit_production(710, 1, kind) != null, "%s joins the paid FIFO" % kind)
	assert_equal(building["production_queue"].map(func(order): return order["kind"]), ["clubman", "archer", "clubman"], "different unit lines preserve request order")
	var paid_food := 0
	for order in building["production_queue"]:
		paid_food += int(order["cost"].get(0, 0))
	assert_equal(world.get_resource_amount(1, 0), 500 - paid_food, "all accepted units pay at enqueue")
	world.update_production(1)
	assert_equal(float(building["production_queue"][1]["progress"]), 0.0, "waiting units cannot train in parallel")
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


func test_mixed_research_queue(catalog) -> void:
	var world = original_world(catalog)
	world.set_resource_amount(1, 0, 2000)
	var building: Dictionary = world.add_building(712, "town_center", Vector2(10, 10), 1)
	world.grant_technology(1, 0)
	world.grant_technology(1, 10)
	assert_true(world.enqueue_unit_production(712, 1, "clubman") != null, "unit starts before research")
	assert_true(world.enqueue_research(712, 1, 101) != null, "age research can wait behind a unit")
	assert_true(world.enqueue_unit_production(712, 1, "clubman") != null, "unit can wait behind research")
	assert_equal(building["production_queue"].map(func(order): return order["order_type"]), ["unit", "research", "unit"], "mixed FIFO preserves its order")
	assert_equal(building["components"]["technology"]["active_research_id"], -1, "waiting research does not impersonate the active operation")
	var before_duplicate: int = world.get_resource_amount(1, 0)
	assert_true(world.enqueue_research(712, 1, 101) == null, "reserved research cannot be queued twice")
	assert_equal(world.get_resource_amount(1, 0), before_duplicate, "duplicate request costs nothing")
	world.update_production(26)
	assert_equal(building["components"]["technology"]["active_research_id"], 101, "research becomes active only after the unit completes")
	assert_equal(float(building["production_queue"][0]["progress"]), 0.0, "new head starts with zero progress")
	world.update_production(120)
	assert_equal(world.get_current_age(1), 101, "mixed queue completes the original age technology")
	assert_equal(building["components"]["technology"]["active_research_id"], -1, "following unit clears the active research ID")
	assert_equal(building["production_queue"].size(), 1, "research completion retains the following unit")

	var upgrades = original_world(catalog)
	upgrades.set_runtime_catalog(catalog.runtime_catalog_data)
	upgrades.grant_technology(1, 101)
	upgrades.grant_technology(1, 39)
	upgrades.set_resource_amount(1, 0, 1000)
	var pit: Dictionary = upgrades.add_building(750, "storage_pit", Vector2(10, 10), 1)
	assert_true(upgrades.enqueue_research(750, 1, 40) != null, "first legal armor upgrade starts")
	assert_true(upgrades.enqueue_research(750, 1, 41) != null, "another armor upgrade waits behind it")
	assert_equal(upgrades.get_resource_amount(1, 0), 825, "both technologies pay exact original costs")
	upgrades.update_production(30)
	assert_true(upgrades.get_researched_technologies(1).has(40), "first upgrade applies its effects")
	assert_equal(pit["components"]["technology"]["active_research_id"], 41, "next research remains the active head after completion")
	assert_true(upgrades.cancel_production(750, 0), "next upgrade can be cancelled")
	assert_equal(upgrades.get_resource_amount(1, 0), 925, "cancelling refunds only the remaining upgrade")
	assert_true(not upgrades.technology_system.is_researching(1, 41), "cancelling releases its reservation")
	assert_true(upgrades.enqueue_research(750, 1, 41) != null, "cancelled research can be queued again")
	for _index in range(14):
		# Fill the same producer with ordinary paid units to exercise the shared limit.
		upgrades.set_resource_amount(1, 0, 10000)
		upgrades.production_system.enqueue_unit(750, 1, "clubman", false)
	assert_equal(pit["production_queue"].size(), 15, "units and research share the fifteen-order limit")
	assert_true(upgrades.enqueue_research(750, 1, 46) == null, "full mixed queue rejects additional research")
	assert_equal(upgrades.last_research_failure, "queue_full", "shared queue reports capacity explicitly")

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
