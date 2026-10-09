extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const Commands := preload("res://scripts/commands.gd")
const Geometry := preload("res://scripts/formation_geometry.gd")
const Orders := preload("res://scripts/order_pipeline.gd")

var failures: Array[String] = []
var catalog := Catalog.new()


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	catalog.load_generated_data()
	for native in [false, true]:
		test_selected_groups_vacate_old_slots_together(native)
		test_unselected_group_keeps_its_reservation(native)
		test_three_cavalry_rotate_without_phantom_slots(native)
	for failure in failures: push_error(failure)
	print("Formation destination reassignment: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func test_selected_groups_vacate_old_slots_together(native: bool) -> void:
	var fixture := make_fixture(native)
	var world = fixture["world"]
	var controller = fixture["controller"]
	var ids: Array[int] = fixture["ids"]
	var group_ids: Array = ids.map(func(id): return world.find_unit(id)["formation_group_id"])
	# The middle rider is assigned first. Its new slot is still occupied by the
	# next selected rider's old reservation unless the order releases all three.
	for offset in [Vector2.DOWN, Vector2.UP, Vector2.DOWN * 2.0]:
		var original: Array = ids.map(func(id): return Vector2(world.find_unit(id)["pos"]))
		var center: Vector2 = (original[0] + original[1] + original[2]) / 3.0
		var command = Commands.FormationMoveCommand.new(controller.tick_index + 1, ids, center + offset, "COLUMN", Vector2.DOWN)
		command.params["preserve_formations"] = true
		controller.enqueue_command(command)
		flush(controller)
		for index in range(ids.size()):
			var unit: Dictionary = world.find_unit(ids[index])
			check(Vector2(unit["destination"]).is_equal_approx(original[index] + offset), "no phantom gap when selected groups exchange slots (native=%s id=%d expected=%s actual=%s)" % [native, ids[index], original[index] + offset, unit["destination"]])
			check(unit["formation_group_id"] == group_ids[index], "combined movement keeps independent group identity")
			check(unit["preferred_formation"] == "LINE", "combined movement keeps each group's formation")
		settle(controller)
		for index in range(ids.size()):
			check(Vector2(world.find_unit(ids[index])["pos"]).distance_to(original[index] + offset) < 0.04, "three cavalry actually reach all three adjacent slots (native=%s id=%d)" % [native, ids[index]])
	world.task_coordinator.shutdown()


func test_unselected_group_keeps_its_reservation(native: bool) -> void:
	var fixture := make_fixture(native)
	var world = fixture["world"]
	var controller = fixture["controller"]
	var ids: Array[int] = fixture["ids"]
	var bystander: Dictionary = world.add_unit(1, "cavalry", Vector2(20.5, 22.5), false)
	bystander["stance"] = "passive"
	controller._assign_formation([bystander], bystander["pos"], "LINE", Vector2.DOWN)
	var reserved: Vector2 = world.destination_reservations.assigned_position(bystander["id"])
	var command = Commands.FormationMoveCommand.new(controller.tick_index + 1, ids, Vector2(20.5, 21.5), "LINE", Vector2.DOWN)
	command.params["preserve_formations"] = true
	controller.enqueue_command(command)
	flush(controller)
	check(world.destination_reservations.assigned_position(bystander["id"]) == reserved, "an unselected group's reservation remains intact")
	for id in ids:
		var unit: Dictionary = world.find_unit(id)
		var clearance: float = unit["footprint_radius"] + bystander["footprint_radius"] + 0.02
		check(Vector2(unit["destination"]).distance_to(reserved) >= clearance, "selected riders still avoid a real occupied destination")
	world.task_coordinator.shutdown()


func test_three_cavalry_rotate_without_phantom_slots(native: bool) -> void:
	var fixture := make_fixture(native)
	var world = fixture["world"]
	var controller = fixture["controller"]
	var ids: Array[int] = fixture["ids"]
	var center := Vector2(20.5, 20.5)
	for forward in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2(1, 1)]:
		controller.enqueue_command(Commands.FormationMoveCommand.new(controller.tick_index + 1, ids, center, "LINE", forward))
		flush(controller)
		var group = controller.formation_groups[world.find_unit(ids[0])["formation_group_id"]]
		check(group.slots.size() == 3, "three riders create exactly three slots")
		var expected := Geometry.world_slots(Geometry.local_slots(3, "LINE", group.spacing), center, forward)
		for slot in expected:
			var occupants: int = ids.filter(func(id): return Vector2(world.find_unit(id)["destination"]).is_equal_approx(slot)).size()
			check(occupants == 1, "every slot in a three-rider line has exactly one assigned rider")
		for id in ids:
			var unit: Dictionary = world.find_unit(id)
			if Vector2(unit["pos"]).distance_to(unit["destination"]) < 0.001:
				check(unit["diagnostic_reason"] != "no_group_route", "an already placed rider does not report a missing route")
				check(bool(Orders.current(unit)["completed"]), "an already placed rider completes the order immediately")
				check(unit["facing"] == world.facing_for_vector(forward), "an already placed rider still turns with the group")
		settle(controller)
		for slot in expected:
			check(ids.filter(func(id): return Vector2(world.find_unit(id)["pos"]).distance_to(slot) < 0.04).size() == 1, "rotation finishes as a dense three-rider line (native=%s forward=%s)" % [native, forward])
	world.task_coordinator.shutdown()


func make_fixture(native: bool) -> Dictionary:
	var world := World.new(Vector2i(64, 64))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.pathfinder.set_native_enabled(native)
	world.add_unit(2, "cavalry", Vector2(60, 60), false)["stance"] = "passive"
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = []
	for position in [Vector2(20.5, 20.5), Vector2(20.5, 21.5), Vector2(20.5, 19.5)]:
		var unit: Dictionary = world.add_unit(1, "cavalry", position, false)
		unit["stance"] = "passive"
		ids.append(int(unit["id"]))
		controller._assign_formation([unit], position, "LINE", Vector2.DOWN)
	return {"world": world, "controller": controller, "ids": ids}


func settle(controller) -> void:
	for tick in range(200): controller.advance_frame(0.05, 1, 2)


func flush(controller) -> void:
	controller.tick_index += 1
	controller.process_commands()


func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
