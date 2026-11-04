extends Node

# Deliberately avoid preloading gameplay scripts: this must report a broken
# exported class registry instead of failing before the smoke check can start.
var tree: SceneTree
var output_path := ""
var save_path := ""
var map_size_id := "compact"
var map_type_id := "grasslands"
var naval_fixture: Dictionary={}
var report: Dictionary = {"passed": false, "stages": []}


func _ready() -> void:
	tree = get_tree()
	call_deferred("run")


func run() -> void:
	Engine.max_fps = 60
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
		elif argument.begins_with("--save="): save_path = argument.trim_prefix("--save=")
		elif argument.begins_with("--map-size="): map_size_id = argument.trim_prefix("--map-size=")
		elif argument.begins_with("--map-type="): map_type_id = argument.trim_prefix("--map-type=")
	if output_path.is_empty():
		fail("Pass --output=<report.json> in a writable diagnostic directory")
		return
	report["release"] = not OS.has_feature("editor")
	if "--require-release" in OS.get_cmdline_user_args() and not report["release"]:
		fail("Startup verification must run the exported executable")
		return
	var classes: Dictionary = {}
	for entry in ProjectSettings.get_global_class_list():
		if String(entry["path"]).begins_with("res://qa/"):
			fail("Diagnostic copy registered as a game class: " + String(entry["path"]))
			return
		classes[String(entry["class"])] = String(entry["path"])
	for expected in ["RoRIsolatedTaskData", "RoRPathfinder", "RoRGameController", "RoRNavigationLoading", "RoRNavigationTaskData", "RoRFormationCorridor", "RoRFormationPreview", "RoRPickingService", "RoRRenderWorld", "RoRSimulationMovementSystem"]:
		if not classes.has(expected) or not String(classes[expected]).begins_with("res://scripts/") or not ResourceLoader.exists(classes[expected]):
			fail("Missing or invalid exported class: " + expected)
			return
	print("PACKAGED_STARTUP class registry OK")
	var launcher = tree.current_scene
	if launcher == null or not launcher.has_method("_launch_custom_skirmish"):
		fail("Startup verification requires the real launcher scene")
		return
	await tree.process_frame
	launcher.screen_buttons["single_player"].pressed.emit()
	launcher.screen_buttons["random_map"].pressed.emit()
	launcher._select_metadata(launcher.setting_controls["map_size_id"], map_size_id)
	launcher._select_metadata(launcher.setting_controls["map_type_id"], map_type_id)
	launcher.setting_controls["seed"].value = 41721
	launcher.start_button.pressed.emit()
	var game = await wait_for_match("random_map")
	if game == null: return
	if not await check_running(game, "random_map"): return
	if "--rendered-load-fixture" in OS.get_cmdline_user_args():
		if not await measure_rendered_load(game): return
		report["passed"]=true
		write_report()
		tree.quit(0)
		return
	if "--combat-fixture" in OS.get_cmdline_user_args() and not await prepare_combat(game): return
	if "--naval-fixture" in OS.get_cmdline_user_args() and not await prepare_naval(game): return
	if save_path.is_empty():
		save_path = output_path.get_base_dir().path_join("startup-roundtrip.json")
		if not game.save_game_to_path(save_path, "Release startup verification"):
			fail("Could not save temporary verification match: " + String(game.last_save_error))
			return
	report["save_path"] = save_path
	tree.current_scene = null
	game.free()
	await tree.process_frame
	launcher = open_launcher()
	if launcher == null: return
	await tree.process_frame
	launcher._show_save_menu()
	# Use the actual menu load callback, without changing the user's saves.
	launcher.saved_games.assign([{ "path": save_path }])
	launcher.save_list.clear()
	launcher.save_list.add_item("Release startup verification")
	launcher.save_list.select(0)
	launcher._load_selected_save()
	game = await wait_for_match("load_save")
	if game == null: return
	game.join_simulation_owner()
	game.game_controller.set_paused(false)
	if not naval_fixture.is_empty():
		if not game.simulation_world.transport_system.embarked_units.has(int(naval_fixture["passenger"])): fail("Loaded naval passenger is missing"); return
		var transport_ids: Array[int]=[int(naval_fixture["ship"])]
		var command=load("res://scripts/commands.gd").UnloadCommand.new(game.game_controller.tick_index,transport_ids,naval_fixture["landing"])
		if not await apply_public_command(game,command): fail("Loaded transport cannot unload through public command"); return
		report["naval_save_unload"]=game.simulation_world.find_unit(int(naval_fixture["passenger"]))!=null
		if not report["naval_save_unload"]: fail("Loaded transport did not restore passenger ownership on landing"); return
	if not await check_running(game, "load_save"): return
	tree.current_scene = null
	game.free()
	if "--competitive-ai" in OS.get_cmdline_user_args():
		launcher=open_launcher()
		if launcher==null: return
		await tree.process_frame
		launcher.screen_buttons["single_player"].pressed.emit(); launcher.screen_buttons["random_map"].pressed.emit()
		launcher._select_metadata(launcher.setting_controls["map_size_id"],map_size_id)
		launcher.start_button.pressed.emit()
		game=await wait_for_match("restart_match")
		if game==null or not await check_running(game,"restart_match"): return
		tree.current_scene=null; game.free()
	report["passed"] = true
	write_report()
	print("PACKAGED_STARTUP PASSED: random map and saved game both reached running simulation")
	tree.quit(0)


