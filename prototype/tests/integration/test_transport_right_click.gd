extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Main := preload("res://main.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for native in [false, true]:
		test_right_click_on_actual_sail(catalog, native)
		test_capacity_cancellation_and_target_loss(catalog, native)
		test_follow_moving_transport(catalog, native)
		test_full_passenger_group(catalog, native)
	test_boarding_replay(catalog)
	for profile in ["islands", "small_islands"]:
		for native in [false, true]:
			test_generated_island_crossing(catalog, profile, native)
	for failure in failures:
		push_error(failure)
	print("Transport right-click and island crossing: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func configured(catalog, native: bool = true, size := Vector2i(32, 32)):
	var world = World.new(size)
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.pathfinder.set_native_enabled(native)
	for team in [1, 2]:
		world.set_population_cap(team, 100)
		world.set_population_housing(team, 100)
	return world


func coast_fixture(catalog, native: bool = true) -> Dictionary:
	var world = configured(catalog, native)
	var terrain: Array[int] = []
	for y in range(32):
		for x in range(32):
			terrain.append(1 if x <= 6 else 2 if x == 7 else 0)
	var levels: Array[int] = []
	levels.resize(33 * 33)
	levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain, "vertex_levels": levels})
	var ship: Dictionary = world.add_unit(1, "transport", Vector2(5.5, 10.5), false)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(16.5, 10.5), false)
	var soldier: Dictionary = world.add_unit(1, "clubman", Vector2(17.5, 12.5), false)
	var sentinel: Dictionary = world.add_unit(2, "clubman", Vector2(29.5, 29.5), false)
	sentinel["stance"] = "passive"
	world.update_fog_of_war()
	return {"world": world, "ship": ship, "worker": worker, "soldier": soldier, "controller": Controller.new(world)}


func test_right_click_on_actual_sail(catalog, native: bool) -> void:
	var fixture := coast_fixture(catalog, native)
	var world = fixture["world"]
	var ship: Dictionary = fixture["ship"]
	ship["hp"] = float(ship["max_hp"]) - 20.0
	var passengers: Array = [fixture["worker"], fixture["soldier"]]
	var game = Main.new()
	game.resource_catalog = catalog
	game.render_world = Main.RenderWorld.new()
	game.simulation_world = world
	game.game_controller = fixture["controller"]
	game.local_player_team = 1
	game.map_size = world.map_size
	game.units = world.get_units().map(func(unit): return unit.duplicate(true))
	game.presentation_snapshot = {"units": game.units, "buildings": [], "resources": []}
	var selected: Array[int] = [int(passengers[0]["id"]), int(passengers[1]["id"])]
	game.player_control_state.replace_or_add(selected, false)
	var point: Variant = isolated_sail_pixel(game, int(ship["id"]))
	check(point is Vector2, "real Transport artwork has a clickable sail outside its hull (native=%s)" % native)
	if point is Vector2:
		game.issue_order(point)
		var commands: Array = game.game_controller.command_queue
		check(commands.size() == 1 and commands[0].command_type() == "board", "main right-click on the sail creates BoardCommand for workers and soldiers")
		game.game_controller.tick_index += 1
		game.game_controller.process_commands()
		check(passengers.all(func(unit): return unit["task"] == "board"), "distant passengers retain an accepted boarding order instead of a range rejection")
		advance_until_embarked(world, ship, 2)
		check(world.get_embarked_units().size() == 2, "both selected units walk to the shore and embark (native=%s state=%s)" % [native, passengers.map(func(unit): return {"task": unit["task"], "pos": unit["pos"], "path": unit["path_status"]})])
		check(world.transport_system.passenger_count(ship) == 2, "transport manifest contains the passengers exactly once")
		check(ship["hp"] == float(ship["max_hp"]) - 20.0, "boarding a damaged Transport does not turn into a repair order")
	game.free()


