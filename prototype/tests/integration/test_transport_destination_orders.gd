extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Main := preload("res://main.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for native in [false, true]:
		test_large_selection(catalog, native)
		test_targeted_landing(catalog, native)
		test_queued_and_cancelled_landing(catalog, native)
		test_multiple_transports(catalog, native)
	for failure in failures: push_error(failure)
	print("Transport destination orders: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func fixture(catalog, native: bool) -> Dictionary:
	var world = World.new(Vector2i(48, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.pathfinder.set_native_enabled(native)
	world.set_population_cap(1, 500)
	world.set_population_housing(1, 500)
	var terrain: Array[int] = []
	for y in range(32):
		for x in range(48): terrain.append(1 if x < 7 else 2 if x == 7 else 0)
	var levels: Array[int] = []
	levels.resize(49 * 33)
	levels.fill(0)
	var map := {"size": Vector2i(48, 32), "terrain_ids": terrain, "vertex_levels": levels}
	world.configure_map_data(map)
	var ship: Dictionary = world.add_unit(1, "transport", Vector2(6, 5.5), false)
	world.add_unit(2, "clubman", Vector2(46, 30), false)["stance"] = "passive"
	world.update_fog_of_war()
	var controller := Controller.new(world)
	controller.set_speed_multiplier(1.0)
	return {"world": world, "ship": ship, "controller": controller, "map": map}
func submit(f: Dictionary, command):
	f["controller"].enqueue_command(command, true, 1)
	f["controller"].process_commands()
	return f["controller"].get_command_result(command.sequence_id)
func test_large_selection(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var ship: Dictionary = f["ship"]
	var world = f["world"]
	var passengers: Array = []
	var ids: Array[int] = []
	for index in range(64):
		var unit: Dictionary = world.add_unit(1, "villager", Vector2(10.5 + index % 8, 3.5 + index / 8), false)
		passengers.append(unit)
		ids.append(int(unit["id"]))
	check(bool(submit(f, Commands.BoardCommand.new(0, ids, int(ship["id"])))["accepted"]), "64 selected passengers accepted (native=%s)" % native)
	check(passengers.all(func(unit): return unit["task"] == "board"), "every selected passenger starts the approach")
	for tick in range(900): world.update_units(0.05, 1, 2)
	check(world.transport_system.passenger_count(ship) == 4, "capacity remains four (native=%s)" % native)
	check(world.get_embarked_units().size() == 4 and world.get_units().filter(func(unit): return int(unit["team"]) == 1).size() == 61, "all 64 passengers survive overflow")
	var waiting: Array = passengers.filter(func(unit): return world.find_unit(int(unit["id"])) != null)
	check(waiting.any(func(unit): return unit["diagnostic_reason"] == "waiting_for_transport_space"), "overflow waits at the boarding point")
	var original: Array = ship["components"]["cargo"]["passenger_ids"].duplicate()
	check(world.unload_transports([ship], Vector2(8.5, 5.5)) == "", "first boatload can unload")
	for tick in range(100): world.update_units(0.05, 1, 2)
	check(world.transport_system.passenger_count(ship) > 0, "waiting passengers use newly available seats")
	check(original.all(func(id): return world.find_unit(int(id)) != null), "first boatload is not automatically reboarded")
func loaded(f: Dictionary) -> Dictionary:
	var unit: Dictionary = f["world"].add_unit(1, "villager", Vector2(7.5, 5.5), false)
	check(f["world"].board_units([unit], f["ship"]) == "", "fixture boards a real passenger")
	return unit
func test_targeted_landing(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var passenger := loaded(f)
	var ship: Dictionary = f["ship"]
	var game = Main.new()
	game.simulation_world = f["world"]
	game.game_controller = f["controller"]
	game.map_size = f["world"].map_size
	game.local_player_team = 1
	game.view_offset = Vector2(400, 40)
	game.units = f["world"].get_units().map(func(unit): return unit.duplicate(true))
	var ids: Array[int] = [int(ship["id"])]
	game.player_control_state.replace_or_add(ids, false)
	var event := InputEventKey.new()
	event.keycode = KEY_U
	event.pressed = true
	game._unhandled_input(event)
	check(game.pending_target_command == "unload" and game.game_controller.command_queue.is_empty(), "U chooses a destination before issuing the order")
	check(game.cancel_pending_targeting(), "Esc/cancel abandons targeting without changing cargo")
	game.issue_unload_at_pointer(true)
	game.commit_pending_target(game.world_to_screen(Vector2(8.5, 24.5)))
	check(bool(game.game_controller.command_queue[0].params.get("queue_order", false)), "Shift-U retains its queue intent until the destination click")
	game.game_controller.command_queue.clear()
	game.issue_unload_at_pointer()
	game.commit_pending_target(game.world_to_screen(Vector2(8.5, 24.5)), true)
	check(bool(game.game_controller.command_queue[0].params.get("queue_order", false)), "Shift on the destination click queues unloading")
	game.game_controller.command_queue.clear()
	game.issue_unit_action("unload")
	check(game.pending_target_command == "unload", "HUD button enters the same landing mode")
	var target := Vector2(8.5, 24.5)
	game.commit_pending_target(game.world_to_screen(target))
	check(game.pending_target_command.is_empty() and game.game_controller.command_queue.size() == 1, "click creates exactly one landing order")
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(ship["task"] == "unload" and ship["unload_target"] == target, "distant beach retains the landing point")
	for tick in range(15): game.game_controller.advance_frame(0.05, 1, 2)
	var checkpoint := Checkpoint.capture(f["world"], game.game_controller, {}, f["map"])
	var restored = fixture(catalog, native)
	check(Checkpoint.restore(Checkpoint.unpack(Checkpoint.pack(checkpoint)), restored["world"], restored["controller"]), "pending sea route restores from checkpoint")
	var replay := Replay.new()
	check(replay.world_state_hash(f["world"], game.game_controller.tick_index, game.game_controller) == replay.world_state_hash(restored["world"], restored["controller"].tick_index, restored["controller"]), "landing checkpoint preserves exact state")
	for tick in range(900):
		game.game_controller.advance_frame(0.05, 1, 2)
		restored["controller"].advance_frame(0.05, 1, 2)
		if f["world"].transport_system.passenger_count(ship) == 0: break
	check(f["world"].find_unit(int(passenger["id"])) != null and f["world"].transport_system.passenger_count(ship) == 0, "ship approaches and unloads automatically (native=%s state=%s)" % [native, [ship["task"], ship["pos"], ship["target"], ship["destination"], ship["path"], ship["stuck_ticks"], ship.get("navigation_progress"), ship["diagnostic_reason"]]])
	check(Vector2(passenger["pos"]).distance_to(target) < 4.6, "passenger lands at the requested beach")
	var expected := replay.world_snapshot(f["world"], game.game_controller.tick_index, game.game_controller)
	var actual := replay.world_snapshot(restored["world"], restored["controller"].tick_index, restored["controller"])
	if expected != actual:
		FileAccess.open("res://qa/landing-expected-%s.json" % native, FileAccess.WRITE).store_string(JSON.stringify(expected))
		FileAccess.open("res://qa/landing-actual-%s.json" % native, FileAccess.WRITE).store_string(JSON.stringify(actual))
	check(expected == actual, "restored landing continues identically")
	game.free()
func test_queued_and_cancelled_landing(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var passenger := loaded(f)
	var ship: Dictionary = f["ship"]
	submit(f, Commands.MoveCommand.new(0, [int(ship["id"])], Vector2(5.5, 13.5)))
	var unload = Commands.UnloadCommand.new(0, [int(ship["id"])], Vector2(8.5, 23.5))
	unload.params["queue_order"] = true
	check(bool(submit(f, unload)["accepted"]) and ship["task"] == "move", "Shift landing waits behind the active sailing order")
	for tick in range(1000):
		f["controller"].advance_frame(0.05, 1, 2)
		if f["world"].transport_system.passenger_count(ship) == 0: break
	check(f["world"].find_unit(int(passenger["id"])) != null, "queued landing completes")
	f = fixture(catalog, native)
	passenger = loaded(f)
	ship = f["ship"]
	submit(f, Commands.UnloadCommand.new(0, [int(ship["id"])], Vector2(8.5, 24.5)))
	submit(f, Commands.StopCommand.new(0, [int(ship["id"])]))
	check(ship["task"] == "idle" and not ship.has("unload_target") and f["world"].transport_system.passenger_count(ship) == 1, "Stop clears pending landing while preserving passengers")
	check(not bool(submit(f, Commands.UnloadCommand.new(0, [int(ship["id"])], Vector2(30.5, 24.5)))["accepted"]), "inland point with no reachable mooring is rejected safely")
	check(f["world"].transport_system.passenger_count(ship) == 1, "invalid coast preserves cargo")
func test_multiple_transports(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var world = f["world"]
	var ships: Array = [f["ship"], world.add_unit(1, "transport", Vector2(6, 9.5), false)]
	var passengers: Array = []
	var ids: Array[int] = []
	for ship in ships:
		ids.append(int(ship["id"]))
		var cargo: Array = []
		for index in range(4):
			var passenger: Dictionary = world.add_unit(1, "villager", Vector2(7.5, ship["pos"].y), false)
			cargo.append(passenger)
			passengers.append(passenger)
		check(world.board_units(cargo, ship) == "", "each transport starts with full cargo")
	world.update_fog_of_war()
	check(bool(submit(f, Commands.UnloadCommand.new(0, ids, Vector2(8.5, 24.5)))["accepted"]), "a group of transports accepts one landing destination")
	check(Vector2(ships[0].get("unload_approach", Vector2.ZERO)).distance_to(Vector2(ships[1].get("unload_approach", Vector2.ZERO))) >= 1.52, "transports receive separate mooring space")
	for tick in range(1000): world.update_units(0.05, 1, 2)
	check(ships.all(func(ship): return world.transport_system.passenger_count(ship) == 0), "every transport reaches its mooring and unloads (native=%s states=%s)" % [native, ships.map(func(ship): return [ship["task"], ship["pos"], ship["diagnostic_reason"]])])
	check(passengers.all(func(unit): return world.find_unit(int(unit["id"])) != null), "all passengers of the transport group are active after landing")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
