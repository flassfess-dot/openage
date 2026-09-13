extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	test_explicit_return_and_resource_types(catalog)
	if failures.is_empty():
		print("I8-006 return-resources integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_explicit_return_and_resource_types(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var town_center: Dictionary = world.add_building(700, "town_center", Vector2(10.0, 10.0), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(6.0, 9.0), false)
	var source: Dictionary = world.add_resource("tree", Vector2(5.0, 5.0), 3)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(18.0, 18.0), false)
	enemy["stance"] = "passive"
	world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, 1), false)
	worker["resource_id"] = int(source["id"])
	for _amount in range(3):
		world.gather(int(source["id"]), worker)
	var starting_wood := world.get_wood()
	var controller := GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var return_command = Commands.ReturnResourcesCommand.new(1, [int(worker["id"])], int(town_center["id"]))
	controller.enqueue_command(return_command, true, 1)
	for _tick in range(500):
		controller.advance_frame(0.05, 1, 2)
		if float(worker.get("carried_amount", 0.0)) <= 0.0:
			break
	assert_true(bool(controller.get_command_result(return_command.sequence_id).get("accepted", false)), "explicit return command is accepted")
	assert_equal(world.get_wood(), starting_wood + 3, "explicit return deposits the exact carried amount")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "resources_deposited"), "deposit is forwarded as domain event")

	var granary: Dictionary = world.add_building(701, "granary", Vector2(5.0, 12.0), 1)
	worker["carried_amount"] = 2.0
	worker["carried_resource_type_id"] = 1
	var wrong_dropoff = Commands.ReturnResourcesCommand.new(controller.tick_index + 1, [int(worker["id"])], int(granary["id"]))
	controller.enqueue_command(wrong_dropoff, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(controller.get_command_result(wrong_dropoff.sequence_id).get("reason"), "invalid_dropoff", "specialized building rejects wrong resource class")

	worker["carried_amount"] = 4.0
	worker["carried_resource_type_id"] = 2
	world.deposit_carried_resources(worker)
	assert_equal(world.get_resource_amount(1, 2), 4, "stone is credited by generic deposit path")
	worker["carried_amount"] = 5.0
	worker["carried_resource_type_id"] = 3
	world.deposit_carried_resources(worker)
	assert_equal(world.get_resource_amount(1, 3), 5, "gold is credited by generic deposit path")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
