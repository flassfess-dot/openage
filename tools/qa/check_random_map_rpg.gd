extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const Service := preload("res://scripts/expedition.gd")
const Ready := preload("res://tests/support/match_ready.gd")
const SAVE := "user://qa/random-map-rpg-default-on.json"

var game
var world
var failure := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> bool:
	if ok:
		print("OK ", message)
	else:
		failure = message
		push_error(message)
		quit(1)
	return ok

func until(condition: Callable, ms: int = 30000) -> bool:
	var deadline := Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		game.join_simulation_owner()
		if condition.call(): return true
	return false

func send(command, team: int = 1) -> bool:
	var controller = game.game_controller
	controller.enqueue_command(command, true, team)
	if not await until(func(): return not controller.get_command_result(command.sequence_id).is_empty()): return false
	var result: Dictionary = controller.get_command_result(command.sequence_id)
	if not result.get("accepted", false): print("Command rejected ", result)
	return result.get("accepted", false)

func adjacent(origin: Vector2) -> Vector2:
	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1,1).normalized(), Vector2(-1,1).normalized()]:
		for distance in [2.0, 1.5, 1.0]:
			var position: Vector2 = origin + direction * distance
			if world.pathfinder.is_segment_walkable(origin, position, 0.3): return position
	return Vector2.INF

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	game._unhandled_input(event)