func open_launcher():
	var scene = load("res://launcher.tscn")
	if scene == null or not scene.can_instantiate():
		fail("Cannot load exported launcher")
		return null
	var launcher = scene.instantiate()
	if not launcher.has_method("_launch_custom_skirmish"):
		launcher.free()
		fail("Exported launcher script did not compile")
		return null
	tree.root.add_child(launcher)
	tree.current_scene = launcher
	return launcher


func wait_for_match(stage: String):
	var deadline := Time.get_ticks_msec() + 180000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		if stage == "load_save" and is_instance_valid(tree.current_scene) and tree.current_scene.has_method("_load_selected_save") and tree.current_scene.current_screen == "saves":
			report["menu_status"] = tree.current_scene.status_label.text if tree.current_scene.status_label != null else ""
			fail("The current save menu rejected the load: " + String(report["menu_status"] ))
			return null
		if is_instance_valid(tree.current_scene) and tree.current_scene.has_method("load_game_from_path"):
			if tree.current_scene.game_controller != null and not tree.current_scene.navigation_loading.is_loading():
				tree.current_scene.join_simulation_owner()
				return tree.current_scene
	fail("Match never became ready: " + stage)
	return null


func check_running(game, stage: String) -> bool:
	if "--competitive-ai" in OS.get_cmdline_user_args():
		game.join_simulation_owner()
		var enabled: Array=game.ai_players.filter(func(ai): return ai.enabled)
		if enabled.is_empty() or enabled.any(func(ai): return String(ai.economic_policy.get("algorithm_version",""))!="competitive_v2" or ai.competitive_controller==null): fail("Packaged match did not activate competitive_v2"); return false
		report["algorithm_version"]="competitive_v2"
		var parameter_keys:=["attack_ratio","retreat_ratio","worker_population_ratio","forecast_seconds","plan_inertia","micro_repeat_ticks","maximum_economic_danger","minimum_naval_escort","ranker_enabled","ranker_model"]
		report["activated_policy_parameters"]=enabled.map(func(ai):
			var parameters:={}
			for key in parameter_keys:
				if ai.economic_policy.has(key): parameters[key]=ai.economic_policy[key]
			return parameters)
	var initial_tick := int(game.simulation_frame_state()["tick"])
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		var current_tick := int(game.simulation_frame_state()["tick"])
		if current_tick >= initial_tick + 10:
			game.current_world_drawables()
			var stage_report := {"stage":stage,"initial_tick":initial_tick,"final_tick":current_tick,"map_size":[game.map_size.x,game.map_size.y],"simulation_owner_started":game.simulation_owner.thread.is_started()}
			if "--capture-rendered-startup" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
				if not await capture_rendered_stage(game,stage,stage_report): return false
				stage_report["final_tick"]=int(game.simulation_frame_state()["tick"])
			report["stages"].append(stage_report)
			print("PACKAGED_STARTUP %s running: tick %d -> %d" % [stage, initial_tick, current_tick])
			return true
	fail("Simulation did not advance after loading: " + stage)
	return false

