extends SceneTree

const Service := preload("res://scripts/expedition.gd")
const Ready := preload("res://tests/support/match_ready.gd")
const TEAM := 2
var game
var world
var captain: Dictionary
var medic: Dictionary
var scout: Dictionary

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	if ok:
		print("OK ", label)
		return true
	push_error(label)
	if game != null: print_actions()
	quit(1)
	return false

func observe(predicate: Callable, ticks := 950, trace_survey := false) -> bool:
	var deadline := Time.get_ticks_msec() + 65000
	var stop_tick := int(game.game_controller.tick_index) + ticks
	var sample := 0
	while Time.get_ticks_msec() < deadline and game.game_controller.tick_index <= stop_tick:
		await process_frame
		game.join_simulation_owner()
		if predicate.call(): return true
		if trace_survey and game.game_controller.tick_index >= sample:
			var unknown := 0
			var origin := Vector2i(Vector2(scout.pos).floor())
			for y in range(maxi(0, origin.y - 11), mini(world.map_size.y, origin.y + 12)):
				for x in range(maxi(0, origin.x - 11), mini(world.map_size.x, origin.x + 12)):
					if Vector2i(x,y).distance_squared_to(origin) <= 121 and world.get_fog_of_war().state_at_world(TEAM, Vector2(x + 0.5, y + 0.5)) == 0: unknown += 1
			print("SCOUT ", game.game_controller.tick_index, " hp ", scout.hp, " pos ", scout.pos, " unknown ", unknown, " carrier ", scout.get("transported_by_id", -1))
			sample = (int(game.game_controller.tick_index) / 150 + 1) * 150
	return false

func start_setup() -> void:
	game.join_simulation_owner()
	game.ai_runtime.shutdown()

func finish_setup() -> void:
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	game._configure_ai_runtime()

func land(near: Vector2) -> Vector2:
	return Vector2(world.pathfinder.nearest_walkable(Vector2i(near.floor()), "land", -1, 0.35)) + Vector2(0.5, 0.5)

func frontier(origin: Vector2) -> Vector2:
	var best := Vector2.INF
	var nearest := INF
	var most_unexplored := 0
	var fog = world.get_fog_of_war()
	for y in range(9, world.map_size.y - 9, 2):
		for x in range(9, world.map_size.x - 9, 2):
			var point := Vector2(x + 0.5, y + 0.5)
			var d := origin.distance_squared_to(point)
			if d < 64 or fog.state_at_world(TEAM, point) != 0 or not world.pathfinder.is_position_walkable(point, 0.4): continue
			var unknown := 0
			for dy in range(-9, 10, 3):
				for dx in range(-9, 10, 3):
					if dx * dx + dy * dy <= 121 and fog.state_at_world(TEAM, point + Vector2(dx,dy)) == 0: unknown += 1
			if unknown > most_unexplored or (unknown == most_unexplored and d < nearest):
				best = point
				nearest = d
				most_unexplored = unknown
	return best

func print_actions() -> Dictionary:
	var controller = game.game_controller
	var recorder = controller.replay_recorder
	var accepted := {}
	if recorder == null: return accepted
	for record in recorder.command_records:
		if record.type != "field_service" or record.issuer_id != TEAM: continue
		var result: Dictionary = controller.get_command_result(record.sequence_id)
		var params: Dictionary = recorder.decode_variant(record.params)
		var key := "%d/%s/%s" % [record.unit_ids[0], params.action, params.get("item", "")]
		if result.get("accepted", false):
			accepted[key] = int(accepted.get(key, 0)) + 1
			print("AI ", record.tick, " id ", record.unit_ids[0], " ", params.action, " ", params.get("item", ""), " accepted")
		else:
			print("AI ", record.tick, " id ", record.unit_ids[0], " ", params.action, " ", result.get("reason", "pending"))
	return accepted