func run() -> void:
	if root.has_node("WindowMode") and DisplayServer.get_name() != "headless":
		root.get_node("WindowMode").apply_settings(false, Vector2i(1280, 720))
	var launcher = load("res://launcher.tscn").instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await process_frame
	launcher.screen_buttons["single_player"].pressed.emit()
	launcher.screen_buttons["random_map"].pressed.emit()
	var toggle: CheckBox = launcher.setting_controls["field_service_enabled"]
	if not check(toggle.button_pressed, "Fresh random map enables RPG without changing the checkbox"): return
	var classic := "--classic-skirmish" in OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless":
		for frame in 3: await process_frame
		var scroll: ScrollContainer = launcher.settings_panel.get_parent()
		scroll.ensure_control_visible(toggle)
		for frame in 2: await process_frame
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture-menu="):
				await RenderingServer.frame_post_draw
				if not check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture-menu=")) == OK, "Captured the default random-map checkbox"): return
		if classic:
			var point := toggle.get_global_rect().get_center()
			for down in [true, false]:
				var click := InputEventMouseButton.new()
				click.position = point
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = down
				root.push_input(click, true)
				await process_frame
			if not check(not toggle.button_pressed, "Clicking the checkbox disables RPG"): return
	elif classic:
		toggle.button_pressed = false
	launcher._select_metadata(launcher.setting_controls["map_type_id"], "grasslands")
	launcher._select_metadata(launcher.setting_controls["map_size_id"], "compact")
	launcher._select_metadata(launcher.setting_controls["resource_preset_id"], "high")
	launcher.setting_controls["seed"].value = 41721
	launcher.start_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_method("load_game_from_path"):
			game = current_scene
			break
	if not check(is_instance_valid(game), "Random-map menu started a match"): return
	if not check(await Ready.wait_for_ready(self, game), "Navigation ready"): return
	world = game.simulation_world
	# The supplied barracks and opponents below have no commands to replay.
	# The release autosave check starts from the finished scenario's checkpoint.
	game.autosave.enabled = false
	game.autosave.shutdown()
	if not check(game.match_path.begins_with("generated://skirmish/") and world.field_service_enabled == (not classic), "Generated match follows the chosen rule " + game.match_path): return
	if not check(world.get_units().all(func(u): return not u.has("service_role")), "Players start with ordinary villagers"): return
	game.game_controller.set_speed_multiplier(3.0)
	var bases: Array = world.get_buildings().filter(func(b): return b.kind == "town_center")
	var human_town: Vector2 = bases.filter(func(b): return b.team == 1)[0].pos
	var enemy_town: Vector2 = bases.filter(func(b): return b.team == 2)[0].pos
	var spot := Vector2.INF
	for y in range(-7, 8):
		for x in range(-7, 8):
			var candidate := human_town + Vector2(x,y)
			if world.can_place_foundation(1, "barracks", candidate):
				spot = candidate
				break
		if spot.is_finite(): break
	if not check(spot.is_finite(), "A barracks fits beside the generated town"): return
	# Only the completed barracks and training opponents are supplied for the encounter.
	var barracks: Dictionary = world.create_building(1, "barracks", spot, true)
	var building_ids: Array[int] = [int(barracks.id)]
	var train = Commands.TrainCommand.new(game.next_local_command_tick(), building_ids, "clubman", 1)
	if not check(await send(train), "Barracks accepted the regular training order"): return
	if not check(await until(func(): return world.get_units().any(func(u): return u.team == 1 and u.kind == "clubman"), 60000), "Barracks trained a clubman"): return
	var soldier: Dictionary = world.get_units().filter(func(u): return u.team == 1 and u.kind == "clubman")[0]
	if not check(soldier.get("service_xp", -1) == (-1 if classic else 0), "Trained soldier follows the experience rule"): return
	var ids: Array[int] = [int(soldier.id)]
	for encounter in 2:
		var position := adjacent(soldier.pos)
		if not check(position.is_finite(), "Walkable ground for encounter"): return
		var foe: Dictionary = world.add_unit(2, "priest", position, false)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		if not check(await send(Commands.AttackCommand.new(game.next_local_command_tick(), ids, int(foe.id))), "Ordinary player attack accepted"): return
		if not check(await until(func(): return foe.hp <= 0, 45000), "Soldier defeated his opponent in combat"): return
		if classic:
			game.player_control_state.replace_or_add(ids, false)
			game.sync_world_state()
			game.refresh_hud_model()
			var hero_controls_hidden: bool = not is_instance_valid(game.expedition_panel) or not game.expedition_panel.visible
			if not check(not soldier.has("service_xp") and world.expedition_field.piles.is_empty() and not game.hud_model.commands.any(func(c): return c.id == "appoint_officer") and hero_controls_hidden, "Classic combat grants no XP or loot and shows no hero controls"): return
			var classic_save := "user://qa/random-map-rpg-default-opt-out.json"
			if not check(game.save_game_to_path(classic_save, "Классическая случайная карта") and game.load_game_from_path(classic_save), "Opted-out random match saved and loaded"): return
			if not check(await Ready.wait_for_ready(self, game) and not game.simulation_world.field_service_enabled and not game.simulation_world.find_unit(ids[0]).has("service_xp"), "Opted-out match keeps classic rules after loading"): return
			print("RANDOM_MAP_CLASSIC_PASSED ", game.match_path)
			quit(0)
			return
		print("Combat ", encounter + 1, " xp=", soldier.get("service_xp"), " piles=", world.expedition_field.piles.size())
		if int(soldier.service_xp) >= Service.VETERAN: break
	if not check(soldier.service_xp == Service.VETERAN, "Soldier earned 36 experience in actual combat"): return
	if not check(world.expedition_field.piles.values().any(func(p): return p.items.has("point") and p.items.has("balm")), "A defeated unit left weapon and balm"): return
	game.player_control_state.replace_or_add(ids, false)
	game.center_view_on_units(ids)
	game.sync_world_state()
	if not check(await until(func(): return game.hud_model.commands.any(func(c): return c.id == "appoint_officer")), "Promotion available on selection panel"): return
	game.issue_unit_action("appoint_officer")
	var dialog = game.get_child(-1) as ConfirmationDialog
	if not check(dialog != null, "Appointment opens from the HUD"): return
	dialog.find_children("*", "LineEdit", true, false)[0].text = "Марк"
	dialog.find_children("*", "OptionButton", true, false)[0].select(0)
	dialog.confirmed.emit()
	dialog.hide()
	if not check(await until(func(): return soldier.get("service_role") == "captain" and game.expedition_panel.visible), "Captain appointed and shown in quick access"): return
	if not check(await until(func(): return game.expedition_panel.nearest_pile() >= 0), "Nearby chest is visible to the selected hero"): return
	key(KEY_F)
	if not check(await until(func(): return soldier.get("service_weapon") == "point" and Service.Inventory.balm_slot(soldier) >= 0), "F collects the chest, equips the weapon and packs the balm"): return
	key(KEY_E)
	if not check(await until(func(): return int(soldier.get("service_guard_until", 0)) > game.game_controller.tick_index), "E applies the captain's shield formation"): return
	key(KEY_J)
	if not check(game.expedition_panel.inventory.visible and game.expedition_panel.slot_buttons.size() == 7, "J opens all seven inventory slots"): return
	if not check(game.expedition_panel.slot_buttons[0].get_theme_constant("outline_size") == 3, "Inventory captions use the high-contrast outline"): return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-path=") and DisplayServer.get_name() != "headless":
			game.center_view_on_units(ids)
			game.queue_redraw()
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			if not check(root.get_texture().get_image().save_png(argument.trim_prefix("--capture-path=")) == OK, "Captured the captain's inventory on this random map"): return
	# Give the opposing player a veteran, then wait for the live skirmish AI to act.
	var ai_pos := Vector2(world.pathfinder.nearest_walkable(Vector2i(enemy_town) + Vector2i(4, 0))) + Vector2(0.5, 0.5)
	var rival: Dictionary = world.add_unit(2, "clubman", ai_pos, false)
	Service.award_personal(world, rival, Service.VETERAN)
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	var appointed: bool = await until(func(): return rival.has("service_role"), 30000)
	print("AI veteran ", rival.get("service_xp"), " role=", rival.get("service_role", ""), " tick=", game.game_controller.tick_index)
	if not check(appointed, "Skirmish AI independently appoints its own veteran"): return
	var hero_id := int(soldier.id)
	var enemy_id := int(rival.id)
	var original_path := String(game.match_path)
	if not check(game.save_game_to_path(SAVE, "Проверка RPG на случайной карте"), "Generated match saved"): return
	if not check(game.load_game_from_path(SAVE), "Generated match loaded"): return
	if not check(await Ready.wait_for_ready(self, game), "Loaded match ready"): return
	var restored = game.simulation_world.find_unit(hero_id)
	if not check(restored != null and game.match_path == original_path and game.simulation_world.field_service_enabled and restored.service_name == "Марк" and restored.service_role == "captain" and restored.service_weapon == "point" and Service.Inventory.balm_slot(restored) >= 0 and game.simulation_world.find_unit(enemy_id).has("service_role"), "Reload preserves generated map, both heroes, XP, weapon and consumable"): return
	print("RANDOM_MAP_RPG_PASSED ", original_path, " ", SAVE)
	quit(0)