static func has_visible_world(image: Image) -> bool:
	if image==null or image.is_empty(): return false
	var width:=image.get_width(); var height:=image.get_height(); var colored:=0
	# Exclude the HUD: a black world with a working status bar is not ready.
	for y in range(int(height*0.1),int(height*0.8),maxi(1,height/32)):
		for x in range(width/20,width*19/20,maxi(1,width/48)):
			var pixel:=image.get_pixel(x,y)
			if maxf(pixel.r,maxf(pixel.g,pixel.b))>0.08:
				colored+=1
				if colored>=8: return true
	return false

func capture_rendered_stage(game,stage: String,stage_report: Dictionary) -> bool:
	var started:=Time.get_ticks_msec(); var deadline:=started+30000
	while Time.get_ticks_msec()<deadline:
		game.current_world_drawables(); game.queue_redraw()
		for frame in range(6): await tree.process_frame
		await RenderingServer.frame_post_draw
		var rendered:=tree.root.get_texture().get_image()
		if not has_visible_world(rendered): continue
		DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		var screenshot:=output_path.get_base_dir().path_join(stage+".png")
		if rendered.save_png(screenshot)!=OK:
			fail("Cannot capture rendered verification: "+screenshot); return false
		stage_report["screenshot"]=screenshot
		stage_report["render_wait_ms"]=Time.get_ticks_msec()-started
		return true
	fail("Rendered world remained black after loading: "+stage)
	return false


func begin_authored_fixture(game) -> bool:
	game.join_simulation_owner()
	var before:Array=game.ai_players.map(func(ai):return ai.canonical_state())
	var pending:bool=game.ai_decision_queue.active
	# Joining the simulation thread can leave a budgeted read generation pinned.
	# Retire that pending query through its owner before changing the authored
	# initial state; reconfigure the same enabled AIs immediately after setup.
	game.ai_runtime.shutdown()
	var pins:=int(game.simulation_world.entity_mutations.read_generation_pins)
	if pins!=0 or game.ai_players.map(func(ai):return ai.canonical_state())!=before:
		fail("Authored fixture did not retire its AI capture without changing player state")
		return false
	report.get_or_add("authored_setup",[]).append({"tick":game.game_controller.tick_index,"pending_query_retired":pending,"remaining_generation_pins":pins})
	return true


