extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Garrison := preload("res://scripts/tower_garrison.gd")
const Model := preload("res://scripts/hud_view_model.gd")
const Controls := preload("res://scripts/hud_controls.gd")
const Main := preload("res://main.gd")
const Context := preload("res://scripts/context_resolver.gd")
var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	for native in [false, true]:
		test_right_click_capacity_and_hud(catalog, native)
		test_volley(catalog, native)
		test_destruction_during_combat(catalog, native)
	test_restrictions_and_lifecycle(catalog)
	test_blocked_exit_and_cancel(catalog)
	test_checkpoint_and_replay(catalog)
	for failure in failures:
		push_error(failure)
	print("Tower garrison: %d assertions, %d failures" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


func fixture(catalog, native: bool = true) -> Dictionary:
	var world = World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.pathfinder.set_native_enabled(native)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	for team in [1, 2]:
		world.set_population_cap(team, 100)
		world.set_population_housing(team, 100)
	var tower: Dictionary = world.add_building(80, "tower", Vector2(12.5, 12.5), 1)
	var sentinel: Dictionary = world.add_unit(2, "clubman", Vector2(29.5, 29.5), false)
	sentinel["stance"] = "passive"
	world.update_fog_of_war()
	return {"world": world, "tower": tower, "controller": Controller.new(world)}


func submit(controller, command, issuer: int = 1) -> Dictionary:
	controller.enqueue_command(command, true, issuer)
	controller.process_commands()
	return controller.get_command_result(command.sequence_id)


func board(f: Dictionary, units: Array) -> Dictionary:
	var ids: Array[int] = []
	for unit in units:
		ids.append(int(unit["id"]))
	return submit(f["controller"], Commands.BoardCommand.new(0, ids, int(f["tower"]["id"])))


func settle(world, tower: Dictionary, count: int) -> void:
	for tick in range(600):
		world.update_units(0.05, 1, 2)
		if world.transport_system.passenger_count(tower) >= count:
			return
	check(false, "units reach tower and actually enter: %d" % count)


func selected_snapshot(f: Dictionary, observer: int = 1) -> Dictionary:
	return Snapshot.with_queries(f["world"], 0, observer, {"compact_render_entities": true, "always_include_entity_ids": [80], "command_option_entity_ids": [80]})


func test_right_click_capacity_and_hud(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var world = f["world"]
	var tower: Dictionary = f["tower"]
	var units: Array = []
	for index in range(6):
		units.append(world.add_unit(1, "archer", Vector2(6.5, 8.5 + index), false))
	world.update_fog_of_war()
	var population: int = world.get_population(1)
	var game = Main.new()
	game.resource_catalog = catalog
	game.render_world = Main.RenderWorld.new()
	game.simulation_world = world
	game.game_controller = f["controller"]
	game.local_player_team = 1
	game.map_size = world.map_size
	game.units = world.get_units().map(func(unit): return unit.duplicate(true))
	game.presentation_snapshot = {"units": game.units, "buildings": [tower.duplicate(true)], "resources": []}
	var ids: Array[int] = []
	for unit in units:
		ids.append(int(unit["id"]))
	game.player_control_state.replace_or_add(ids, false)
	var click := game.world_to_screen(Vector2(tower["pos"]))
	check(not game.pick_stack_at(click).is_empty(), "tower artwork/footprint is pickable")
	game.issue_order(click)
	check(game.game_controller.command_queue.size() == 1 and game.game_controller.command_queue[0].command_type() == "board", "actual right-click creates a replayable boarding command (native=%s)" % native)
	game.game_controller.tick_index = 1
	game.game_controller.process_commands()
	settle(world, tower, 5)
	check(world.transport_system.passenger_count(tower) == 5, "tower has exactly five occupants from an oversized group")
	check(world.get_embarked_units().size() == 5 and world.get_population(1) == population, "garrison removes occupants from map without releasing population")
	check(units.filter(func(unit): return world.find_unit(int(unit["id"])) != null).size() == 1, "sixth archer remains on the map")
	var view_model := Model.new()
	view_model.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	var before := view_model.build_update(selected_snapshot(f), [80], "RECTANGLE")
	check(before["model"]["garrison"].get("units", []).size() == 5, "selected compact snapshot carries private occupant details to HUD")
	check(before["model"]["garrison"].get("capacity", 0) == 5, "HUD shows five seats")
	var controls := Controls.new()
	controls.configure_icons(catalog.interface_icons)
	controls.configure_interface_skin(catalog.interface_skin, 4)
	controls.set_layout(preload("res://scripts/interface_layout.gd").for_viewport(Vector2(1280, 720)))
	controls.set_view_model(before["model"])
	controls.ungarrison_requested.connect(func(building_id, passenger_id): game.command_actions.issue_ungarrison(game, building_id, passenger_id))
	check(controls.status_panel.garrison_buttons.all(func(button): return button.visible and not button.disabled and button.icon != null), "all five occupant portraits are visible and clickable")
	for button in controls.status_panel.garrison_buttons:
		check(controls.current_layout["production"].encloses(button.get_rect()), "garrison portrait stays inside its HUD area")
	var first_id := int(before["model"]["garrison"]["units"][0]["id"])
	controls.status_panel.garrison_buttons[0].pressed.emit()
	check(game.game_controller.command_queue.size() == 1 and game.game_controller.command_queue[0].passenger_ids == [first_id], "portrait click requests only that occupant")
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(world.find_unit(first_id) != null and world.transport_system.passenger_count(tower) == 4, "portrait command actually releases one archer")
	var after := view_model.build_update(selected_snapshot(f), [80], "RECTANGLE", before["signature"])
	check(after["changed"] and after["model"]["garrison"]["units"].size() == 4, "same selected tower refreshes after unloading")
	var tower_ids: Array[int] = [80]
	game.player_control_state.replace_or_add(tower_ids, false)
	game.presentation_snapshot = selected_snapshot(f)
	game.command_actions.issue_unit_action(game, "ungarrison")
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(world.transport_system.passenger_count(tower) == 0, "unload-all HUD command releases all remaining occupants")
	check(world.get_embarked_units().is_empty() and world.get_population(1) == population, "unload-all preserves population and clears private cargo")
	for unit in units:
		if world.find_unit(int(unit["id"])) != null:
			check(world.navigation_grid.is_position_walkable_for(unit["pos"], float(unit["footprint_radius"]), "land", int(unit["terrain_restriction"])), "released unit stands on walkable ground")
	controls.free()
	game.free()


func fire(world, tower: Dictionary, target: Dictionary) -> void:
	tower["anim"] = 100.0
	tower["animation_events_fired"] = {}
	world.apply_attack_frame_event(tower, target, 1)


func test_volley(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var world = f["world"]
	var tower: Dictionary = f["tower"]
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(18.5, 12.5), false)
	enemy["hp"] = 1000.0
	enemy["max_hp"] = 1000.0
	enemy["stance"] = "passive"
	tower["components"]["combat"]["accuracy"] = 100
	fire(world, tower, enemy)
	check(world.get_projectiles().size() == 1, "empty tower still fires one projectile")
	var initial_hp: float = enemy["hp"]
	world.update_projectiles(10.0, 1)
	var single_damage: float = initial_hp - float(enemy["hp"])
	var infantry: Dictionary = world.add_unit(1, "clubman", Vector2(10.8, 12.5), false)
	check(bool(board(f, [infantry]).get("accepted", false)), "infantry may shelter inside")
	settle(world, tower, 1)
	check(Garrison.extra_arrows(world, tower) == 0, "melee infantry does not increase volley")
	var archers: Array = []
	for index in range(4):
		archers.append(world.add_unit(1, "archer", Vector2(10.8, 11.5 + index * 0.4), false))
	board(f, archers)
	settle(world, tower, 5)
	var extra := Garrison.extra_arrows(world, tower)
	check(extra > 0 and extra <= 4, "ranged garrison increases volley within its cap")
	var hp_before: float = enemy["hp"]
	fire(world, tower, enemy)
	check(world.get_projectiles().size() == 1 + extra, "release frame creates actual additional projectiles")
	check(world.get_projectiles().all(func(projectile): return projectile["source_id"] == 80 and projectile["projectile_unit_id"] == tower["projectile_id"]), "all extra arrows use tower weapon and attribution")
	var origins: Array = []
	for projectile in world.get_projectiles():
		if projectile["origin"] not in origins:
			origins.append(projectile["origin"])
	check(origins.size() == 1 + extra, "volley arrows have distinct launch points")
	world.update_projectiles(10.0, 1)
	check(is_equal_approx(hp_before - float(enemy["hp"]), single_damage * (1 + extra)), "extra projectiles deal actual per-arrow damage")
	var previous := extra
	archers[0]["attack_damage"] = 100.0
	check(Garrison.extra_arrows(world, tower) >= previous and Garrison.extra_arrows(world, tower) == 4, "stronger archer increases firepower but cannot exceed four additional arrows")


func test_restrictions_and_lifecycle(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var tower: Dictionary = f["tower"]
	for kind in ["cavalry", "chariot_archer", "stone_thrower", "ballista", "elephant"]:
		var unit: Dictionary = world.add_unit(1, kind, Vector2(6.5, 6.5), false)
		check(not bool(board(f, [unit]).get("accepted", false)), "%s cannot enter tower" % kind)
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(10.8, 12.5), false)
	tower["state"] = "foundation"
	check(not bool(board(f, [archer]).get("accepted", false)), "unfinished tower cannot receive a garrison")
	tower["state"] = "complete"
	board(f, [archer])
	settle(world, tower, 1)
	var observer: Dictionary = world.add_unit(2, "clubman", Vector2(16.5, 12.5), false)
	observer["stance"] = "passive"
	world.update_fog_of_war()
	var foreign := Snapshot.with_queries(world, 0, 2, {"always_include_entity_ids": [80]})
	check(foreign.get("buildings", []).any(func(entity): return int(entity["id"]) == 80), "enemy observer can see the tower itself")
	check(foreign.get("buildings", []).all(func(entity): return not entity.has("garrison")), "enemy snapshot never reveals occupants")
	var population: int = world.get_population(1)
	check(world.transfer_entity_ownership(tower, 2, 999), "tower conversion succeeds")
	check(world.find_unit(int(archer["id"])) != null and int(archer["team"]) == 1 and world.get_population(1) == population, "conversion ejects original owner's occupant without changing population")
	var casualty := fixture(catalog)
	var soldier: Dictionary = casualty["world"].add_unit(1, "archer", Vector2(10.8, 12.5), false)
	board(casualty, [soldier])
	settle(casualty["world"], casualty["tower"], 1)
	casualty["tower"]["hp"] = 0.0
	casualty["world"].begin_entity_death(casualty["tower"])
	check(casualty["world"].find_unit(int(soldier["id"])) != null and float(soldier["hp"]) > 0.0, "destroyed tower ejects surviving occupant to free ground")
	check(casualty["world"].get_embarked_units().is_empty(), "destroyed tower leaves no orphaned garrison")
	var resolver := Context.resolve([archer], tower, Vector2.ZERO, 1, [1])
	check(resolver.get("type") == "attack", "right-clicking an enemy tower remains an attack")


func test_checkpoint_and_replay(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(10.8, 12.5), false)
	board(f, [archer])
	settle(world, f["tower"], 1)
	var packed := Checkpoint.pack(Checkpoint.capture(world, f["controller"], {}, {"size": world.map_size}))
	var restored := fixture(catalog)
	check(Checkpoint.restore(Checkpoint.unpack(packed), restored["world"], restored["controller"]), "binary checkpoint restores a garrisoned tower")
	var loaded_tower: Dictionary = restored["world"].find_building(80)
	check(restored["world"].get_embarked_units().size() == 1 and loaded_tower["components"]["cargo"]["passenger_ids"] == [int(archer["id"])], "checkpoint restores manifest and hidden occupants together")
	var hasher := Replay.new()
	check(hasher.world_state_hash(world, 0, f["controller"]) == hasher.world_state_hash(restored["world"], 0, restored["controller"]), "checkpoint retains exact authoritative hash")
	var result := submit(restored["controller"], Commands.UnloadCommand.new(0, [80], Vector2(12.5, 12.5), [int(archer["id"])]))
	check(bool(result.get("accepted", false)) and restored["world"].find_unit(int(archer["id"])) != null, "loaded occupant can actually disembark")
	var recording := fixture(catalog)
	var passenger: Dictionary = recording["world"].add_unit(1, "archer", Vector2(6.5, 12.5), false)
	var controller = recording["controller"]
	controller.set_speed_multiplier(1.0)
	var replay = controller.start_recording(551, false)
	controller.enqueue_command(Commands.BoardCommand.new(1, [int(passenger["id"])], 80), true, 1)
	for frame in range(100):
		controller.advance_frame(0.05, 1, 2)
	check(recording["world"].get_embarked_units().size() == 1, "recording scenario actually garrisons the archer")
	controller.enqueue_command(Commands.UnloadCommand.new(controller.tick_index + 1, [80], Vector2(12.5, 12.5), [int(passenger["id"])]), true, 1)
	for frame in range(10):
		controller.advance_frame(0.05, 1, 2)
	var playback := fixture(catalog)
	playback["world"].add_unit(1, "archer", Vector2(6.5, 12.5), false)
	playback["controller"].set_speed_multiplier(1.0)
	check(playback["controller"].load_replay(replay.to_json()) and playback["controller"].replay_until_tick(controller.tick_index, 1, 2), "tower boarding/unloading commands replay through fixed ticks")
	check(hasher.world_state_hash(recording["world"], controller.tick_index, controller) == hasher.world_state_hash(playback["world"], controller.tick_index, playback["controller"]), "replayed garrison scenario has identical authoritative state")


func test_blocked_exit_and_cancel(catalog) -> void:
	var f := fixture(catalog)
	var world = f["world"]
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(10.8, 12.5), false)
	board(f, [archer])
	settle(world, f["tower"], 1)
	world.apply_unit_upgrade_to_entity(f["tower"], 69)
	check(world.transport_system.passenger_count(f["tower"]) == 1 and int(f["tower"]["source_unit_id"]) == 69, "upgrading the tower preserves its garrison")
	var occupied: Array = []
	for y in range(9, 16):
		for x in range(9, 16):
			occupied.append(Vector2i(x, y))
	world.navigation_grid.occupy(occupied, "obstacle", 99001)
	var result := submit(f["controller"], Commands.UnloadCommand.new(0, [80], Vector2(12.5, 12.5)))
	check(not bool(result.get("accepted", false)) and result.get("reason") == "landing_blocked", "blocked exit rejects unloading")
	check(world.get_embarked_units().size() == 1 and world.find_unit(int(archer["id"])) == null, "blocked exit keeps occupant safe and does not duplicate or teleport it")
	archer["attack_damage"] = 100.0
	check(Garrison.extra_arrows(world, f["tower"]) > 0, "blocked-exit fixture contains an effective ranged garrison")
	check(world.transfer_entity_ownership(f["tower"], 2, 999), "blocked tower can change owner")
	check(Garrison.extra_arrows(world, f["tower"]) == 0 and int(archer["team"]) == 1, "trapped hostile occupant does not strengthen the captured tower")
	world.transfer_entity_ownership(f["tower"], 1, 999)
	world.navigation_grid.release_occupant(occupied, "obstacle", 99001)
	result = submit(f["controller"], Commands.UnloadCommand.new(0, [80], Vector2(12.5, 12.5)))
	check(bool(result.get("accepted", false)) and world.find_unit(int(archer["id"])) != null, "unloading succeeds after the exit becomes free")
	var distant: Dictionary = world.add_unit(1, "archer", Vector2(4.5, 12.5), false)
	check(bool(board(f, [distant]).get("accepted", false)), "distant archer receives approach order")
	submit(f["controller"], Commands.StopCommand.new(0, [int(distant["id"])]))
	for tick in range(160):
		world.update_units(0.05, 1, 2)
	check(world.transport_system.passenger_count(f["tower"]) == 0 and world.find_unit(int(distant["id"])) != null, "new manual order cancels pending garrison approach")
	check(bool(board(f, [distant]).get("accepted", false)), "cancelled unit can receive another approach order")
	f["tower"]["hp"] = 0.0
	world.begin_entity_death(f["tower"])
	for tick in range(4):
		world.update_units(0.05, 1, 2)
	check(distant["task"] == "idle" and world.find_unit(int(distant["id"])) != null, "losing the destination tower safely cancels approach")


func test_destruction_during_combat(catalog, native: bool) -> void:
	var f := fixture(catalog, native)
	var world = f["world"]
	var archer: Dictionary = world.add_unit(1, "archer", Vector2(10.8, 12.5), false)
	board(f, [archer])
	settle(world, f["tower"], 1)
	f["tower"]["hp"] = 1.0
	var attacker: Dictionary = world.add_unit(2, "clubman", Vector2(14.0, 12.5), false)
	var attack = Commands.AttackCommand.new(0, [int(attacker["id"])], 80)
	check(bool(submit(f["controller"], attack, 2).get("accepted", false)), "melee attacker receives a normal tower attack command")
	for tick in range(240):
		world.update_units(0.05, 1, 2)
		if float(f["tower"]["hp"]) <= 0.0:
			break
	check(float(f["tower"]["hp"]) <= 0.0 and world.get_embarked_units().is_empty() and world.find_unit(int(archer["id"])) != null, "combat destruction safely evacuates during the active-unit loop (native=%s)" % native)


func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
