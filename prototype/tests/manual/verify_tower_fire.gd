extends Node
const Ready := preload("res://tests/support/match_ready.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if output.is_empty() or DisplayServer.get_name() == "headless": push_error("Pass --output to a graphical runtime"); get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	get_node("/root/WindowMode").apply_settings(false, Vector2i(1280,720))
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	get_tree().root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	var tower: Dictionary = game.simulation_world.add_building(90001, "tower", Vector2(15,20), 1)
	game.resource_catalog.prewarm_match_entities([], game.simulation_world.get_buildings())
	game.game_controller.set_paused(false)
	game.game_controller.set_speed_multiplier(1.0)
	game.view_zoom = 3.0
	game.center_view_on_world(tower["pos"])
	game.view_offset.y += 120.0
	for _frame in range(4): await get_tree().process_frame
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	game.set_process(false)
	var samples: Array = []
	var distinct_frames := {}
	for index in range(40):
		if not await Ready.advance_to_tick(get_tree(), game.game_controller, game.game_controller.tick_index+1, game.PLAYER_TEAM, game.ENEMY_TEAM): get_tree().quit(1); return
		game.sync_world_state()
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var fire: Array = game.current_world_drawables().filter(func(item): return String(item.get("kind", "")) == "building_part" and int(item.get("stable_id", -1)) == 90001 and int(item.get("frame_info", {}).get("graphic_id", -1)) == 324)
		var frames: Array = fire.map(func(item): return int(item.get("frame", -1)))
		if frames.size() != 4: push_error("Four visible tower torches required"); get_tree().quit(1); return
		distinct_frames[frames[0]] = true
		var capture := output.get_base_dir().path_join("fire-%03d.png" % index)
		if get_tree().root.get_texture().get_image().save_png(capture) != OK: push_error("Cannot capture tower fire"); get_tree().quit(1); return
		samples.append({"tick":game.game_controller.tick_index,"frames":frames,"capture":capture})
	var passed := distinct_frames.size() == 20
	for i in range(1,samples.size()): passed = passed and samples[i]["frames"][0] != samples[i-1]["frames"][0]
	var report := {"passed":passed,"release":not OS.is_debug_build() and not Engine.is_editor_hint(),"source_unit_id":tower.get("source_unit_id",-1),"distinct_fire_frames":distinct_frames.size(),"frame_seconds":0.05,"samples":samples}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write tower report"); get_tree().quit(1); return
	file.store_string(JSON.stringify(report,"\t"))
	game.free()
	if not passed: push_error("Tower fire did not advance at every tick")
	print("TOWER_FIRE ",JSON.stringify({"passed":passed,"distinct_frames":distinct_frames.size(),"release":report["release"]}))
	get_tree().quit(0 if passed else 1)
