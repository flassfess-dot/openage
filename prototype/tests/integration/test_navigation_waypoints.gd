extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Orders := preload("res://scripts/order_pipeline.gd")
const Replay := preload("res://scripts/replay_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	for native in [false, true]:
		for domain in ["land", "water"]:
			test_resolved_segment_cursor_and_arrival(native, domain)
			test_failed_segments_are_terminal(native, domain, true)
			test_failed_segments_are_terminal(native, domain, false)
			test_unreachable_intermediate_and_substituted_final(native, domain)
			test_duplicate_waypoints_and_zero_distance(native, domain)
			test_legacy_corner_escape(native, domain)
			test_off_centre_path_endpoints(native, domain)
		test_rejected_formation_and_next_queued_order(native)
		test_global_repath_clears_active_planner(native)
		test_waypoint_reproducibility(native)
	for failure in failures: push_error(failure)
	print("Navigation waypoints: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func make_world(native: bool, domain: String = "land", barrier: bool = false):
	var world := World.new(Vector2i(24, 20))
	world.navigation_grid.configure_terrain(func(cell):
		return ("grass" if domain == "water" else "water") if barrier and cell.x == 12 else ("water" if domain == "water" else "grass"))
	world.set_gamespec({"units": {
		"clubman": {"hit_points": 100.0, "speed": 1.5, "selection_radius": [0.3, 0.3, 1.0]},
		"scout_ship": {"terrain_restriction": 3, "hit_points": 100.0, "speed": 1.5, "selection_radius": [0.3, 0.3, 1.0]},
	}})
	world.pathfinder.set_native_enabled(native)
	world.add_unit(2, "scout_ship" if domain == "water" else "clubman", Vector2(21.5, 17.5), false)["stance"] = "passive"
	for y in range(world.map_size.y):
		for x in range(world.map_size.x): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	return world


func add_member(world, domain: String, position: Vector2) -> Dictionary:
	var unit: Dictionary = world.add_unit(1, "scout_ship" if domain == "water" else "clubman", position, false)
	unit["stance"] = "passive"
	world.set_entity_field(unit, "task", "move")
	return unit


func test_resolved_segment_cursor_and_arrival(native: bool, domain: String) -> void:
	var world = make_world(native, domain)
	world.navigation_grid.occupy([Vector2i(8, 8)], "static", 100)
	var unit := add_member(world, domain, Vector2(5.5, 8.5))
	var points: Array[Vector2] = [Vector2(8.5, 8.5), Vector2(10.5, 8.5)]
	check(world.assign_unit_waypoints(unit, points, points[-1]), "adjusted intermediate endpoint remains routable (%s %s)" % [native, domain])
	var planner = world.movement_system.knowledge.planner(world, 1)
	var previous := Vector2i(Vector2(unit["pos"]).floor())
	for waypoint in unit["path"]:
		var next := Vector2i(Vector2(waypoint).floor())
		check(planner.line_walkable(previous, next, domain, unit["terrain_restriction"], unit["footprint_radius"]), "combined route has no discontinuity after endpoint adjustment (%s %s)" % [native, domain])
		previous = next
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	for tick in range(240):
		controller.advance_frame(0.05, 1, 2)
		if unit["task"] == "idle": break
	check(Vector2(unit["pos"]).distance_to(points[-1]) < 0.04, "unit physically completes the combined route (%s %s pos=%s)" % [native, domain, unit["pos"]])
	check(bool(Orders.current(unit)["completed"]), "arrival completes the waypoint order")
	world.task_coordinator.shutdown()


func test_failed_segments_are_terminal(native: bool, domain: String, partial: bool) -> void:
	var world = make_world(native, domain, true)
	var unit := add_member(world, domain, Vector2(5.5, 8.5))
	check(world.assign_unit_destination(unit, Vector2(7.5, 8.5)), "failed-route fixture begins with an active previous route")
	var points: Array[Vector2] = []
	if partial: points.append(Vector2(8.5, 8.5))
	points.append(Vector2(18.5, 8.5))
	check(not world.assign_unit_waypoints(unit, points, points[-1]), "a failed segment rejects the whole route (%s %s partial=%s)" % [native, domain, partial])
	check(unit["task"] == "idle" and unit["path"].is_empty(), "failed route leaves no executable partial path")
	check(unit["target"] == unit["pos"] and unit["destination"] == unit["pos"], "failed route stops its old motion")
	check(unit["reserved_destination"] == null and world.destination_reservations.assigned_position(unit["id"]) == null, "failed route releases its endpoint reservation")
	check(bool(Orders.current(unit)["completed"]) and Orders.current(unit)["completion_reason"] == "no_group_route", "failed route completes the order with a reason")
	check(unit["path_status"] == "unreachable", "failed route keeps its navigation failure status")
	var request_id: int = world.navigation_service.next_request_id
	var origin: Vector2 = unit["pos"]
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	for tick in range(40): controller.advance_frame(0.05, 1, 2)
	check(unit["pos"] == origin and world.navigation_service.next_request_id == request_id, "terminal failure neither moves nor repeatedly plans")
	world.task_coordinator.shutdown()


func test_unreachable_intermediate_and_substituted_final(native: bool, domain: String) -> void:
	var world = make_world(native, domain, true)
	var unit := add_member(world, domain, Vector2(5.5, 8.5))
	var points: Array[Vector2] = [Vector2(18.5, 8.5), Vector2(8.5, 8.5)]
	check(not world.assign_unit_waypoints(unit, points, points[-1]), "unreachable intermediate waypoint cannot be silently skipped")
	check(unit["path"].is_empty() and bool(Orders.current(unit)["completed"]), "intermediate failure is terminal even when the final point is reachable")
	world.task_coordinator.shutdown()
	world = make_world(native, domain)
	world.navigation_grid.occupy([Vector2i(8, 7)], "static", 100)
	unit = add_member(world, domain, Vector2(5.5, 8.5))
	world.set_entity_field(unit, "footprint_radius", 0.6)
	var destination := Vector2(8.8, 8.8)
	check(world.navigation_grid.is_position_walkable_for(destination, 0.6, domain, unit["terrain_restriction"]), "subcell final reservation is physically valid")
	points = [destination]
	check(not world.assign_unit_waypoints(unit, points, destination), "a substituted final endpoint cannot fulfil the reserved destination")
	check(unit["reserved_destination"] == null and bool(Orders.current(unit)["completed"]), "substituted final endpoint failure releases the reservation")
	world.task_coordinator.shutdown()


func test_duplicate_waypoints_and_zero_distance(native: bool, domain: String) -> void:
	var world = make_world(native, domain)
	var unit := add_member(world, domain, Vector2(5.5, 8.5))
	var points: Array[Vector2] = [unit["pos"], unit["pos"]]
	check(world.assign_unit_waypoints(unit, points, unit["pos"]), "zero distance is successful arrival")
	check(unit["path_status"] == "arrived" and bool(Orders.current(unit)["completed"]), "zero distance completes without a path failure")
	world.set_entity_field(unit, "task", "move")
	points = [Vector2(8.5, 8.5), Vector2(8.5, 8.5)]
	check(world.assign_unit_waypoints(unit, points, points[-1]), "duplicate final waypoint remains accepted")
	check(unit["path_status"] == "resolved" and unit["path"].size() == 1, "duplicate waypoint does not overwrite route status with unreachable")
	world.task_coordinator.shutdown()


func test_rejected_formation_and_next_queued_order(native: bool) -> void:
	var world = make_world(native, "land", true)
	var unit := add_member(world, "land", Vector2(5.5, 8.5))
	world.set_entity_field(unit, "task", "idle")
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(unit["id"])]
	var failed := Commands.FormationMoveCommand.new(1, ids, Vector2(18.5, 8.5), "LINE", Vector2.RIGHT)
	controller.enqueue_command(failed, false, 1)
	controller.tick_index = 1
	controller.process_commands()
	check(not bool(controller.get_command_result(failed.sequence_id)["accepted"]), "public formation command reports rejection")
	check(bool(Orders.current(unit)["completed"]) and unit["reserved_destination"] == null, "rejected formation leaves a completed order and no reservation")
	var next := Commands.FormationMoveCommand.new(2, ids, Vector2(8.5, 8.5), "LINE", Vector2.RIGHT)
	next.params["queue_order"] = true
	controller.enqueue_command(next, false, 1)
	for tick in range(100): controller.advance_frame(0.05, 1, 2)
	check(Vector2(unit["pos"]).distance_to(Vector2(8.5, 8.5)) < 0.04, "queued formation order physically completes after rejection")
	check(Orders.queued(unit).is_empty() and bool(Orders.current(unit)["completed"]), "next queued order finishes cleanly")
	world.task_coordinator.shutdown()


func test_global_repath_clears_active_planner(native: bool) -> void:
	var world = make_world(native)
	var unit := add_member(world, "land", Vector2(5.5, 8.5))
	check(world.assign_unit_destination(unit, Vector2(10.5, 8.5)), "stalled fixture has a valid initial route")
	var known = world.movement_system.knowledge.planner(world, 1)
	world.pathfinder.find_path(Vector2(2.5, 2.5), Vector2(3.5, 2.5))
	world.set_entity_field(unit, "speed", 0.0)
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	for tick in range(25):
		controller.advance_frame(0.05, 1, 2)
		if int(unit["stuck_ticks"]) == 18: break
	check(int(unit["stuck_ticks"]) == 18, "live movement reaches global recovery")
	check(known.cache_hits == 0 and known.cache.size() == 1, "global recovery recomputes the player's route instead of using a cached result")
	check(world.pathfinder.cache.size() == 1, "player recovery preserves the unrelated physical planner cache")
	world.set_entity_field(unit, "speed", 1.5)
	for tick in range(150): controller.advance_frame(0.05, 1, 2)
	check(Vector2(unit["pos"]).distance_to(Vector2(10.5, 8.5)) < 0.04 and bool(Orders.current(unit)["completed"]), "unit resumes and arrives after recovery")
	world.task_coordinator.shutdown()


func test_legacy_corner_escape(native: bool, domain: String) -> void:
	var world = make_world(native, domain)
	world.navigation_grid.occupy([Vector2i(6, 6)], "static", 100)
	var unit := add_member(world, domain, Vector2(5.5, 5.5))
	world.set_entity_field(unit, "pos", Vector2(5.9, 5.9))
	world.set_entity_field(unit, "previous_pos", unit["pos"])
	check(not world.navigation_grid.is_position_walkable_for(unit["pos"], 0.3, domain, unit["terrain_restriction"]), "legacy corner fixture starts with an overlapping circle")
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	var command := Commands.MoveCommand.new(1, [int(unit["id"])], Vector2(4.5, 4.5))
	controller.enqueue_command(command, false, 1)
	for tick in range(100):
		var before: Vector2 = unit["pos"]
		controller.advance_frame(0.05, 1, 2)
		check(before.distance_to(unit["pos"]) <= 1.5 * 0.05 + 0.036, "legacy corner escape never teleports")
	check(Vector2(unit["pos"]).distance_to(Vector2(4.5, 4.5)) < 0.04, "legacy overlap escapes and reaches its destination (%s %s pos=%s)" % [native, domain, unit["pos"]])
	world.task_coordinator.shutdown()


func test_waypoint_reproducibility(native: bool) -> void:
	var worlds: Array = [make_world(native), make_world(native)]
	var controllers: Array = []
	var members: Array = []
	for world in worlds:
		world.navigation_grid.occupy([Vector2i(8, 8)], "static", 100)
		var unit := add_member(world, "land", Vector2(5.5, 8.5))
		var points: Array[Vector2] = [Vector2(8.5, 8.5), Vector2(10.5, 8.5)]
		check(world.assign_unit_waypoints(unit, points, points[-1]), "deterministic fixture accepts a resolved intermediate waypoint")
		members.append(unit)
		var controller := Controller.new(world)
		controller.set_speed_multiplier(1.0)
		controllers.append(controller)
	var replay := Replay.new()
	for tick in range(160):
		for controller in controllers: controller.advance_frame(0.05, 1, 2)
		check(replay.world_state_hash(worlds[0], controllers[0].tick_index, controllers[0]) == replay.world_state_hash(worlds[1], controllers[1].tick_index, controllers[1]), "identical waypoint routes reproduce the complete simulation state (%s tick=%s)" % [native, tick])
	check(members.all(func(unit): return Vector2(unit["pos"]).distance_to(Vector2(10.5, 8.5)) < 0.04), "both deterministic runs physically reach the destination")
	for world in worlds: world.task_coordinator.shutdown()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)


