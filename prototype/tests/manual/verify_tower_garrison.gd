extends SceneTree

const Ready := preload("res://tests/support/match_ready.gd")


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var output := "res://qa/tower-garrison"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if DisplayServer.get_name() == "headless":
		push_error("A graphical runtime is required for the garrison capture")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.get_node("WindowMode").apply_settings(false, Vector2i(1280, 720))
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self, game, 60000):
		quit(1)
		return
	game.game_controller.set_paused(true)
	game.set_process(false)
	var world = game.simulation_world
	var tower: Dictionary = world.add_building(90001, "tower", Vector2(15, 20), 1)
	var occupants: Array = []
	for index in range(5):
		occupants.append(world.add_unit(1, "archer" if index < 4 else "clubman", Vector2(13.4, 19.5 + index * 0.2), false))
	var reason: String = world.board_units(occupants, tower)
	if not reason.is_empty():
		push_error(reason)
		quit(1)
		return
	game.resource_catalog.prewarm_match_entities([], world.get_buildings())
	var ids: Array[int] = [90001]
	game.player_control_state.replace_or_add(ids, false)
	game.view_zoom = 2.0
	game.center_view_on_world(tower["pos"])
	for phase in ["full", "single", "empty"]:
		if phase != "full":
			game.command_actions.issue_ungarrison(game, 90001, int(occupants[0]["id"]) if phase == "single" else -1)
			game.game_controller.tick_index += 1
			game.game_controller.process_commands()
		game.sync_world_state()
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.save_png(output.path_join(phase + ".png")) != OK:
			push_error("Cannot save garrison screenshot")
			quit(1)
			return
		print("GARRISON_CAPTURE ", phase, " occupants=", world.transport_system.passenger_count(tower))
	game.free()
	quit(0)
