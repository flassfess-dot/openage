extends SceneTree

const Probe := preload("res://scripts/performance_probe.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")

class FrameProbe extends Probe:
	var frame_metrics: Dictionary = {}
	func observe_microseconds(metric: String, duration_microseconds: int) -> void:
		super.observe_microseconds(metric, duration_microseconds)
		frame_metrics[metric] = int(frame_metrics.get(metric, 0)) + duration_microseconds

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var seconds := 120.0
	var save_path := ""
	var output := "res://qa/saved-match-stalls.json"
	var disable_ai := false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--save="): save_path = argument.trim_prefix("--save=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument == "--disable-ai": disable_ai = true
	if save_path.is_empty():
		push_error("Pass --save=user://saves/named/<slot>.json (the save is read only)")
		quit(1)
		return
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await MatchReady.wait_for_ready(self, game, 120000): quit(1); return
	print("STALL_PROBE loading ", save_path)
	if not game.load_game_from_path(save_path): push_error(game.last_save_error); quit(1); return
	if not await MatchReady.wait_for_ready(self, game, 120000): quit(1); return
	game.set_process(false)
	game.set_process_unhandled_input(false)
	if disable_ai:
		game.ai_decision_queue.cancel(game.task_coordinator)
		game.ai_players.clear()
	game.game_controller.set_paused(false)
	var probe := FrameProbe.new(30000)
	game.game_controller.set_performance_probe(probe)
	var timeline: Array = []
	var slow: Array = []
	var stalls: Array = []
	var stall: Dictionary = {}
	var initial_tick: int = game.game_controller.tick_index
	var started := Time.get_ticks_usec()
	var previous := started
	var end := started + int(seconds * 1000000)
	print("STALL_PROBE ready tick=%d size=%s units=%d resources=%d ai=%d" % [initial_tick, game.map_size, game.simulation_world.units.size(), game.simulation_world.resource_nodes.size(), game.ai_players.size()])
	while Time.get_ticks_usec() < end:
		var frame_started := Time.get_ticks_usec()
		var elapsed := frame_started - previous
		previous = frame_started
		probe.frame_metrics.clear()
		game._process(float(elapsed) / 1000000.0)
		game.current_world_drawables()
		var work := Time.get_ticks_usec() - frame_started
		var waiting: bool = game.game_controller.preparation_waiting
		var phase := "capture" if not game.ai_decision_queue.is_prepared() else "worker"
		if waiting:
			if stall.is_empty():
				stall = {"start_us": frame_started - started, "tick": game.game_controller.tick_index, "frames": 0, "capture_frames": 0, "worker_frames": 0, "teams": game.ai_decision_queue.records.map(func(r): return r["ai"].team)}
			stall["frames"] += 1
			stall[phase + "_frames"] += 1
		elif not stall.is_empty():
			stall["duration_us"] = frame_started - started - int(stall["start_us"])
			stalls.append(stall)
			if int(stall["duration_us"]) > 100000: print("STALL_PROBE gate ", JSON.stringify(stall))
			stall = {}
		if work > 50000:
			var stages: Array = []
			for key in probe.frame_metrics:
				if probe.frame_metrics[key] > 1000: stages.append({"metric": key, "us": probe.frame_metrics[key]})
			stages.sort_custom(func(a,b): return a["us"] > b["us"])
			var entry := {"time_us": frame_started - started, "tick": game.game_controller.tick_index, "work_us": work, "stages": stages.slice(0,16)}
			slow.append(entry)
			print("STALL_PROBE long_frame ", JSON.stringify(entry))
		timeline.append({"work_us": work, "frame_us": elapsed, "tick": game.game_controller.tick_index, "waiting": waiting})
		await process_frame
	if not stall.is_empty():
		stall["duration_us"] = Time.get_ticks_usec() - started - int(stall["start_us"])
		stalls.append(stall)
	var result := {"save": save_path, "ai_disabled": disable_ai, "initial_tick": initial_tick, "final_tick": game.game_controller.tick_index, "seconds": seconds, "timeline": timeline, "slow": slow, "stalls": stalls, "probe": probe.report()}
	result["work_us"] = Probe.summarize(timeline.map(func(row): return row["work_us"]))
	result["frame_us"] = Probe.summarize(timeline.map(func(row): return row["frame_us"]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write stall report: " + output)
		game.free()
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("STALL_PROBE done ", output, " work=", result["work_us"], " frames=", result["frame_us"])
	game.free()
	quit(0)
