extends SceneTree

const Settings := preload("res://scripts/skirmish_settings.gd")
const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const Probe := preload("res://scripts/performance_probe.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var settings := Settings.default_settings()
	settings["map_size_id"] = "supergiant"
	settings["population_limit"] = 500
	settings["map_type_id"] = "mediterranean"
	var ticks := 700
	var disable_ai := false
	var rendered := false
	var output := "user://large-map-camera-benchmark.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ticks="): ticks = int(argument.trim_prefix("--ticks="))
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--map-size="): settings["map_size_id"] = argument.trim_prefix("--map-size=")
		elif argument.begins_with("--map-type="): settings["map_type_id"] = argument.trim_prefix("--map-type=")
		elif argument.begins_with("--seed="): settings["seed"] = int(argument.trim_prefix("--seed="))
		elif argument == "--disable-ai": disable_ai = true
		elif argument == "--rendered": rendered = true
	if rendered and DisplayServer.get_name() == "headless":
		push_error("--rendered requires a display renderer (omit --headless)")
		quit(1)
		return
	root.size = Vector2i(2560, 1080)
	var started := Time.get_ticks_usec()
	print("FREEZE_PROBE generating ", settings["map_size_id"], " ", settings["map_type_id"])
	var built := Settings.build(settings)
	assert(bool(built.get("valid", false)), str(built.get("errors")))
	print("FREEZE_PROBE generated ms=", (Time.get_ticks_usec() - started) / 1000)
	var game = load("res://main.tscn").instantiate()
	game.match_path = built["identity"]
	game.match_definition_override = built["definition"]
	game.map_definition_override = built["map_data"]
	root.add_child(game)
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	if disable_ai: game.ai_players.clear()
	if game.scenario_overlay != null: game.scenario_overlay.queue_free(); game.scenario_overlay = null
	if game.hud_modal_overlay != null: game.hud_modal_overlay.queue_free(); game.hud_modal_overlay = null
	var probe := Probe.new(ticks * 2 + 100)
	game.game_controller.set_performance_probe(probe)
	var cycles: Array[int] = []
	var slow: Array = []
	var rendered_frames: Array[int] = []
	var camera_samples: Array = []
	var frame_intervals: Array[int] = []
	var previous_frame_start := 0
	var slow_rendered_frames: Array = []
	print("FREEZE_PROBE ready ms=", (Time.get_ticks_usec() - started) / 1000, " resources=", game.simulation_world.get_resources().size(), " ai=", game.ai_players.size())
	for step in range(ticks):
		var counts: Dictionary = {}
		for metric in probe.samples_by_metric: counts[metric] = probe.samples_by_metric[metric].size()
		var tick_start := Time.get_ticks_usec()
		if rendered and previous_frame_start > 0: frame_intervals.append(tick_start - previous_frame_start)
		previous_frame_start = tick_start
		if step in [200, 400, 600]:
			var target := Vector2(200, 200) if step == 200 else Vector2(320, 200) if step == 400 else Vector2(200, 80)
			var geometry: Dictionary = game.minimap_geometry()
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = MinimapProjection.world_to_minimap(target, geometry["center"], geometry["scale"])
			var accepted: bool = game.handle_minimap_input(click)
			assert(accepted, "minimap camera click accepted")
		game._process(0.05)
		game.current_world_drawables()
		var us := Time.get_ticks_usec() - tick_start
		cycles.append(us)
		if step in [200, 400, 600]: camera_samples.append({"step": step, "us": us, "terrain": game.terrain_canvas.last_mesh_build_metrics.duplicate()})
		if us > 50000:
			var stages: Array = []
			for metric in probe.samples_by_metric:
				var durations: Array = probe.samples_by_metric[metric]
				var total := 0
				for index in range(int(counts.get(metric, 0)), durations.size()): total += int(durations[index])
				if total > 1000: stages.append({"metric": metric, "us": total})
			stages.sort_custom(func(a, b): return int(a["us"]) > int(b["us"]))
			var sample := {"step": step, "tick": game.game_controller.tick_index, "us": us, "stages": stages.slice(0, 18)}
			slow.append(sample)
			print("FREEZE_PROBE slow ", JSON.stringify(sample))
		if rendered:
			await RenderingServer.frame_post_draw
			var frame_us := Time.get_ticks_usec() - tick_start
			rendered_frames.append(frame_us)
			if frame_us > 100000: slow_rendered_frames.append({"step": step, "us": frame_us})
			await process_frame
		elif step % 20 == 0: await process_frame
	var result := {"settings": settings, "ai_disabled": disable_ai, "rendered": rendered, "frame_intervals_us": Probe.summarize(frame_intervals), "slow_rendered_frames": slow_rendered_frames, "camera_samples": camera_samples, "rendered_frames_us": Probe.summarize(rendered_frames), "cycles_us": Probe.summarize(cycles), "slow": slow, "probe": probe.report(), "resources": game.simulation_world.get_resources().size(), "units": game.simulation_world.get_units().size(), "buildings": game.simulation_world.get_buildings().size()}
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null, output)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("FREEZE_PROBE done ", output, " ", JSON.stringify(result["cycles_us"]))
	game.free()
	quit()
