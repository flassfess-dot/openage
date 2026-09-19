extends SceneTree

# Runs the real main scene in the root game window, drives the same input
# adapter used by a player and records end-to-end frame pacing. The script is
# intentionally exported with the project so it can be launched from the
# packaged PCK rather than from an editor-only scene.

const MatchRegistry := preload("res://scripts/match_registry.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const DEFAULT_SIZE := Vector2i(1280, 720)
const DEFAULT_OUTPUT := "user://live-packaged-probe/report.json"
const DEFAULT_MATCH := "prototype_skirmish"
const WARMUP_FRAMES := 30
const IDLE_FRAMES := 90
const MOVEMENT_FRAMES := 150
const PAN_FRAMES := 90

var game: Node
var output_directory := ""
var frame_post_draw_received := false
var boot_metrics: Dictionary = {}


func _initialize() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var output_path := _absolute_path(String(options["output"]))
	output_directory = output_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(output_directory)

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(options["size"])
	root.size = options["size"]
	await process_frame

	var boot_started := Time.get_ticks_usec()
	var entry := MatchRegistry.resolve(String(options["match"]))
	if entry.is_empty() or not bool(entry.get("available", false)):
		push_error("Live packaged probe cannot resolve match: %s" % options["match"])
		quit(1)
		return
	var scene_load_started := Time.get_ticks_usec()
	var scene: PackedScene = load("res://main.tscn")
	boot_metrics["scene_load_microseconds"] = Time.get_ticks_usec() - scene_load_started
	if scene == null:
		push_error("Live packaged probe cannot load main.tscn")
		quit(1)
		return
	var instantiate_started := Time.get_ticks_usec()
	game = scene.instantiate()
	boot_metrics["scene_instantiate_microseconds"] = Time.get_ticks_usec() - instantiate_started
	game.match_path = String(entry["path"])
	var attach_started := Time.get_ticks_usec()
	root.add_child(game)
	boot_metrics["scene_attach_ready_microseconds"] = Time.get_ticks_usec() - attach_started
	current_scene = game
	await process_frame
	boot_metrics["first_frame_microseconds"] = Time.get_ticks_usec() - boot_started
	var overlay_state := _dismiss_blocking_overlays()

	for _frame in range(WARMUP_FRAMES):
		await process_frame
	boot_metrics["warm_ready_microseconds"] = Time.get_ticks_usec() - boot_started
	var subsystem_probe = PerformanceProbe.new(IDLE_FRAMES + MOVEMENT_FRAMES + PAN_FRAMES + 64)
	game.game_controller.set_performance_probe(subsystem_probe)

	var result := {
		"schema_version": 1,
		"kind": "live_packaged_game_probe",
		"match": String(options["match"]),
		"viewport_size": [int(options["size"].x), int(options["size"].y)],
		"boot": boot_metrics,
		"overlays": overlay_state,
		"stages": {},
		"captures": {},
	}
	result["captures"]["initial"] = await _capture("01-initial.png")
	result["stages"]["idle"] = await _measure_frames(IDLE_FRAMES)

	var selection := _select_local_group()
	result["selection"] = selection
	for _frame in range(3):
		await process_frame
	result["captures"]["selected"] = await _capture("02-selected.png")

	var command := _issue_formation_move()
	result["command"] = command
	await process_frame
	result["captures"]["command"] = await _capture("03-command.png")
	result["stages"]["movement"] = await _measure_frames(MOVEMENT_FRAMES)
	result["captures"]["movement"] = await _capture("04-movement.png")

	_begin_middle_pan()
	result["stages"]["pan"] = await _measure_frames(PAN_FRAMES, true)
	_end_middle_pan()
	result["captures"]["pan"] = await _capture("05-pan.png")

	result["subsystems"] = subsystem_probe.report()
	result["snapshot_variants"] = _measure_snapshot_variants()
	result["ticks"] = int(game.game_controller.tick_index)
	result["presentation_revision"] = int(game.presentation_revision)
	result["world"] = {
		"units": game.simulation_world.get_units().size(),
		"buildings": game.simulation_world.get_buildings().size(),
		"resources": game.simulation_world.get_resources().size(),
	}
	result["process"] = {
		"os": OS.get_name(),
		"processor": OS.get_processor_name(),
		"logical_processors": OS.get_processor_count(),
		"video_adapter": RenderingServer.get_video_adapter_name(),
		"video_vendor": RenderingServer.get_video_adapter_vendor(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"memory_static_max_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
	}

	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Live packaged probe cannot write %s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("Live packaged probe saved: %s" % output_path)
	quit(0)


func _measure_snapshot_variants() -> Dictionary:
	var bounds: Rect2i = game.visible_tile_bounds(8)
	var base_options := {
		"include_navigation": false,
		"include_build_sites": false,
		"include_overview": false,
		"compact_render_entities": true,
		"entity_bounds": Rect2(Vector2(bounds.position), Vector2(bounds.size)),
		"always_include_entity_ids": game.player_control_state.selected_ids(),
		"command_option_entity_ids": game.player_control_state.selected_ids(),
	}
	var variants := {
		"full": {},
		"without_fog": {"include_fog_cells": false},
		"without_scenario": {"include_scenario": false},
		"without_projectiles": {"include_projectiles": false},
		"minimal": {"include_fog_cells": false, "include_scenario": false, "include_projectiles": false},
	}
	var result: Dictionary = {}
	for name in variants:
		var options: Dictionary = base_options.duplicate(true)
		options.merge(variants[name], true)
		var samples: Array[int] = []
		for _sample in range(4):
			var started := Time.get_ticks_usec()
			SimulationSnapshot.presentation(game.simulation_world, game.game_controller.tick_index, game.PLAYER_TEAM, options)
			samples.append(Time.get_ticks_usec() - started)
		result[name] = PerformanceProbe.summarize(samples)
	return result


func _measure_frames(count: int, pan: bool = false) -> Dictionary:
	var frame_wall: Array[int] = []
	var process_times: Array[int] = []
	var physics_times: Array[int] = []
	var draw_calls: Array[int] = []
	var objects: Array[int] = []
	var primitives: Array[int] = []
	var fps: Array[int] = []
	var start_tick := int(game.game_controller.tick_index)
	var start_revision := int(game.presentation_revision)
	var previous := Time.get_ticks_usec()
	for index in range(count):
		if pan:
			_drag_middle_pan(index)
		await process_frame
		var now := Time.get_ticks_usec()
		frame_wall.append(now - previous)
		previous = now
		process_times.append(roundi(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000000.0))
		physics_times.append(roundi(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000000.0))
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		fps.append(Engine.get_frames_per_second())
	return {
		"frames": count,
		"fixed_ticks": int(game.game_controller.tick_index) - start_tick,
		"presentation_revisions": int(game.presentation_revision) - start_revision,
		"frame_wall_microseconds": PerformanceProbe.summarize(frame_wall),
		"process_microseconds": PerformanceProbe.summarize(process_times),
		"physics_microseconds": PerformanceProbe.summarize(physics_times),
		"draw_calls": PerformanceProbe.summarize(draw_calls),
		"objects": PerformanceProbe.summarize(objects),
		"primitives": PerformanceProbe.summarize(primitives),
		"fps": PerformanceProbe.summarize(fps),
	}


func _select_local_group() -> Dictionary:
	var candidates: Array[Dictionary] = []
	var gameplay_rect := Rect2(Vector2(8.0, 24.0), Vector2(root.size.x - 16, root.size.y - 164))
	for unit_value in game.simulation_world.get_units():
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) != int(game.PLAYER_TEAM) or float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var screen: Vector2 = game.world_to_screen(Vector2(unit.get("pos", Vector2.ZERO)))
		if gameplay_rect.has_point(screen):
			candidates.append({"id": int(unit.get("id", -1)), "screen": screen})
	candidates.sort_custom(func(left, right):
		var left_screen: Vector2 = left["screen"]
		var right_screen: Vector2 = right["screen"]
		if not is_equal_approx(left_screen.y, right_screen.y):
			return left_screen.y < right_screen.y
		return int(left["id"]) < int(right["id"])
	)
	var points: Array[Vector2] = []
	var ids: Array[int] = []
	for candidate in candidates.slice(0, mini(8, candidates.size())):
		points.append(Vector2(candidate["screen"]))
		ids.append(int(candidate["id"]))
	if points.is_empty():
		return {"attempted_ids": [], "selected_ids": []}
	var minimum := points[0]
	var maximum := points[0]
	for point in points:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	_mouse_button(minimum - Vector2(14.0, 14.0), MOUSE_BUTTON_LEFT, true)
	_mouse_motion(maximum + Vector2(14.0, 14.0), MOUSE_BUTTON_MASK_LEFT)
	_mouse_button(maximum + Vector2(14.0, 14.0), MOUSE_BUTTON_LEFT, false)
	var selection_method := "input_drag"
	if game.player_control_state.selected_ids().is_empty():
		# The packaged probe feeds input directly into the game root rather than
		# through an OS window. Re-run the same rectangle through the public game
		# selection path when the synthetic drag is swallowed by viewport focus.
		game.finish_selection(minimum - Vector2(14.0, 14.0), maximum + Vector2(14.0, 14.0))
		selection_method = "selection_api"
	if game.player_control_state.selected_ids().is_empty():
		# Keep the movement benchmark useful even if a future input-layer change
		# breaks synthetic pointer delivery. The report makes this fallback
		# explicit so it cannot be mistaken for a successful UI interaction.
		game.player_control_state.replace_or_add(ids, false)
		game.refresh_hud_model()
		selection_method = "state_fallback"
	return {
		"visible_candidates": candidates.size(),
		"attempted_ids": ids,
		"selected_ids": game.player_control_state.selected_ids(),
		"selection_method": selection_method,
	}


func _dismiss_blocking_overlays() -> Dictionary:
	var result := {
		"scenario_was_blocking": false,
		"scenario_dismissed": false,
		"hud_modal_was_blocking": false,
	}
	if game.scenario_overlay != null and game.scenario_overlay.is_blocking():
		result["scenario_was_blocking"] = true
		if game.scenario_overlay.briefing_layer != null and game.scenario_overlay.briefing_layer.visible:
			game.scenario_overlay._dismiss_briefing()
			result["scenario_dismissed"] = not game.scenario_overlay.is_blocking()
	if game.hud_modal_overlay != null and game.hud_modal_overlay.is_blocking():
		result["hud_modal_was_blocking"] = true
		game._close_hud_modal()
	return result


func _issue_formation_move() -> Dictionary:
	_key(KEY_F5)
	var selected: Array = []
	for selected_id_value in game.player_control_state.selected_ids():
		var entity = game.simulation_world.find_combat_target(int(selected_id_value))
		if entity != null:
			selected.append(entity)
	if selected.is_empty():
		return {"accepted": false, "reason": "empty_selection"}
	var center := Vector2.ZERO
	for entity_value in selected:
		center += Vector2(entity_value.get("pos", Vector2.ZERO))
	center /= float(selected.size())
	var destination_world := center + Vector2(3.5, 2.0)
	var destination_screen: Vector2 = game.world_to_screen(destination_world)
	var direction_screen := destination_screen + Vector2(62.0, -10.0)
	_mouse_button(destination_screen, MOUSE_BUTTON_RIGHT, true)
	_mouse_motion(direction_screen, MOUSE_BUTTON_MASK_RIGHT)
	_mouse_button(direction_screen, MOUSE_BUTTON_RIGHT, false)
	return {
		"accepted": true,
		"selected_ids": game.player_control_state.selected_ids(),
		"destination_world": [destination_world.x, destination_world.y],
		"destination_screen": [destination_screen.x, destination_screen.y],
	}


func _begin_middle_pan() -> void:
	var start := Vector2(root.size) * Vector2(0.55, 0.46)
	_mouse_button(start, MOUSE_BUTTON_MIDDLE, true)


func _drag_middle_pan(index: int) -> void:
	var start := Vector2(root.size) * Vector2(0.55, 0.46)
	var offset := Vector2(float(index + 1) * 1.2, sin(float(index) * 0.15) * 18.0)
	_mouse_motion(start + offset, MOUSE_BUTTON_MASK_MIDDLE)


func _end_middle_pan() -> void:
	var end := Vector2(root.size) * Vector2(0.55, 0.46) + Vector2(float(PAN_FRAMES) * 1.2, 0.0)
	_mouse_button(end, MOUSE_BUTTON_MIDDLE, false)


func _mouse_button(position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	game._unhandled_input(event)


func _mouse_motion(position: Vector2, button_mask: int) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	event.button_mask = button_mask
	game._unhandled_input(event)


func _key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = true
	game._unhandled_input(event)


func _capture(filename: String) -> String:
	frame_post_draw_received = false
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)
	game.queue_redraw()
	if game.terrain_canvas != null:
		game.terrain_canvas.queue_redraw()
	for _attempt in range(12):
		await process_frame
		if frame_post_draw_received:
			break
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	var path := output_directory.path_join(filename)
	var texture := root.get_texture()
	if texture == null:
		return "unavailable:no_root_texture"
	var image := texture.get_image()
	if image == null:
		return "unavailable:no_root_image"
	var error := image.save_png(path)
	return path if error == OK else "error:%s" % error_string(error)


func _on_frame_post_draw() -> void:
	frame_post_draw_received = true


func _options(arguments: PackedStringArray) -> Dictionary:
	var result := {"size": DEFAULT_SIZE, "output": DEFAULT_OUTPUT, "match": DEFAULT_MATCH}
	for argument_value in arguments:
		var argument := String(argument_value)
		if argument.begins_with("--size="):
			result["size"] = _parse_size(argument.trim_prefix("--size="))
		elif argument.begins_with("--output="):
			result["output"] = argument.trim_prefix("--output=")
		elif argument.begins_with("--match="):
			result["match"] = argument.trim_prefix("--match=")
	return result


func _parse_size(value: String) -> Vector2i:
	var parts := value.to_lower().split("x", false)
	if parts.size() != 2:
		return DEFAULT_SIZE
	var parsed := Vector2i(int(parts[0]), int(parts[1]))
	return parsed if parsed.x >= 640 and parsed.y >= 480 else DEFAULT_SIZE


func _absolute_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path
