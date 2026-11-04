extends Node
const BaseProbe := preload("res://scripts/performance_probe.gd")
const Ready := preload("res://tests/support/match_ready.gd")
class FrameProbe extends BaseProbe:
	var metrics: Dictionary = {}
	func observe_microseconds(metric: String, us: int) -> void:
		super.observe_microseconds(metric, us)
		metrics[metric] = int(metrics.get(metric, 0)) + us
class ProfileGame:
	extends "res://main.gd"
	func _can_use_simulation_owner() -> bool:
		if game_controller == null: return false
		var previous_probe = game_controller.performance_probe
		game_controller.performance_probe = null
		var allowed: bool = super._can_use_simulation_owner()
		game_controller.performance_probe = previous_probe
		return allowed
class InstrumentedOwner:
	extends "res://scripts/simulation_owner.gd"
	const Probe := preload("res://scripts/performance_probe.gd")
	var measurement_enabled := false
	var measurements := Probe.new(40000)
	var measured_controller
	var previous_probe
	func submit(controller,runtime,delta: float,player: int,enemy: int,frame: int) -> bool:
		if pending: return false
		if measurement_enabled:
			measured_controller=controller
			previous_probe=controller.performance_probe
			controller.set_performance_probe(measurements)
		var accepted: bool=super.submit(controller,runtime,delta,player,enemy,frame)
		if not accepted: _restore_probe()
		return accepted
	func take() -> Dictionary:
		var result: Dictionary=super.take()
		_restore_probe()
		return result
	func _restore_probe() -> void:
		if measured_controller!=null:
			measured_controller.set_performance_probe(previous_probe)
			measured_controller=null
			previous_probe=null
