extends SceneTree
const Ready:=preload("res://tests/support/match_ready.gd")
func _initialize() -> void:
	call_deferred("run")
func capture(game, directory: String, name: String) -> void:
	game.sync_world_state()
	game.refresh_hud_model()
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join(name+".png"))
func run() -> void:
	var directory:="res://qa/ui-fortifications-20261029/ui"
	var release := OS.has_feature("template") and not OS.has_feature("debug") and not OS.has_feature("editor")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): directory=argument.trim_prefix("--output=")
		if argument=="--require-release" and not release:
			push_error("A real exported Release is required")
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_node("WindowMode").apply_settings(false,Vector2i(1280,720))
	var game=load("res://main.tscn").instantiate()
	game.match_path="res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self,game,60000):quit(1);return
	game.game_controller.set_paused(true)
	game.set_process(false)
	var world=game.simulation_world
	world.grant_technology(1,101)
	world.grant_technology(1,11)
	var tower: Dictionary=world.add_building(90001,"tower",Vector2(13,21),1)
	var gate: Dictionary=world.add_building(90002,"gate",Vector2(16,21),1,false,{"gate_axis":0})
	game.resource_catalog.prewarm_match_entities([],world.get_buildings())
	game.view_zoom=2.0
	game.center_view_on_world(Vector2(15,21))
	var selected: Array[int]=[90002]
	game.player_control_state.replace_or_add(selected,false)
	for stage in range(4):
		gate["construction_stage"]=stage
		world.notify_entity_changed(gate)
		await capture(game,directory,"gate-construction-%d"%stage)
	world.complete_foundation(gate)
	await capture(game,directory,"gate-closed")
	gate["gate_open_fraction"]=1.0
	world.notify_entity_changed(gate)
	await capture(game,directory,"gate-open")
	var units: Array=[]
	for index in range(5):units.append(world.add_unit(1,"archer",Vector2(11.5,20.5+index*0.2),false))
	if not world.board_units(units,tower).is_empty():push_error("capture boarding failed");quit(1);return
	selected=[90001]
	game.player_control_state.replace_or_add(selected,false)
	await capture(game,directory,"garrison")
	var granary: Dictionary=world.add_building(90003,"granary",Vector2(22,22),1)
	world.add_building(90004,"market",Vector2(23,13),1)
	for index in range(3):preload("res://scripts/farm_reseed.gd").change(world,granary,1)
	selected=[90003]
	game.player_control_state.replace_or_add(selected,false)
	await capture(game,directory,"farm-reserve")
	var report := FileAccess.open(directory.path_join("report.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":true,"release":release,"executable":OS.get_executable_path(),"captures":8,"garrison":5,"farm_reserves":world.economy_system.farm_reseed_queues_by_team.get(1,[]).size()},"\t"))
	report.close()
	game.free()
	print("UI_FORTIFICATIONS_CAPTURE passed")
	quit(0)
