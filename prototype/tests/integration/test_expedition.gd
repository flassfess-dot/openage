extends SceneTree

const Service := preload("res://scripts/expedition.gd")
const Commands := preload("res://scripts/commands.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Ready := preload("res://tests/support/match_ready.gd")
var failed := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		push_error(message)
		failed += 1

func order(game, id: int, action: String, team := 1, details: Dictionary = {}) -> Dictionary:
	var controller = game.game_controller
	var command := Commands.ServiceCommand.new(controller.tick_index, [id], action, "Луций", details)
	controller.enqueue_command(command, true, team)
	controller.process_commands()
	return controller.get_command_result(command.sequence_id)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://data/matches/expedition_outpost.json"
	root.add_child(game)
	current_scene = game
	if not await Ready.wait_for_ready(self, game):
		quit(1)
		return
	check(game.scenario_overlay.briefing_layer.visible, "chapter opens with briefing")
	await capture("briefing")
	var opening_save := "user://qa/expedition-before-briefing.json"
	check(game.save_game_to_path(opening_save) and game.load_game_from_path(opening_save), "opening briefing round trip")
	if not await Ready.wait_for_ready(self, game):
		quit(1)
		return
	game.set_process(false)
	check(game.scenario_overlay.briefing_layer.visible, "an unread briefing stays open on load")
	game.scenario_overlay._dismiss_briefing()
	game.game_controller.set_paused(true)
	var world = game.simulation_world
	check(Service.enabled(world), "expedition bootstraps opt-in rules")
	var archer: Dictionary = world.get_units().filter(func(u): return u.team == 1 and u.kind == "archer")[0]
	var foe: Dictionary = world.get_units().filter(func(u): return u.team == 2 and u.kind == "clubman")[0]
	var id := int(archer.id)
	var selected: Array[int] = [id]
	check(archer.has("service_xp") and foe.has("service_xp"), "both sides enrolled")
	check(not order(game, id, "scout").accepted, "inexperienced officer cannot promote")
	world.combat_system._apply_impact_damage(foe, 16, {"team":1,"entity_id":id}, -1, 1)
	check(archer.service_xp == 16000, "non-lethal contribution earns experience")
	var friendly: Dictionary = world.get_units().filter(func(u): return u.team == 1 and u.kind == "swordsman")[0]
	world.combat_system._apply_impact_damage(friendly, 2, {"team":1,"entity_id":id}, -1, 1)
	check(archer.service_xp == 16000, "friendly fire does not award XP")
	var priest: Dictionary = world.get_units().filter(func(u): return u.team == 1 and u.kind == "priest")[0]
	var previous_xp := int(priest.service_xp)
	check(priest.get("service_role") == "medic" and Service.Inventory.pack(priest)[0].count == 2, "new campaign starts with a playable field medic and supplies")
	world.combat_system._apply_impact_damage(friendly, 8, {"team":2,"entity_id":int(foe.id)}, -1, 1)
	check(world.healing_system.begin(priest, friendly) == "", "priest starts healing battle wounds")
	world.healing_system.advance_healing(priest, friendly, 10)
	check(priest.service_xp == previous_xp + 8000, "only the hostile eight points count towards medical service")
	world.combat_system._apply_impact_damage(foe, 9999, {"team":1,"entity_id":id}, -1, 1)
	if int(archer.service_xp) < Service.VETERAN:
		var target: Dictionary = world.get_units().filter(func(u): return u.team == 2 and u.hp > 0)[0]
		world.combat_system._apply_impact_damage(target, 16, {"team":1,"entity_id":id}, -1, 1)
	check(archer.service_xp == Service.VETERAN, "capped veteran")
	check(world.expedition_field.piles.size() == 1 and world.expedition_field.piles[1].items == ["point","balm"], "first hostile casualty leaves guaranteed field loot")
	game.player_control_state.replace_or_add(selected, false)
	game.sync_world_state()
	game.refresh_hud_model()
	check(game.hud_model.commands.any(func(c): return c.id == "appoint_officer"), "real HUD offers promotion")
	check(not order(game, id, "scout", 2).accepted, "cannot promote enemy")
	var vision := float(archer.components.vision.range)
	game.issue_unit_action("appoint_officer")
	var appointment := game.get_child(-1) as ConfirmationDialog
	if appointment == null:
		check(false, "HUD opens appointment dialog")
		quit(1)
		return
	var name_input: LineEdit = appointment.find_children("*", "LineEdit", true, false)[0]
	var role_input: OptionButton = appointment.find_children("*", "OptionButton", true, false)[0]
	name_input.text = "Луций"
	role_input.select(1)
	appointment.confirmed.emit()
	appointment.hide()
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(archer.has("service_name"), "appointment from dialog reaches controller")
	check(archer.service_name == "Луций" and is_equal_approx(archer.components.vision.range, vision + 2), "named scout gets sight")
	game.sync_world_state()
	game.refresh_hud_model()
	check(game.hud_controls.status_panel.name_label.text == "Луций" and game.hud_controls.status_panel.service_badge.visible, "named officer and insignia in HUD")
	game.current_world_drawables()
	var scout_body: Dictionary = game.expedition_actor_items.get(id, {})
	check(is_equal_approx(float(scout_body.get("frame_info", {}).get("figure_scale", 1.0)), 1.10), "appointment immediately enlarges the scout on the field")
	await capture("officer")
	# Select the coffer through the same screen-position/context order as the mouse.
	var pile: Dictionary = world.expedition_field.piles[1]
	world.set_entity_field(archer, "pos", Vector2(pile.pos) + Vector2(-1, 0))
	world.update_fog_of_war()
	game.sync_world_state()
	game.refresh_hud_model()
	game.issue_order(game.world_to_screen(pile.pos))
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(archer.get("service_weapon") == "point" and Service.Inventory.balm_slot(archer) == 3 and world.expedition_field.piles.is_empty(), "context pickup equips the blade and stows the balm")
	game.sync_world_state()
	game.refresh_hud_model()
	var bag_key := InputEventKey.new()
	bag_key.pressed = true
	bag_key.keycode = KEY_J
	game._unhandled_input(bag_key)
	var panel = game.expedition_panel
	check(panel.inventory.visible and panel.slot_buttons.size() == 7, "inventory hotkey opens equipped and packed slots")
	panel.slot_buttons[0].pressed.emit()
	panel.primary.pressed.emit()
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(archer.get("service_weapon", "") == "" and Service.Inventory.at(archer, 4).get("item") == "point", "HUD unequips into the first free pack slot")
	game.sync_world_state()
	game.refresh_hud_model()
	panel.slot_buttons[4].pressed.emit()
	panel.primary.pressed.emit()
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(archer.get("service_weapon") == "point", "HUD re-equips from selected pack slot")
	var codec := Replay.new()
	var cmd := Commands.ServiceCommand.new(5, selected, "scout", "Луций")
	cmd.assign_envelope(1, 1)
	codec.record_command(cmd)
	var decoded = codec.command_from_record(codec.command_records[0])
	check(decoded.params == cmd.params and decoded.unit_ids == cmd.unit_ids, "replay reproduces command parameters")
	check(not order(game, id, "search").accepted, "cannot loot temple remotely")
	var shrine: Dictionary = world.get_buildings().filter(func(b): return b.get("expedition_cache") == "shield")[0]
	var shrine_edge := Vector2(shrine.pos) + Vector2(2.5,0)
	world.set_entity_fields(archer, {"pos":shrine_edge, "previous_pos":shrine_edge})
	world.update_fog_of_war()
	check(order(game, id, "search").accepted and archer.service_item == "shield", "officer claims item once")
	check(not order(game, id, "search").accepted, "cannot duplicate treasure")
	game.center_view_on_world(archer.pos)
	game.sync_world_state()
	game.refresh_hud_model()
	panel.select_slot(1)
	game.queue_redraw()
	await capture("inventory")
	var tower: Dictionary = world.get_buildings().filter(func(b): return b.kind == "tower")[0]
	world.set_entity_field(archer, "pos", tower.pos)
	check(world.board_units([archer], tower) == "", "officer boards garrison")
	check(Service.survivors(world, 1).any(func(row): return row.id == id), "embarked veterans selectable")
	world.expedition_field.place(Vector2(11, 19), ["incense"])
	var path := "user://qa/expedition-test-save.json"
	check(game.save_game_to_path(path), "save expedition")
	check(game.load_game_from_path(path), "load expedition")
	check(game.scenario_overlay.briefing_dismissed and not game.scenario_overlay.is_blocking(), "resuming a chapter keeps its read briefing closed")
	world = game.simulation_world
	var carried: Dictionary = world.transport_system.embarked_units[id]
	check(Service.enabled(world) and carried.service_name == "Луций" and carried.service_item == "shield" and carried.get("service_weapon") == "point" and Service.Inventory.balm_slot(carried) == 3, "entire equipped and packed kit survives loading while embarked")
	check(world.expedition_field.piles.size() == 1 and world.expedition_field.hero_ids.has(id), "save restores ground loot and embarked hero roster")
	# Finish via the public surrender command; use the actual result UI to
	# transfer the garrisoned survivor into a freshly bootstrapped chapter.
	var resign := Commands.ResignCommand.new(game.game_controller.tick_index)
	game.game_controller.enqueue_command(resign, true, 2)
	game.game_controller.process_commands()
	world.check_battle_state(1, 2, 0.05)
	game.game_controller.tick_index += 1
	game.sync_world_state()
	check(game.scenario_overlay.expedition_button.is_visible_in_tree(), "victory unlocks next chapter: %s / %s / %s" % [world.get_victory_result(), game.presentation_snapshot.get("match_result"), game.scenario_overlay.presentation_model])
	game.scenario_overlay.expedition_button.pressed.emit()
	var dialog := game.get_child(-1) as ConfirmationDialog
	if dialog == null:
		check(false, "survivor selection dialog opens")
	else:
		await capture("survivors")
		dialog.confirmed.emit()
		await process_frame
		await process_frame
		var next = current_scene
		if next == null or next.match_definition.get("id") != "expedition_coast":
			check(false, "next chapter starts")
		else:
			await Ready.wait_for_ready(self, next)
			var roster := Service.survivors(next.simulation_world, 1)
			var scouts := roster.filter(func(row): return row.name == "Луций")
			check(roster.size() == 2 and scouts.size() == 1 and scouts[0].item == "shield" and scouts[0].weapon == "point" and scouts[0].pack[0].item == "balm", "selected scout and medic cross chapters with their equipment exactly once")
			if scouts.is_empty():
				quit(1)
				return
			next.set_process(false)
			var next_world = next.simulation_world
			var veteran = next_world.find_unit(scouts[0].id)
			var chart_shrine: Dictionary = next_world.get_buildings().filter(func(b): return b.get("expedition_cache") == "chart")[0]
			next_world.set_entity_field(veteran, "pos", chart_shrine.pos + Vector2(2.5, 0))
			next_world.update_fog_of_war()
			check(order(next, veteran.id, "search").accepted and veteran.service_item == "shield", "read map while carrying shield")
			check(next_world.get_fog_of_war().state_at_world(1, Vector2(32,25)) == 1, "chart reveals terrain but not live vision")
			var ally: Dictionary = next_world.get_units().filter(func(u): return u.team == 1 and u.kind == "swordsman")[0]
			Service.award(next_world, ally, Service.VETERAN)
			check(not order(next, ally.id, "scout").accepted, "only one active hero of each role")
			check(order(next, ally.id, "captain").accepted, "different roles coexist")
			check(next_world.transfer_entity_ownership(veteran, 2), "scout changes allegiance")
			check(veteran.service_xp == Service.VETERAN and not veteran.has("service_role") and not veteran.has("service_item"), "conversion removes office and item but preserves rank")
			check(next_world.expedition_field.piles.values().any(func(p): return "point" in p.items and "shield" in p.items), "conversion drops equipment on the ground")
			var partner: Dictionary = next_world.get_units().filter(func(u): return u.team == 1 and u.kind == "archer")[0]
			var ids: Array[int] = [int(ally.id), int(partner.id)]
			var march := Commands.FormationMoveCommand.new(next.game_controller.tick_index, ids, Vector2(16,18), "LINE")
			next.game_controller.enqueue_command(march, true, 1)
			next.game_controller.process_commands()
			check(order(next, ally.id, "rally").accepted, "captain rallies actual formation")
	print("Expedition gameplay, checkpoint and chapter transfer: %d failures" % failed)
	quit(1 if failed else 0)

func capture(label: String) -> void:
	if "--capture-expedition" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless": return
	var game = current_scene
	var restore_process: bool = game.is_processing()
	var paused: bool = game.game_controller.paused
	game.game_controller.set_paused(true)
	root.get_node("WindowMode").apply_settings(false, Vector2i(1280,720))
	game.set_process(true)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://qa/expedition" if OS.has_feature("editor") else "user://qa/expedition"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory.path_join(label + ".png")) == OK, "capture " + label)
	game.join_simulation_owner()
	game.set_process(restore_process)
	game.game_controller.set_paused(paused)