func isolated_sail_pixel(game, ship_id: int) -> Variant:
	var items: Array = game.current_world_drawables()
	var bodies: Array = items.filter(func(item): return item["kind"] == "unit" and int(item["stable_id"]) == ship_id)
	var parts: Array = items.filter(func(item): return item["kind"] == "unit_part" and int(item["stable_id"]) == ship_id)
	if bodies.is_empty():
		return null
	var project := Callable(game, "world_to_screen")
	for part in parts:
		var info: Dictionary = part["frame_info"]
		var texture: Texture2D = info.get("texture")
		if texture == null:
			continue
		var anchor := PixelScaling.snap_screen(game.world_to_screen(Vector2(part["world_anchor"])))
		anchor += Vector2(info.get("screen_offset", Vector2.ZERO)) * game.view_zoom
		var corner: Vector2 = anchor - Vector2(part["hotspot"]) * game.view_zoom
		for y in range(0, texture.get_height(), 3):
			for x in range(0, texture.get_width(), 3):
				var point: Vector2 = corner + Vector2(x + 0.5, y + 0.5) * game.view_zoom
				if not game.picking_service.texture_hit(point, part, project, game.view_zoom):
					continue
				if game.picking_service.texture_hit(point, bodies[0], project, game.view_zoom) or game.picking_service.footprint_hit(point, "unit", bodies[0]["data"], project, game.view_zoom):
					continue
				return point
	return null


func test_capacity_cancellation_and_target_loss(catalog, native: bool) -> void:
	var fixture := coast_fixture(catalog, native)
	var world = fixture["world"]
	var ship: Dictionary = fixture["ship"]
	var first: Dictionary = fixture["worker"]
	var second: Dictionary = fixture["soldier"]
	ship["components"]["cargo"]["capacity"] = 1
	var controller = fixture["controller"]
	var board = submit_board(controller, first, ship)
	check(bool(controller.get_command_result(board.sequence_id)["accepted"]), "distant boarding command is accepted")
	var overflow = submit_board(controller, second, ship)
	check(controller.get_command_result(overflow.sequence_id)["reason"] == "transport_full" and second["task"] == "idle", "pending passengers reserve seats without mutating rejected units")
	controller.enqueue_command(Commands.StopCommand.new(controller.tick_index, [int(first["id"])]), true, 1)
	controller.process_commands()
	check(first["task"] == "idle" and not first.has("boarding_position"), "Stop cancels a pending boarding order")
	var replacement = submit_board(controller, second, ship)
	check(bool(controller.get_command_result(replacement.sequence_id)["accepted"]), "cancelled passenger releases the reserved seat")
	ship["hp"] = 0.0
	world.update_units(0.05, 1, 2)
	check(second["task"] == "idle" and world.find_unit(int(second["id"])) != null, "loss of the transport cancels boarding without losing the passenger")
	var blocked := coast_fixture(catalog, native)
	blocked["ship"]["pos"] = Vector2(1.5, 10.5)
	var rejected = submit_board(blocked["controller"], blocked["worker"], blocked["ship"])
	check(blocked["controller"].get_command_result(rejected.sequence_id)["reason"] == "boarding_shore_unreachable", "a ship too far from shore cannot teleport passengers across the sea")
	check(blocked["worker"]["task"] == "idle", "unreachable shore leaves the existing order untouched")
	var allied := coast_fixture(catalog, native)
	allied["world"].transfer_entity_ownership(allied["worker"], 2, -1)
	allied["world"].set_alliance(1, 2, true)
	var allied_board = submit_board(allied["controller"], allied["worker"], allied["ship"], 2)
	check(bool(allied["controller"].get_command_result(allied_board.sequence_id)["accepted"]), "allied passenger can start a boarding approach")
	allied["world"].set_alliance(1, 2, false)
	allied["world"].update_units(0.05, 1, 2)
	check(allied["worker"]["task"] == "idle" and allied["world"].get_embarked_units().is_empty(), "revoked alliance cancels a pending approach")


func test_follow_moving_transport(catalog, native: bool) -> void:
	var fixture := coast_fixture(catalog, native)
	var world = fixture["world"]
	var ship: Dictionary = fixture["ship"]
	submit_board(fixture["controller"], fixture["worker"], ship)
	world.assign_command_move([ship], Vector2(5.5, 15.5))
	advance_until_embarked(world, ship, 1)
	check(world.transport_system.passenger_count(ship) == 1, "passenger updates its coastal approach when the Transport moves (native=%s)" % native)


