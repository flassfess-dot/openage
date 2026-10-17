extends Node
const Ready := preload("res://tests/support/match_ready.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
var failures: Array[String] = []
func _ready() -> void: call_deferred("run")
func run() -> void:
	var source := ""
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): source = arg.trim_prefix("--save=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if source.is_empty() or output.is_empty() or DisplayServer.get_name() == "headless": get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	Engine.max_fps = 60
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	var game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	get_tree().root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	if not game.load_game_from_path(source): push_error(game.last_save_error); get_tree().quit(1); return
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	game.set_process(false)
	game.autosave.enabled = true
	game.autosave.save_path = output.get_base_dir().path_join("live-autosave.json")
	game._seed_autosave()
	game.game_controller.set_paused(false)
	game.game_controller.set_speed_multiplier(1.0)
	game.set_process(true)
	var initial: int = game.game_controller.tick_index
	var frames := {"before": [], "during": [], "after": []}
	var started := Time.get_ticks_usec()
	var previous := started
	var requested := false
	var completed_at := -1
	var capture_us := 0
	while Time.get_ticks_usec() - started < 90000000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var phase := "during" if game.autosave.busy else "after" if completed_at >= 0 else "before"
		if now - started > 1000000: frames[phase].append(now - previous)
		previous = now
		capture_us = maxi(capture_us, game.autosave.last_capture_us)
		if not requested and now - started >= 4000000:
			game.autosave.elapsed = game.autosave.next_save
			requested = true
		if game.autosave.last_tick >= 0 and completed_at < 0: completed_at = now
		if completed_at >= 0 and now - completed_at >= 4000000: break
	game.game_controller.set_paused(true)
	game.set_process(false)
	if completed_at < 0: failures.append("autosave did not complete in live play")
	if game.autosave.worker_pool_shared: failures.append("recovery work used the shared gameplay worker pool")
	if frames["during"].size() < 30: failures.append("insufficient frames during background save")
	if game.game_controller.tick_index <= initial + 100: failures.append("live simulation did not continue")
	var entries := Archive.list_saves(output.get_base_dir(), output + ".missing", game.autosave.save_path)
	if entries.size() != 1: failures.append("one loadable autosave was not found")
	game.hud_modal_overlay.set_named_saves(entries)
	game.hud_modal_overlay.show_menu()
	game.hud_modal_overlay.show_section("load")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot := output.get_base_dir().path_join("live-autosave-load-menu.png")
	get_viewport().get_texture().get_image().save_png(screenshot)
	var summaries := {}
	for phase in frames: summaries[phase] = Probe.summarize(frames[phase])
	var report := {"passed": failures.is_empty(), "release": not OS.is_debug_build(), "rendered": true, "source": source, "initial_tick": initial, "final_tick": game.game_controller.tick_index, "saved_tick": game.autosave.last_tick, "capture_us": capture_us, "worker_pool_shared": game.autosave.worker_pool_shared, "frame_us": summaries, "screenshot": screenshot, "failures": failures}
	game.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for failure in failures: push_error(failure)
	print("LIVE_AUTOSAVE_VERIFY ", JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)