func measure_rendered_load(game) -> bool:
	if DisplayServer.get_name()=="headless": fail("Rendered load requires a real graphics backend"); return false
	if not begin_authored_fixture(game):return false
	# The authored roster is a diagnostic initial state, outside the normal replay.
	# Do not submit it to the user autosave mirror. Save/load is tested separately.
	game.autosave.enabled=false
	game.autosave.shutdown()
	var setup_started=Time.get_ticks_msec()
	var algorithm_versions: Array=game.ai_players.filter(func(ai): return ai.enabled).map(func(ai): return String(ai.economic_policy.get("algorithm_version","legacy_adaptive_v1")))
	var world=game.simulation_world
	var teams: Array=world.player_registry.all_teams()
	teams=teams.filter(func(team): return int(team)>0)
	teams.sort()
	if teams.size()!=2: fail("Rendered load fixture requires the default two participants"); return false
	var occupied: Dictionary={}
	for actor in world.get_units(): occupied[Vector2i(Vector2(actor["pos"]).floor())]=true
	var commands=load("res://scripts/commands.gd")
	var counts: Dictionary={}
	var water_ids=load("res://scripts/terrain_rules.gd").WATER_TERRAIN_IDS
	var spawn_terrain_counts: Dictionary={}
	for team_value in teams:
		var team_id=int(team_value)
		var bases: Array=world.get_buildings().filter(func(b): return int(b.get("team",0))==team_id and String(b.get("kind",""))=="town_center")
		if bases.is_empty(): fail("Rendered fixture has no starting town center"); return false
		var origin=Vector2(bases[0]["pos"])
		var own: Array=world.get_units().filter(func(u): return int(u.get("team",0))==team_id)
		var restriction=int(own[0].get("terrain_restriction",-1))
		var positions: Array=[]
		for y in range(1,world.map_size.y-1):
			for x in range(1,world.map_size.x-1):
				var cell=Vector2i(x,y)
				if occupied.has(cell) or world.navigation_grid.terrain_id(cell) in water_ids: continue
				var point=Vector2(cell)+Vector2(0.5,0.5)
				if world.navigation_grid.is_position_walkable_for(point,0.35,"land",restriction): positions.append(point)
		positions.sort_custom(func(a,b):
			var da=origin.distance_squared_to(a); var db=origin.distance_squared_to(b)
			return da<db if da!=db else a.y<b.y if a.y!=b.y else a.x<b.x)
		var needed=maxi(0,500-own.size())
		if positions.size()<needed: fail("Rendered load has too few legal initial positions"); return false
		world.set_population_cap(team_id,500); world.set_population_housing(team_id,500)
		var moving: Array[int]=[]
		var trees: Array=world.get_resources().filter(func(r): return String(r.get("kind",""))=="tree" and origin.distance_to(Vector2(r["pos"]))<18.0)
		for index in range(needed):
			var roster_index=own.size()+index
			var position=Vector2(positions[index]); occupied[Vector2i(position.floor())]=true
			var terrain_key=str(world.navigation_grid.terrain_id(Vector2i(position.floor())))
			spawn_terrain_counts[terrain_key]=int(spawn_terrain_counts.get(terrain_key,0))+1
			var actor: Dictionary=world.add_unit(team_id,"villager" if roster_index<225 else "archer" if roster_index%2==0 else "clubman",position,false)
			if roster_index<100 and not trees.is_empty(): world.assign_command_gather([actor],int(trees[index%trees.size()]["id"]))
			elif roster_index>=225 and roster_index<325: moving.append(int(actor["id"]))
		if not moving.is_empty(): game.game_controller.enqueue_command(commands.AttackMoveCommand.new(game.game_controller.tick_index,moving,Vector2(world.map_size)*0.5),true,team_id)
		counts[str(team_id)]=world.get_units().filter(func(u): return int(u.get("team",0))==team_id).size()
	world.update_fog_of_war()
	world=null
	game._configure_ai_runtime()
	var setup_ms=Time.get_ticks_msec()-setup_started
	var warm_deadline=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<warm_deadline: await tree.process_frame
	var initial_tick=int(game.simulation_frame_state()["tick"])
	var owner_frames=0
	var started=Time.get_ticks_usec(); var previous=started
	var frame_probe=load("res://scripts/performance_probe.gd").new(8192)
	while Time.get_ticks_usec()-started<20000000:
		await tree.process_frame
		var now=Time.get_ticks_usec()
		if game.simulation_owner.thread.is_started(): owner_frames+=1
		frame_probe.observe_microseconds("rendered.frame_interval",now-previous)
		previous=now
	var elapsed=Time.get_ticks_usec()-started
	var final_tick=int(game.simulation_frame_state()["tick"])
	var frame_count=frame_probe.sample_count("rendered.frame_interval")
	var rendered: Dictionary={"initial_units_by_team":counts,"spawn_terrain_counts":spawn_terrain_counts,"spawned_on_dry_land":true,"setup_ms":setup_ms,"algorithm_versions":algorithm_versions,"ai_players":algorithm_versions.size(),"owner_started_samples":owner_frames,"autosave":"disabled for authored roster; archive checks are separate","warm_seconds":5,"sample_seconds":float(elapsed)/1000000.0,"frames":frame_count,"initial_tick":initial_tick,"final_tick":final_tick,"fixed_ticks":final_tick-initial_tick,"fixed_ticks_per_second":float(final_tick-initial_tick)*1000000.0/float(elapsed),"frame_intervals_us":frame_probe.report()["metrics_microseconds"]["rendered.frame_interval"],"simulation_owner_started":game.simulation_owner.thread.is_started(),"graphics_backend":DisplayServer.get_name(),"scope":"Authored mixed-load initial roster, 2x500; actual rendered EXE intervals and simulation progress; no human skill or full-match FPS claim"}
	if frame_count<30 or final_tick<=initial_tick or owner_frames==0: fail("Rendered load did not produce frames and progressing simulation"); return false
	if not await capture_rendered_stage(game,"rendered-load-2x500",rendered): return false
	report["rendered_load"]=rendered
	return true