func test_full_passenger_group(catalog, native: bool) -> void:
	var fixture := coast_fixture(catalog, native)
	var world = fixture["world"]
	var ship: Dictionary = fixture["ship"]
	var passengers: Array = [fixture["worker"], fixture["soldier"], world.add_unit(1, "villager", Vector2(18.5, 11.5), false), world.add_unit(1, "clubman", Vector2(19.5, 13.5), false)]
	var ids: Array[int] = []
	for passenger in passengers:
		ids.append(int(passenger["id"]))
	var controller = fixture["controller"]
	var command = Commands.BoardCommand.new(controller.tick_index, ids, int(ship["id"]))
	controller.enqueue_command(command, true, 1)
	controller.process_commands()
	check(bool(controller.get_command_result(command.sequence_id)["accepted"]), "all four passengers can receive one boarding command")
	advance_until_embarked(world, ship, passengers.size(), 1400)
	check(world.transport_system.passenger_count(ship) == passengers.size(), "the complete selection embarks despite competing coastal destinations (native=%s)" % native)


func test_boarding_replay(catalog) -> void:
	var first := coast_fixture(catalog)
	var recorder = first["controller"].start_recording(1337)
	var command = Commands.BoardCommand.new(1, [int(first["worker"]["id"])], int(first["ship"]["id"]))
	first["controller"].enqueue_command(command, true, 1)
	for tick in range(30):
		first["controller"].advance_frame(0.05, 1, 2)
	check(first["worker"]["task"] == "board", "replay fixture captures an approach before boarding completes")
	var second := coast_fixture(catalog)
	check(second["controller"].load_replay(recorder.to_json()), "boarding replay loads")
	check(second["controller"].replay_until_tick(first["controller"].tick_index, 1, 2), "boarding approach reconstructs to the saved tick")
	check(Replay.new().world_state_hash(first["world"], first["controller"].tick_index) == Replay.new().world_state_hash(second["world"], second["controller"].tick_index), "pending boarding state survives replay reconstruction")
	for tick in range(500):
		first["controller"].advance_frame(0.05, 1, 2)
		second["controller"].advance_frame(0.05, 1, 2)
		if first["world"].transport_system.passenger_count(first["ship"]) == 1:
			break
	check(first["world"].transport_system.passenger_count(first["ship"]) == 1 and second["world"].transport_system.passenger_count(second["ship"]) == 1, "both original and restored approaches complete boarding")
	check(Replay.new().world_state_hash(first["world"], first["controller"].tick_index) == Replay.new().world_state_hash(second["world"], second["controller"].tick_index), "reconstructed boarding remains deterministic after embarkation")


