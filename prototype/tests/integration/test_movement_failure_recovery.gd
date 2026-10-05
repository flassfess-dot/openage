extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Ai := preload("res://scripts/ai_player.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for native in [false, true]:
		test_legacy_ship_escape(catalog, native)
		test_stopped_worker_recovers(catalog, native)
		test_failed_work_route_is_terminal(catalog, native)
	for failure in failures: push_error(failure)
	print("Movement failure recovery: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func configured(catalog, native: bool):
	var world = World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.pathfinder.set_native_enabled(native)
	return world
func test_legacy_ship_escape(catalog, native: bool) -> void:
	var world = configured(catalog, native)
	var terrain: Array[int] = []
	for y in range(32):
		for x in range(32): terrain.append(1 if x < 7 else 2 if x == 7 else 0)
	var levels: Array[int] = []
	levels.resize(33 * 33)
	levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain, "vertex_levels": levels})
	var ship: Dictionary = world.add_unit(1, "transport", Vector2(6.5, 10.5), false)
	check(world.navigation_grid.is_position_walkable_for(ship["pos"], ship["footprint_radius"], "water", ship["terrain_restriction"]), "new ships have legal hull clearance")
	# Reproduce a centre-only placement from an older saved game.
	ship["pos"] = Vector2(6.5, 10.5)
	ship["previous_pos"] = ship["pos"]
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	check(world.assign_command_move([ship], Vector2(5.5, 16.5)), "legacy shore overlap still has an escape route")
	var moved := false
	for tick in range(250):
		var before := Vector2(ship["pos"])
		world.update_units(0.05, 1, 2)
		var distance := before.distance_to(ship["pos"])
		check(distance <= float(ship["speed"]) * 0.05 + 0.036, "shore escape never teleports")
		moved = moved or distance > 0.001
	check(moved and Vector2(ship["pos"]).distance_to(Vector2(5.5, 16.5)) < 0.2, "old stranded hull retreats and completes its route (native=%s pos=%s reason=%s)" % [native, ship["pos"], ship["diagnostic_reason"]])
	ship["pos"] = Vector2(6.5, 10.5)
	ship["previous_pos"] = ship["pos"]
	var passenger: Dictionary = world.add_unit(1, "villager", Vector2(7.8, 10.5), false)
	check(world.board_units([passenger], ship) == "", "legacy hull can retain cargo")
	world.update_fog_of_war()
	check(world.transport_system.assign_unload_order([ship], Vector2(8.5, 23.5)) == "", "landing order itself can recover legacy shore overlap")
	for tick in range(500): world.update_units(0.05, 1, 2)
	check(world.find_unit(int(passenger["id"])) != null and world.transport_system.passenger_count(ship) == 0, "legacy hull reaches its requested landing without a separate move order")
func test_stopped_worker_recovers(catalog, native: bool) -> void:
	var world = configured(catalog, native)
	var worker: Dictionary = world.add_unit(2, "villager", Vector2(10.5, 10.5), false)
	world.add_unit(1, "clubman", Vector2(28.5, 28.5), false)["stance"] = "passive"
	world.update_fog_of_war()
	var original_speed := float(worker["speed"])
	world.assign_command_move([worker], Vector2(18.5, 10.5))
	worker["speed"] = 0.0
	for tick in range(80): world.update_units(0.05, 1, 2)
	check(worker["task"] == "idle" and worker["diagnostic_reason"] == "stuck_stopped_nearest_valid", "real movement loop detects a stalled order")
	check(worker["path"].is_empty() and worker["target"] == worker["pos"] and worker["reserved_destination"] == null, "stopping releases the complete old route")
	worker["speed"] = original_speed
	var snapshot := Snapshot.with_queries(world, 100, 2, {"compact_entities": true})
	var ai := Ai.new({"team": 2})
	var initial: Array = ai.collect_commands(snapshot, 100).filter(func(command): return int(worker["id"]) in command.unit_ids)
	check(initial.is_empty(), "real stuck observation enters bounded AI backoff")
	var commands: Array = ai.collect_commands(snapshot, 180).filter(func(command): return int(worker["id"]) in command.unit_ids)
	check(commands.size() == 1 and commands[0].command_type() == "move", "noncombat worker gets a local escape command")
	var controller := Controller.new(world)
	controller.tick_index = 180
	controller.set_speed_multiplier(1.0)
	for command in commands: controller.enqueue_command(command, true, 2)
	controller.process_commands()
	var origin := Vector2(worker["pos"])
	for tick in range(100): controller.advance_frame(0.05, 1, 2)
	check(Vector2(worker["pos"]).distance_to(origin) > 0.5 and worker["diagnostic_reason"] != "stuck_stopped_nearest_valid", "worker physically leaves the failed location (native=%s)" % native)
	world.assign_command_move([worker], Vector2(16.5, 10.5))
	world.halt_unit(worker, "stop")
	var stopped_position := Vector2(worker["pos"])
	for tick in range(40): world.update_units(0.05, 1, 2)
	check(worker["pos"] == stopped_position and worker["path"].is_empty(), "Stop cannot keep following an old path in idle state")
func test_failed_work_route_is_terminal(catalog, native: bool) -> void:
	var world = configured(catalog, native)
	var worker: Dictionary = world.add_unit(2, "villager", Vector2(10.5, 10.5), false)
	var barrier: Array[Vector2i] = []
	for y in range(8, 13):
		for x in range(8, 13):
			if x in [8, 12] or y in [8, 12]: barrier.append(Vector2i(x, y))
	world.navigation_grid.occupy(barrier, "static", 777)
	world.update_fog_of_war()
	worker["task"] = "gather"
	check(not world.assign_unit_destination(worker, Vector2(14.5, 10.5)), "enclosed worker has no route to its work destination")
	check(worker["task"] == "idle" and worker["diagnostic_reason"] == "no_path" and worker["path"].is_empty(), "failed work routes complete instead of repeatedly searching while idle")
	var request := int(world.navigation_service.next_request_id)
	for tick in range(60): world.update_units(0.05, 1, 2)
	check(world.navigation_service.next_request_id == request, "terminal failure issues no repeated A* requests")
	check(world.assign_unit_destination(worker, worker["pos"]), "a zero-distance destination is successful arrival, not a path failure")
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