func run() -> void:
	var launcher = load("res://launcher.tscn").instantiate()
	root.add_child(launcher)
	current_scene = launcher
	await process_frame
	launcher.screen_buttons["single_player"].pressed.emit()
	launcher.screen_buttons["random_map"].pressed.emit()
	if not check(launcher.setting_controls["field_service_enabled"].button_pressed, "RPG is checked on the new random map"): return
	launcher._select_metadata(launcher.setting_controls["map_size_id"], "compact")
	launcher._select_metadata(launcher.setting_controls["map_type_id"], "grasslands")
	launcher.setting_controls["seed"].value = 41721
	launcher.start_button.pressed.emit()
	var deadline := Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_method("load_game_from_path"):
			game = current_scene
			break
	if not check(game != null and await Ready.wait_for_ready(self, game), "Generated map is running"): return
	world = game.simulation_world
	var computers: Array = game.ai_players.filter(func(ai): return ai.enabled and ai.team == TEAM)
	if not check(world.field_service_enabled and game.match_path.begins_with("generated://skirmish/") and computers.size() == 1, "Ordinary random-map opponent is active"): return
	print("MAP ", game.match_path, " AI ", computers[0].profile, " ", computers[0].economic_policy.get("algorithm_version", "legacy"))
	game.autosave.enabled = false
	game.autosave.shutdown()
	game.game_controller.set_speed_multiplier(3.0)
	start_setup()
	var towns: Array = world.get_buildings().filter(func(b): return b.team == TEAM and b.kind == "town_center")
	var origin: Vector2 = towns[0].pos
	captain = world.add_unit(TEAM, "clubman", land(origin + Vector2(4, 1)), false)
	if "--earn-veteran" in OS.get_cmdline_user_args():
		if not check(int(captain.get("service_xp", -1)) == 0, "Opposing soldier starts at zero experience"): return
		world.add_unit(1, "priest", land(captain.pos + Vector2(1, 0)), false)
		world.add_unit(1, "priest", land(captain.pos + Vector2(0, 1)), false)
		finish_setup()
		if not await observe(func(): return captain.has("service_role"), 3300):
			print("SOLDIER ", captain.get("service_xp"), " HP ", captain.hp, " task ", captain.get("task"), " tick ", game.game_controller.tick_index)
			check(false, "Soldier fought to veteran rank and the computer appointed him")
			return
		var records := print_actions()
		if not check(captain.get("service_role") == "captain" and int(captain.service_xp) >= Service.VETERAN and records.has("%d/captain/" % captain.id), "Combat experience alone led to an AI-issued captain appointment"): return
		print("RANDOM_MAP_AI_RPG_PASSED from zero XP to ", float(captain.service_xp) / 1000, " on ", game.match_path, " tick ", game.game_controller.tick_index)
		quit(0)
		return
	Service.award_personal(world, captain, Service.VETERAN)
	world.expedition_field.place(captain.pos, ["point", "shield", "balm"])
	finish_setup()
	if not check(await observe(func(): return captain.get("service_role") == "captain" and captain.get("service_weapon") == "point" and captain.get("service_item") == "shield" and Service.Inventory.balm_slot(captain) >= 0), "AI promoted the melee veteran, collected the coffer and equipped bronze and shield"): return
	start_setup()
	world.expedition_field.place(captain.pos, ["iron", "scales"])
	finish_setup()
	if not check(await observe(func(): return captain.get("service_weapon") == "iron" and captain.get("service_item") == "scales"), "AI swapped both backpack upgrades into occupied equipment slots"): return
	if not check(Service.Inventory.carried(captain).has("point") and Service.Inventory.carried(captain).has("shield"), "Replaced equipment is in the backpack"): return
	start_setup()
	var low_hp := roundi(float(captain.max_hp) * 0.4)
	world.set_entity_field(captain, "hp", float(low_hp))
	finish_setup()
	if not check(await observe(func(): return captain.hp >= low_hp + 18 and Service.Inventory.balm_slot(captain) < 0), "Wounded AI commander used a balm and regained 18 HP"): return
	start_setup()
	var companion: Dictionary = world.add_unit(TEAM, "clubman", land(captain.pos + Vector2(0, 1)), false)
	world.add_unit(1, "priest", land(captain.pos + Vector2(2, 0)), false)
	finish_setup()
	if not check(await observe(func(): return int(companion.get("service_guard_until", 0)) > game.game_controller.tick_index and int(captain.get("service_ready_tick", 0)) > 0), "AI captain applied shield formation to a companion in contact with the enemy"): return
	if not check(await observe(func(): return int(game.game_controller.tick_index) % 300 >= 270, 350), "Frontier encounter starts shortly before the scout's next survey opportunity"): return
	start_setup()
	var edge := frontier(origin)
	if not check(edge.is_finite(), "Walkable unexplored frontier available"): return
	scout = world.add_unit(TEAM, "archer", edge, false)
	medic = world.add_unit(TEAM, "priest", land(origin + Vector2(-4, 1)), false)
	var patient: Dictionary = world.add_unit(TEAM, "clubman", land(medic.pos + Vector2(1, 0)), false)
	var patient_start := 5.0
	world.set_entity_field(patient, "hp", patient_start)
	Service.award_personal(world, scout, Service.VETERAN)
	Service.award_personal(world, medic, Service.VETERAN)
	finish_setup()
	if not check(await observe(func(): return scout.get("service_role") == "scout" and medic.get("service_role") == "medic"), "AI independently appointed the archer as scout and priest as field medic"): return
	if not check(await observe(func(): return int(medic.get("service_ready_tick", 0)) > 0 and patient.hp >= patient_start + 13), "AI medic used bandaging on a wounded ally"): return
	if not check(await observe(func(): return int(scout.get("service_ready_tick", 0)) > 0, 1600, true), "AI scout surveyed previously unexplored terrain"): return
	var issued := print_actions()
	for pair in [[captain,"captain",""], [captain,"pickup",""], [captain,"activate","iron"], [captain,"activate","scales"], [captain,"balm",""], [captain,"ability",""], [medic,"medic",""], [medic,"ability",""], [scout,"scout",""], [scout,"ability",""]]:
		if not check(issued.has("%d/%s/%s" % [pair[0].id, pair[1], pair[2]]), "The AI issued the corresponding accepted public command for %s %s" % [pair[1], pair[2]]): return
	print("RANDOM_MAP_AI_RPG_PASSED ", game.match_path, " tick ", game.game_controller.tick_index)
	quit(0)