func test_generated_island_crossing(catalog, profile: String, native: bool) -> void:
	var settings := Settings.default_settings()
	settings["map_type_id"] = profile
	settings["map_size_id"] = "compact"
	settings["seed"] = 41721
	var built := Settings.build(settings)
	check(bool(built.get("valid", false)), "%s map fixture is playable" % profile)
	if not bool(built.get("valid", false)):
		return
	var world = configured(catalog, native, built["map_data"]["size"])
	Bootstrap.apply(world, built["definition"], built["map_data"])
	var zones: Array = built["map_data"]["naval_start_zones"]
	var home := coast_site(world, zones[0])
	var landing := coast_site(world, zones[1])
	check(not home.is_empty() and not landing.is_empty(), "%s has valid Transport moorings and landing space" % profile)
	if home.is_empty() or landing.is_empty():
		return
	var ship: Dictionary = world.add_unit(1, "transport", home["water"], false)
	var workers: Array = world.get_units().filter(func(unit): return int(unit["team"]) == 1 and world.entity_is_worker(unit))
	var selected: Array = workers.slice(0, 2)
	check(selected.size() == 2, "%s exposes two ordinary starting villagers" % profile)
	var ids: Array[int] = []
	for worker in selected:
		ids.append(int(worker["id"]))
	var controller = Controller.new(world)
	var board = Commands.BoardCommand.new(0, ids, int(ship["id"]))
	controller.enqueue_command(board, true, 1)
	controller.process_commands()
	check(bool(controller.get_command_result(board.sequence_id)["accepted"]), "%s accepts boarding from the initial town: %s ship=%s home=%s landing=%s" % [profile, controller.get_command_result(board.sequence_id), {"pos": ship["pos"], "radius": ship["footprint_radius"]}, home, landing])
	if not bool(controller.get_command_result(board.sequence_id)["accepted"]):
		return
	advance_until_embarked(world, ship, selected.size(), 1800)
	check(world.transport_system.passenger_count(ship) == selected.size(), "%s villagers reach the coast and embark: cargo=%s ship=%s workers=%s" % [profile, ship["components"]["cargo"], ship["pos"], selected.map(func(unit): return {"pos": unit["pos"], "task": unit["task"], "path": unit["path_status"], "radius": unit["footprint_radius"], "reason": unit["components"]["order"]["completion_reason"], "embarked": unit.get("transported_by_id", -1), "diagnostic": unit.get("diagnostic_reason", "")})])
	if world.transport_system.passenger_count(ship) != selected.size():
		for worker in selected:
			if world.find_unit(int(worker["id"])) == null:
				continue
			print("BLOCKED ", {"pos": worker["pos"], "target": worker["target"], "path": worker["path"], "index": worker["path_index"], "stuck": worker["stuck_ticks"], "failed": worker.get("boarding_failed_positions", []), "valid": world.navigation_grid.is_position_walkable_for(worker["pos"], worker["footprint_radius"], worker["movement_domain"], worker["terrain_restriction"]), "neighbors": world.get_units().filter(func(unit): return int(unit["id"]) != int(worker["id"]) and Vector2(unit["pos"]).distance_to(worker["pos"]) < 4.0).map(func(unit): return {"kind": unit["kind"], "pos": unit["pos"], "radius": unit["footprint_radius"]})})
		return
	world.assign_command_move([ship], landing["water"])
	for tick in range(2400):
		advance(world)
		if Vector2(ship["pos"]).distance_to(landing["water"]) < 0.2:
			break
	check(Vector2(ship["pos"]).distance_to(landing["water"]) < 0.2, "%s loaded Transport crosses the sea through fog" % profile)
	var unload = Commands.UnloadCommand.new(controller.tick_index, [int(ship["id"])], landing["land"])
	controller.enqueue_command(unload, true, 1)
	controller.process_commands()
	check(bool(controller.get_command_result(unload.sequence_id)["accepted"]), "%s unloads villagers through the public command" % profile)
	var component: int = world.navigation_grid.surface_component_id(Vector2i(landing["land"]), "land")
	check(selected.all(func(unit): return world.find_unit(int(unit["id"])) != null and world.navigation_grid.surface_component_id(Vector2i(unit["pos"]), "land") == component), "%s passengers land alive on the other island" % profile)
	check(world.transport_system.passenger_count(ship) == 0, "%s clears its cargo after landing" % profile)


func coast_site(world, zone: Dictionary) -> Dictionary:
	var origin := Vector2(zone["water_staging"])
	var component: int = world.navigation_grid.surface_component_id(Vector2i(Vector2(zone["land_staging"])), "land")
	var candidates: Array[Vector2] = []
	for y in range(maxi(0, int(origin.y) - 6), mini(world.map_size.y, int(origin.y) + 7)):
		for x in range(maxi(0, int(origin.x) - 6), mini(world.map_size.x, int(origin.x) + 7)):
			var water := Vector2(x + 0.5, y + 0.5)
			if world.navigation_grid.is_position_walkable_for(water, 0.75, "water"):
				candidates.append(water)
	candidates.sort_custom(func(left, right): return origin.distance_squared_to(left) < origin.distance_squared_to(right))
	for water in candidates:
		for y in range(int(water.y) - 2, int(water.y) + 3):
			for x in range(int(water.x) - 2, int(water.x) + 3):
				var land := Vector2(x + 0.5, y + 0.5)
				if water.distance_to(land) <= 2.25 and world.navigation_grid.surface_component_id(Vector2i(land), "land") == component and world.navigation_grid.is_position_walkable_for(land, 0.3, "land"):
					return {"water": water, "land": land}
	return {}


func submit_board(controller, passenger: Dictionary, ship: Dictionary, issuer: int = 1):
	var command = Commands.BoardCommand.new(controller.tick_index, [int(passenger["id"])], int(ship["id"]))
	controller.enqueue_command(command, true, issuer)
	controller.process_commands()
	return command


func advance_until_embarked(world, ship: Dictionary, count: int, max_ticks: int = 900) -> void:
	for tick in range(max_ticks):
		advance(world)
		if world.transport_system.passenger_count(ship) >= count:
			return


func advance(world) -> void:
	world.update_units(0.05, 1, 2)
	world.rebuild_spatial_index(false)
	world.update_fog_of_war()


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