var owner_stages := false
var visual_hold := false
var game
var log_slow_frames := false
var probe := FrameProbe.new(16000)
var measuring := false
var previous := 0
var started := 0
const MAX_FRAME_SAMPLES := 120000
var frames: Array = []
var slow: Array = []
var timeline: Array = []
var memory_peak := 0
var previous_anchors: Dictionary = {}
var previous_animations: Dictionary = {}
var previous_pose_pairs: Dictionary = {}
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
		row.merge(motion_sample())
		row.merge({"seconds":float(now-started)/1000000.0,"frame_us":elapsed,"autosave":game.autosave.busy})
		timeline.append(row)
		if elapsed > 35000:
			var stages: Array = []
			for key in probe.metrics:
				if probe.metrics[key] > 1000: stages.append({"name": key, "us": probe.metrics[key]})
			stages.sort_custom(func(a,b): return a["us"] > b["us"])
			var entry := {"seconds": float(now-started)/1000000.0,"tick":row["tick"],"frame_us":elapsed,"busy":game.autosave.busy,"stages":stages.slice(0,20)}
			slow.append(entry)
			# Console/file flushing can itself create the next slow frame on a
			# busy disk. Keep samples in memory unless live logging is requested.
			if elapsed > 80000 and log_slow_frames: print("SLOW ", JSON.stringify(entry))
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
		elif arg == "--owner-stages": owner_stages = true
		elif arg == "--visual-hold": visual_hold = true
		elif arg == "--no-autosave": enabled = false
		elif arg == "--no-ai": disable_ai = true
		elif arg == "--uncapped": uncapped = true
		elif arg == "--no-probe": no_probe = true
		elif arg == "--log-slow-frames": log_slow_frames = true
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
	if owner_stages:
		game.set_script(ProfileGame)
		game.simulation_owner = InstrumentedOwner.new()
		game.simulation_owner.measurement_enabled = true
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	get_tree().root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(),game,120000): get_tree().quit(1); return
	game.autosave.enabled = enabled
	game.autosave.save_path = output + ".autosave.json"
	if not game.load_game_from_path(save): push_error(game.last_save_error); get_tree().quit(1); return
	if not await Ready.wait_for_ready(get_tree(),game,120000): get_tree().quit(1); return
	if owner_stages: game.simulation_owner.measurements.clear()
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
	var result := {"release":not OS.is_debug_build(),"uncapped":uncapped,"frame_limit":Engine.max_fps,"default_frame_limit":default_frame_limit,"simulation_owner_started":game.simulation_owner.thread.is_started(),"probe_enabled":not no_probe,"resolution":[get_window().size.x,get_window().size.y],"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"native_visibility_deltas":game.simulation_world.get_fog_of_war().native_kernel.has_method("apply_source_deltas"),"native_visibility_sources":game.simulation_world.get_fog_of_war().native_kernel.has_method("collect_source_deltas"),"native_controls":ClassDB.instantiate("RoRReadModelKernel").has_method("project_control"),"native_terrain_chunks":ClassDB.instantiate("RoRTerrainKernel").has_method("split_mesh_arrays"),"native_resource_bounds":ClassDB.instantiate("RoRReadModelKernel").has_method("known_resources_in_bounds"),"terrain_peak_chunk_upload_us":game.terrain_canvas.peak_chunk_upload_us,"terrain_mesh_metrics":game.terrain_canvas.last_mesh_build_metrics.duplicate(),"native_resource_buckets":ClassDB.instantiate("RoRReadModelKernel").has_method("build_resource_buckets"),"native_walkability_masks":ClassDB.instantiate("RoRReadModelKernel").has_method("walkability_mask"),"save":save,"autosave":enabled,"pan":pan,"seconds":seconds,"speed":speed,"frame_us":BaseProbe.summarize(frames),"steady_frame_us":BaseProbe.summarize(steady.map(func(row):return row["frame_us"])),"simulation_pauses":simulation_pause_summary(steady),"initial_tick":initial,"final_tick":game.game_controller.tick_index,"slow":slow,"timeline":timeline,"probe":probe.report(),"memory_peak":memory_peak if memory_peak > 0 else null,"capture_us":game.autosave.last_capture_us,"saved_tick":game.autosave.last_tick,"autosave_error":game.autosave.last_error, "autosave_process_isolated":game.autosave.worker_process_isolated}
	result["owner_stage_probe_enabled"] = owner_stages
	result["owner_stage_probe"] = game.simulation_owner.measurements.report() if owner_stages else {}
	result["motion"] = motion_summary(steady)
	result["autosave_initialization_us"] = game.autosave.last_initialization_us
	result["autosave_worker_us"] = game.autosave.last_worker_us
	result["slow_frame_logging"] = log_slow_frames
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: push_error("Cannot write frame report"); game.free(); get_tree().quit(1); return
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("RESULT ",JSON.stringify(result["frame_us"]))
	await RenderingServer.frame_post_draw
	var screenshot := get_viewport().get_texture().get_image()
	screenshot.save_png(output + ".png")
	if visual_hold:
		# Recording happens after the measured interval in the same real match.
		game.game_controller.set_paused(false)
		game.set_process(true)
		get_window().grab_focus()
		var ready_file := FileAccess.open(output + ".visual-ready", FileAccess.WRITE)
		ready_file.store_string("performance measurement finished\n")
		ready_file.close()
		var hold_until := Time.get_ticks_usec() + 30000000
		while Time.get_ticks_usec() < hold_until: await get_tree().process_frame
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


func motion_sample() -> Dictionary:
	var moving:=0
	var stationary:=0
	var stop_pixels:=0.0
	var next_animations: Dictionary={}
	var reversed:=0
	var pose_pairs: Dictionary={}
	var present: Dictionary={}
	# Retained render items belong to the main thread and contain the actual
	# interpolated world anchors used by the last draw. Do not read live actors.
	for item in game.cached_world_drawables:
		if String(item.get("kind",""))!="unit": continue
		var data: Dictionary=item.get("data",{})
		if int(data.get("team",0))!=game.local_player_team: continue
		var id:=int(item["stable_id"])
		var position:=Vector2(item["world_anchor"])
		present[id]=position
		var animation:=String(data.get("anim_state",""))
		next_animations[id]=animation
		if previous_anchors.has(id) and previous_animations.get(id,"") in ["Move","Carry"] and animation not in ["Move","Carry"]:
			stop_pixels=maxf(stop_pixels,game.world_to_screen(Vector2(previous_anchors[id])).distance_to(game.world_to_screen(position)))
		var pair: Array=[Vector2(data.get("previous_pos",data["pos"])),Vector2(data["pos"])]
		pose_pairs[id]=pair
		if Vector2(data.get("previous_pos",data["pos"])).distance_squared_to(Vector2(data["pos"]))<0.00000001: continue
		if String(data.get("anim_state","")) not in ["Move","Carry"]: continue
		moving+=1
		if previous_anchors.has(id):
			var shown_delta:=position-Vector2(previous_anchors[id])
			if shown_delta.length_squared()<0.00000001: stationary+=1
			if previous_pose_pairs.get(id)==pair and shown_delta.dot(Vector2(pair[1])-Vector2(pair[0])) < -0.00000001: reversed+=1
	previous_anchors=present
	previous_pose_pairs=pose_pairs
	previous_animations=next_animations
	return {"moving_units":moving,"stationary_moving_units":stationary,"rewinding_moving_units":reversed,"stop_correction_millipixels":roundi(stop_pixels*1000.0)}

func motion_summary(rows: Array) -> Dictionary:
	var moving_samples:=0
	var stalled_samples:=0
	var reversed_samples:=0
	var all_still_us:=0
	var durations: Array=[]
	var stop_corrections: Array=[]
	for row in rows:
		if int(row.get("stop_correction_millipixels",0))>0: stop_corrections.append(int(row["stop_correction_millipixels"]))
		moving_samples+=int(row.get("moving_units",0))
		stalled_samples+=int(row.get("stationary_moving_units",0))
		reversed_samples+=int(row.get("rewinding_moving_units",0))
		if int(row.get("moving_units",0))>=2 and int(row.get("moving_units",0))==int(row.get("stationary_moving_units",0)):
			all_still_us+=int(row["frame_us"])
		elif all_still_us>0:
			durations.append(all_still_us);all_still_us=0
	if all_still_us>0:durations.append(all_still_us)
	return {"moving_actor_frame_samples":moving_samples,"stationary_moving_actor_frame_samples":stalled_samples,"rewinding_moving_actor_frame_samples":reversed_samples,"all_moving_still_us":BaseProbe.summarize(durations),"stop_correction_millipixels":BaseProbe.summarize(stop_corrections)}
