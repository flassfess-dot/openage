extends Node
const BaseProbe := preload("res://scripts/performance_probe.gd")
const Ready := preload("res://tests/support/match_ready.gd")
class FrameProbe extends BaseProbe:
	var metrics: Dictionary = {}
	func observe_microseconds(metric: String, us: int) -> void:
		super.observe_microseconds(metric, us)
		metrics[metric] = int(metrics.get(metric, 0)) + us
var game
var probe := FrameProbe.new(16000)
var measuring := false
var previous := 0
var started := 0
const MAX_FRAME_SAMPLES := 120000
var frames: Array = []
var slow: Array = []
var timeline: Array = []
var memory_peak := 0
func _process(_delta: float) -> void:
	if not measuring: return
	var now := Time.get_ticks_usec()
	if previous > 0:
		var elapsed := now - previous
		if frames.size() >= MAX_FRAME_SAMPLES:
			push_error("Frame probe sample limit reached; use a shorter duration")
			measuring=false;game.free();get_tree().quit(1);return
		frames.append(elapsed)
		var row: Dictionary = game.simulation_frame_state()
		row.merge({"seconds":float(now-started)/1000000.0,"frame_us":elapsed,"autosave":game.autosave.busy})
		timeline.append(row)
		if elapsed > 35000:
			var stages: Array = []
			for key in probe.metrics:
				if probe.metrics[key] > 1000: stages.append({"name": key, "us": probe.metrics[key]})
			stages.sort_custom(func(a,b): return a["us"] > b["us"])
			var entry := {"seconds": float(now-started)/1000000.0,"tick":row["tick"],"frame_us":elapsed,"busy":game.autosave.busy,"stages":stages.slice(0,20)}
			slow.append(entry)
			if elapsed > 80000: print("SLOW ", JSON.stringify(entry))
	probe.metrics.clear()
	previous = now
	memory_peak = maxi(memory_peak, int(Performance.get_monitor(Performance.MEMORY_STATIC)))
func _ready() -> void: call_deferred("run")
func run() -> void:
	var output := ""
	var save := ""
	var seconds := 90.0
	var pan := false
	var enabled := true
	var disable_ai := false
	var uncapped := false
	var no_probe := false
	var frame_limit := 60
	var default_frame_limit := false
	var size := Vector2i(1280, 720)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--save="): save = arg.trim_prefix("--save=")
		elif arg.begins_with("--seconds="): seconds = float(arg.trim_prefix("--seconds="))
		elif arg == "--pan": pan = true
		elif arg == "--no-autosave": enabled = false
		elif arg == "--no-ai": disable_ai = true
		elif arg == "--uncapped": uncapped = true
		elif arg == "--no-probe": no_probe = true
		elif arg == "--default-frame-limit": default_frame_limit = true
		elif arg.begins_with("--frame-limit="): frame_limit = clampi(int(arg.trim_prefix("--frame-limit=")),1,240)
		elif arg.begins_with("--size="):
			var parts := arg.trim_prefix("--size=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
	if output.is_empty() or save.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		push_error("Pass a save, a new output path and a graphical runtime")
		get_tree().quit(1); return
	if not default_frame_limit: Engine.max_fps = 0 if uncapped else frame_limit
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = size
	game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	get_tree().root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(),game,120000): get_tree().quit(1); return
	game.autosave.enabled = enabled
	game.autosave.save_path = output + ".autosave.json"
	if not game.load_game_from_path(save): push_error(game.last_save_error); get_tree().quit(1); return
	if not await Ready.wait_for_ready(get_tree(),game,120000): get_tree().quit(1); return
	if disable_ai:
		game.ai_decision_queue.cancel(game.task_coordinator)
		game.ai_players.clear()
	game.game_controller.set_paused(false)
	game.game_controller.set_performance_probe(null if no_probe else probe)
	var initial: int = game.game_controller.tick_index
	var speed: float = game.game_controller.get_speed_multiplier()
	var offset: Vector2 = game.view_offset
	started = Time.get_ticks_usec()
	previous = started
	measuring = true
	print("READY tick=",initial," size=",game.map_size," units=",game.simulation_world.units.size()," resources=",game.simulation_world.resource_nodes.size()," speed=",speed," release=",not OS.is_debug_build())
	while Time.get_ticks_usec()-started < int(seconds*1000000):
		await get_tree().process_frame
		if pan:
			var t := float(Time.get_ticks_usec()-started)/1000000.0
			game.view_offset = offset + Vector2(sin(t*0.4)*480.0,cos(t*0.3)*240.0)
	measuring = false
	game.join_simulation_owner()
	game.game_controller.set_paused(true)
	game.set_process(false)
	var steady := timeline.filter(func(row):return row["seconds"]>=15.0)
	var result := {"release":not OS.is_debug_build(),"uncapped":uncapped,"frame_limit":Engine.max_fps,"default_frame_limit":default_frame_limit,"simulation_owner_started":game.simulation_owner.thread.is_started(),"probe_enabled":not no_probe,"resolution":[get_window().size.x,get_window().size.y],"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"native_visibility_deltas":game.simulation_world.get_fog_of_war().native_kernel.has_method("apply_source_deltas"),"native_visibility_sources":game.simulation_world.get_fog_of_war().native_kernel.has_method("collect_source_deltas"),"native_controls":ClassDB.instantiate("RoRReadModelKernel").has_method("project_control"),"native_terrain_chunks":ClassDB.instantiate("RoRTerrainKernel").has_method("split_mesh_arrays"),"native_resource_bounds":ClassDB.instantiate("RoRReadModelKernel").has_method("known_resources_in_bounds"),"terrain_peak_chunk_upload_us":game.terrain_canvas.peak_chunk_upload_us,"terrain_mesh_metrics":game.terrain_canvas.last_mesh_build_metrics.duplicate(),"native_resource_buckets":ClassDB.instantiate("RoRReadModelKernel").has_method("build_resource_buckets"),"native_walkability_masks":ClassDB.instantiate("RoRReadModelKernel").has_method("walkability_mask"),"save":save,"autosave":enabled,"pan":pan,"seconds":seconds,"speed":speed,"frame_us":BaseProbe.summarize(frames),"steady_frame_us":BaseProbe.summarize(steady.map(func(row):return row["frame_us"])),"simulation_pauses":simulation_pause_summary(steady),"initial_tick":initial,"final_tick":game.game_controller.tick_index,"slow":slow,"timeline":timeline,"probe":probe.report(),"memory_peak":memory_peak if memory_peak > 0 else null,"capture_us":game.autosave.last_capture_us,"saved_tick":game.autosave.last_tick,"autosave_error":game.autosave.last_error}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write frame report"); game.free(); get_tree().quit(1); return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("RESULT ",JSON.stringify(result["frame_us"]))
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png(output + ".png")
	game.free()
	get_tree().quit(0)


func simulation_pause_summary(rows: Array) -> Dictionary:
	var waits: Array = []
	var gaps: Array = []
	var held := 0
	var previous_tick := -1
	var previous_advance := 0.0
	for row in rows:
		if row["waiting"]: held += int(row["frame_us"])
		elif held > 0: waits.append(held);held=0
		if int(row["tick"]) != previous_tick:
			if previous_tick >= 0: gaps.append(roundi((float(row["seconds"])-previous_advance)*1000000.0))
			previous_tick=int(row["tick"])
			previous_advance=float(row["seconds"])
	if held > 0: waits.append(held)
	var result := {"waits_us":BaseProbe.summarize(waits),"tick_gaps_us":BaseProbe.summarize(gaps),"total_wait_us":0}
	for value in waits: result["total_wait_us"] += int(value)
	return result
