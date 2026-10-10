extends SceneTree
const Probe := preload("res://scripts/performance_probe.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var save_path := ""
	var output := ""
	var seconds := 90.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save="): save_path = argument.trim_prefix("--save=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
	if save_path.is_empty() or output.is_empty() or FileAccess.file_exists(output):
		push_error("Pass a save and a new output path")
		quit(1)
		return
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await MatchReady.wait_for_ready(self, game, 120000): quit(1); return
	if not game.load_game_from_path(save_path): push_error(game.last_save_error); quit(1); return
	if not await MatchReady.wait_for_ready(self, game, 120000): quit(1); return
	game.game_controller.set_paused(false)
	var probe := Probe.new(30000)
	game.game_controller.set_performance_probe(probe)
	var initial_tick: int = game.game_controller.tick_index
	var initial_offset: Vector2 = game.view_offset
	var selected: Array[int] = []
	for unit in game.simulation_world.get_units():
		if int(unit.get("team", 0)) == game.local_player_team:
			selected.append(int(unit["id"]))
			if selected.size() >= 40: break
	var started := Time.get_ticks_usec()
	var previous := started
	var timeline: Array = []
	while Time.get_ticks_usec() - started < int(seconds * 1000000):
		await process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - started) / 1000000.0
		# Natural _process/_draw; only camera and selection are scripted.
		game.view_offset = initial_offset + Vector2(sin(elapsed * 0.4) * 480.0, cos(elapsed * 0.3) * 240.0)
		if int(elapsed) % 10 < 5: game.player_control_state.replace_or_add(selected, false)
		else: game.player_control_state.clear()
		timeline.append({"time_us": now - started, "frame_us": now - previous, "tick": game.game_controller.tick_index, "memory_static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC)})
		previous = now
	var result := {"save": save_path, "seconds": seconds, "resolution": [1280, 720], "headless": DisplayServer.get_name() == "headless", "initial_tick": initial_tick, "final_tick": game.game_controller.tick_index, "natural_frame_us": Probe.summarize(timeline.map(func(row): return row["frame_us"])), "steady_frame_us": Probe.summarize(timeline.filter(func(row): return row["time_us"] >= 15000000).map(func(row): return row["frame_us"])), "timeline": timeline, "probe": probe.report()}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("Cannot save graphical profile"); quit(1); return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("GRAPHICAL_PROFILE ", result["natural_frame_us"])
	game.free()
	quit(0)
