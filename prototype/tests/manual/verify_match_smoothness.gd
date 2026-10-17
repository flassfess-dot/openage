extends Node
const BaseProbe := preload("res://scripts/performance_probe.gd")
const Ready := preload("res://tests/support/match_ready.gd")
class FrameProbe extends BaseProbe:
	var metrics: Dictionary = {}
	func observe_microseconds(metric: String, us: int) -> void:
		super.observe_microseconds(metric, us)
		metrics[metric] = int(metrics.get(metric, 0)) + us
var game
var probe := FrameProbe.new(8192)
var measuring := false
var previous := 0
var started := 0
var frames: Array = []
var phases := {"idle": [], "autosave": []}
var slow: Array = []
var memory_peak := 0
var capture_peak := 0
var completed: Array[int] = []
var pan := false
var camera_origin := Vector2.ZERO
var profile_stages := true
func _process(_delta: float) -> void:
	if not measuring: return
	var now := Time.get_ticks_usec()
	if pan:
		var seconds := float(now - started) / 1000000.0
		game.view_offset = camera_origin + Vector2(sin(seconds * 0.4) * 160, sin(seconds * 0.25) * 90)
	if previous > 0 and now - started > 1000000:
		var elapsed := now - previous
		frames.append(elapsed)
		phases["autosave" if game.autosave.busy else "idle"].append(elapsed)
		if elapsed > 50000:
			var stages: Array = []
			for key in probe.metrics:
				if probe.metrics[key] > 1000: stages.append({"name": key, "us": probe.metrics[key]})
			stages.sort_custom(func(a,b): return a["us"] > b["us"])
			slow.append({"seconds": float(now - started) / 1000000.0, "tick": game.game_controller.tick_index, "frame_us": elapsed, "busy": game.autosave.busy, "stages": stages.slice(0,14)})
	probe.metrics.clear()
	previous = now
	memory_peak = maxi(memory_peak, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
	capture_peak = maxi(capture_peak, game.autosave.last_capture_us)
	if game.autosave.last_tick >= 0 and (completed.is_empty() or completed.back() != game.autosave.last_tick): completed.append(game.autosave.last_tick)
func _ready() -> void: call_deferred("run")
func run() -> void:
	var enabled := not "--without-autosave" in OS.get_cmdline_user_args()
	profile_stages = not "--without-stage-probe" in OS.get_cmdline_user_args()
	pan = "--pan" in OS.get_cmdline_user_args()
	var output := ""
	var source := ""
	var seconds := 120.0
	var speed := 1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--save="): source = arg.trim_prefix("--save=")
		elif arg.begins_with("--seconds="): seconds = maxf(30.0, float(arg.trim_prefix("--seconds=")))
		elif arg.begins_with("--speed="): speed = float(arg.trim_prefix("--speed="))
	if output.is_empty() or source.is_empty() or DisplayServer.get_name() == "headless": get_tree().quit(1); return
	if not speed in [1.0, 1.5, 2.0]: get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	Engine.max_fps = 60
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280,720)
	game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	get_tree().root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	if not game.load_game_from_path(source): get_tree().quit(1); return
	if not await Ready.wait_for_ready(get_tree(), game, 120000): get_tree().quit(1); return
	game.set_process(false)
	if enabled:
		game.autosave.enabled = true
		game.autosave.save_path = output.get_base_dir().path_join("profile-autosave.json")
		game._seed_autosave()
	game.game_controller.set_speed_multiplier(speed)
	game.game_controller.set_paused(false)
	if profile_stages: game.game_controller.set_performance_probe(probe)
	# Keep physical mouse/keyboard activity outside the controlled scenario.
	# The ordinary camera/input path otherwise lets an edge hover pan the test.
	game.match_preferences.values["scroll"] = 0.0
	game.set_process_unhandled_input(false)
	var camera_start: Vector2 = game.view_offset
	camera_origin = camera_start
	var initial: int = game.game_controller.tick_index
	game.set_process(true)
	started = Time.get_ticks_usec()
	previous = started
	measuring = true
	var requested := false
	while Time.get_ticks_usec() - started < seconds * 1000000.0:
		await get_tree().process_frame
		if enabled and not requested and Time.get_ticks_usec() - started >= 4000000:
			game.autosave.elapsed = game.autosave.next_save
			requested = true
	measuring = false
	game.game_controller.set_paused(true)
	game.set_process(false)
	var summaries := {}
	for phase in phases: summaries[phase] = BaseProbe.summarize(phases[phase])
	var frame_summary := BaseProbe.summarize(frames)
	var captures: Array = probe.samples_by_metric.get("presentation.ai.capture_frame", [])
	var capture_summary := BaseProbe.summarize(captures)
	var progress := float(game.game_controller.tick_index - initial) / (seconds * 20.0 * speed)
	var passed: bool = game.autosave.last_error.is_empty() and progress >= 0.9 and (not enabled or not completed.is_empty())
	# Preparation now owns a rendered frame when it exhausts its 16 ms budget;
	# a whole fixed tick is deferred. Allow one indivisible preparation portion
	# to overrun, while retaining the same actual whole-frame/rate criteria.
	var smooth: bool = int(frame_summary["over_100ms"]) == 0 and int(frame_summary["p95"]) < 40000 and (not profile_stages or int(capture_summary["max"]) < 32000)
	var result := {"passed": passed, "smooth": smooth, "release": not OS.is_debug_build(), "autosave": enabled, "seconds": seconds, "frame_us": frame_summary, "phases": summaries, "ai_capture_frame_us": capture_summary, "initial_tick": initial, "final_tick": game.game_controller.tick_index, "speed_ratio": progress, "completed_autosaves": completed, "worker_pool_shared": game.autosave.worker_pool_shared, "slow": slow, "probe": probe.report(), "memory_peak": memory_peak, "capture_us": capture_peak, "error": game.autosave.last_error}
	result["game_speed"] = speed
	result["profile_stages"] = profile_stages
	result["ai_capture_limit_us"] = 32000
	if not profile_stages: result["ai_capture_frame_us"] = null
	result["camera_pan"] = pan
	result["camera_start"] = [camera_start.x, camera_start.y]
	result["camera_end"] = [game.view_offset.x, game.view_offset.y]
	game.free()
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("MATCH_SMOOTHNESS ", JSON.stringify(frame_summary), " smooth=", smooth)
	get_tree().quit(0 if passed else 1)