func prepare_combat(game) -> bool:
	if not begin_authored_fixture(game):return false
	var world=game.simulation_world
	var base: Dictionary=world.get_buildings().filter(func(b): return int(b.get("team",0))==1 and String(b.get("kind",""))=="town_center")[0]
	var origin:=Vector2(base["pos"])
	var ids: Array=[]
	for side in [1,2]:
		for index in range(4):
			var actor: Dictionary=world.add_unit(side,"archer" if side==2 else "clubman",origin+Vector2(4.0+side*3.0,index*1.0-1.5),false)
			ids.append(int(actor["id"]))
	world.update_fog_of_war()
	var initial_tick: int=game.game_controller.tick_index
	world=null
	game._configure_ai_runtime()
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await tree.process_frame
		if int(game.simulation_frame_state()["tick"])<initial_tick+100: continue
		game.join_simulation_owner()
		var active: Array=game.simulation_world.get_units().filter(func(u): return int(u["id"]) in ids)
		var damaged: bool=active.size()<ids.size() or active.any(func(u): return float(u["hp"])<float(u["max_hp"]))
		var decisions: int=game.ai_players.filter(func(ai): return ai.enabled)[0].strategy.metrics.get("commands_accepted",0)
		var tactical: Dictionary=game.ai_players.filter(func(ai): return ai.enabled)[0].competitive_controller.micro.last_orders if "--competitive-ai" in OS.get_cmdline_user_args() else {}
		report["combat_fixture"]={"setup":"fixed diagnostic forces; ordinary AI commands, no strength score","actors":ids,"damaged":damaged,"accepted_ai_commands":decisions,"micro_orders":tactical.size(),"tick":game.game_controller.tick_index}
		if not damaged or decisions<=0: fail("Packaged combat fixture did not produce real combat and AI commands"); return false
		return true
	fail("Packaged combat fixture timed out"); return false

func prepare_naval(game) -> bool:
	if not begin_authored_fixture(game):return false
	var world=game.simulation_world
	var home:=Vector2(world.get_buildings().filter(func(b): return int(b.get("team",0))==1)[0]["pos"])
	var best: Dictionary={}; var score:=INF
	for y in range(2,world.map_size.y-2):
		for x in range(2,world.map_size.x-2):
			var water:=Vector2(x+0.5,y+0.5)
			if not world.navigation_grid.is_position_walkable_for(water,0.75,"water",-1): continue
			for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
				var land: Vector2=water+offset
				if not world.navigation_grid.is_position_walkable_for(land,0.2,"land",-1): continue
				var value:=home.distance_squared_to(land)
				if value<score: score=value; best={"water":water,"land":land}
	if best.is_empty(): fail("Island fixture has no legal transport beach"); return false
	var ship: Dictionary=world.add_unit(1,"transport",best["water"],false)
	var passenger: Dictionary=world.add_unit(1,"clubman",best["land"],false)
	world.update_fog_of_war()
	var passenger_ids: Array[int]=[int(passenger["id"])]
	var ship_id:=int(ship["id"])
	var passenger_id:=int(passenger["id"])
	world=null
	game._configure_ai_runtime()
	var command=load("res://scripts/commands.gd").BoardCommand.new(game.game_controller.tick_index,passenger_ids,ship_id)
	if not await apply_public_command(game,command) or not game.simulation_world.transport_system.embarked_units.has(passenger_id): fail("Public boarding failed in packaged island fixture"); return false
	naval_fixture={"ship":ship_id,"passenger":passenger_id,"landing":best["land"]}
	report["naval_fixture"]={"setup":"public player commands; not a naval AI strength measurement","ship":ship_id,"passenger":passenger_id}
	return true


func apply_public_command(game, command) -> bool:
	# Match the player's command boundary. A published observation may still be
	# pinned after joining the simulation owner; only the fixed tick can safely
	# finish that capture before dispatching a mutating command.
	game.game_controller.enqueue_command(command,true,1)
	var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await tree.process_frame
		game.join_simulation_owner()
		var result: Dictionary=game.game_controller.get_command_result(command.sequence_id)
		if not result.is_empty(): return bool(result.get("accepted",false))
	return false


func fail(message: String) -> void:
	report["error"] = message
	write_report()
	push_error(message)
	tree.quit(1)


func write_report() -> void:
	if output_path.is_empty(): return
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write startup report: " + output_path)
		return
	file.store_string(JSON.stringify(report, "\t"))
