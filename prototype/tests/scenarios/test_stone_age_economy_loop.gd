extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	test_worker_to_first_military_unit(catalog)
	if failures.is_empty():
		print("I8-001 Stone Age economic loop scenario passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_worker_to_first_military_unit(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var town_center: Dictionary = world.add_building(900, "town_center", Vector2(12.0, 12.0), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(8.0, 9.0), false)
	var tree: Dictionary = world.add_resource("tree", Vector2(8.8, 9.0), 12)
	world.add_unit(2, "clubman", Vector2(22.0, 22.0), false)
	var controller := GameController.new(world)
	var starting_wood := world.get_wood()
	var gather = Commands.GatherCommand.new(1, [int(worker["id"])], int(tree["id"]))
	controller.enqueue_command(gather, true, 1)
	for _tick in range(2600):
		controller.advance_frame(0.05, 1, 2)
		if int(tree["amount"]) == 0 and String(worker["task"]) == "idle":
			break
	assert_true(bool(controller.get_command_result(gather.sequence_id).get("accepted", false)), "gather command is accepted")
	if world.get_wood() != starting_wood + 12:
		var nearest: Variant = world.nearest_dropoff(worker)
		print("I8-001 gather diagnostic worker=%s tree=%s nearest_dropoff_id=%d" % [{"pos": worker.get("pos"), "task": worker.get("task"), "reason": worker.get("diagnostic_reason"), "carried": worker.get("carried_amount"), "stage": worker.get("gather_stage"), "dropoff": worker.get("dropoff_id"), "path_status": worker.get("path_status")}, {"amount": tree.get("amount"), "pos": tree.get("pos")}, int(nearest.get("id", -1)) if nearest != null else -1])
	assert_equal(world.get_wood(), starting_wood + 12, "physical gather/carry/deposit credits the exact resource")

	var build_position := Vector2(7.0, 13.0)
	var barracks_cost: Dictionary = world.building_cost("barracks", 1)
	var build = Commands.BuildCommand.new(controller.tick_index + 1, [int(worker["id"])], "barracks", build_position)
	controller.enqueue_command(build, true, 1)
	var barracks: Variant = null
	for _tick in range(1800):
		controller.advance_frame(0.05, 1, 2)
		var candidates: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "barracks")
		if not candidates.is_empty():
			barracks = candidates[0]
			if String(barracks.get("state", "")) == "complete":
				break
	assert_true(bool(controller.get_command_result(build.sequence_id).get("accepted", false)), "Barracks build command is accepted")
	assert_true(barracks != null and String(barracks.get("state", "")) == "complete", "worker completes the Barracks physically (state=%s progress=%.3f task=%s reason=%s)" % [String(barracks.get("state", "missing")) if barracks != null else "missing", float(barracks.get("construction_progress", 0.0)) if barracks != null else 0.0, String(worker.get("task", "")), String(worker.get("diagnostic_reason", ""))])
	assert_equal(world.get_wood(), starting_wood + 12 - int(barracks_cost.get(1, 0)), "civilization-adjusted Barracks wood cost is charged once")
	assert_true(world.is_object_available(1, 73), "completed Barracks unlocks Clubman through source technology 62")

	var rally := Vector2(15.0, 12.0)
	var train = Commands.TrainCommand.new(controller.tick_index + 1, [int(barracks["id"])], "clubman", 1, rally)
	controller.enqueue_command(train, true, 1)
	for _tick in range(700):
		controller.advance_frame(0.05, 1, 2)
		if world.get_units().any(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "clubman"):
			break
	assert_true(bool(controller.get_command_result(train.sequence_id).get("accepted", false)), "train command is accepted after gathering")
	var trained: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "clubman")
	assert_equal(trained.size(), 1, "production queue creates the first military unit")
	assert_equal(world.get_food(), 130, "original Clubman food cost is charged once")
	assert_equal(world.get_population(1), 2, "completed Clubman joins the living population")

	var events := controller.events_after()
	assert_true(events.any(func(event): return String(event["type"]) == "resource_gathered"), "gather progress is observable")
	assert_true(events.any(func(event): return String(event["type"]) == "resources_deposited"), "stockpile deposit is observable")
	assert_true(events.any(func(event): return String(event["type"]) == "foundation_placed"), "foundation reservation is observable")
	assert_true(events.any(func(event): return String(event["type"]) == "build_complete"), "building completion is observable")
	assert_true(events.any(func(event): return String(event["type"]) == "building_technology_unlocked"), "building unlock is observable")
	assert_true(events.any(func(event): return String(event["type"]) == "production_queued"), "production request is observable")
	assert_true(events.any(func(event): return String(event["type"]) == "unit_produced"), "production completion is observable")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