func test_off_centre_path_endpoints(native: bool, domain: String) -> void:
	for reverse in [false, true]:
		var world = make_world(native, domain)
		world.navigation_grid.occupy([Vector2i(8, 8)], "static", 100)
		var off_centre := Vector2(7.72, 7.85)
		var centred := Vector2(11.5, 7.5)
		var unit := add_member(world, domain, centred if reverse else off_centre)
		var destination := off_centre if reverse else centred
		check(world.assign_unit_destination(unit, Vector2(7.25, 7.25) if reverse else destination, false), "off-centre route is accepted")
		if reverse: world.ensure_navigation_destination(unit, destination)
		var planner = world.movement_system.knowledge.planner(world, 1)
		var previous: Vector2 = unit["pos"]
		for waypoint in unit["path"]:
			check(planner.grid.is_segment_walkable_for(previous, waypoint, unit["footprint_radius"], domain, unit["terrain_restriction"]), "world-space endpoint conversion preserves clearance (%s %s reverse=%s)" % [native, domain, reverse])
			previous = waypoint
		var controller := Controller.new(world)
		controller.set_speed_multiplier(1.0)
		for tick in range(180):
			controller.advance_frame(0.05, 1, 2)
			if unit["task"] == "idle": break
		check(Vector2(unit["pos"]).distance_to(destination) < 0.04, "unit physically reaches the off-centre route endpoint")
		world.shutdown_derived_state()