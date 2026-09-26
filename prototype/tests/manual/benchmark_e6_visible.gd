extends SceneTree

# Manual E6 presentation benchmark. It boots the real main scene, keeps the
# complete authoritative population, fixes the camera and measures snapshot,
# render-queue preparation and actual rendered frames independently.

const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")

const DEFAULT_SIZE := Vector2i(1024, 768)
const DEFAULT_OUTPUT := "res://qa/performance/e6-visible.json"
const MAP_SIDE := 400
const HUD_TOP := 20.0
const HUD_BOTTOM := 126.0

var frame_post_draw_received := false


func _initialize() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var result := await _run_case(options)
	var output_path := ProjectSettings.globalize_path(String(options["output"]))
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("E6 visible benchmark cannot write %s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("E6 visible case=%s viewport=%dx%d population=%d on_screen=%d frame_p95_us=%d draw_calls_p95=%d output=%s" % [
		String(result["case"]),
		int(result["viewport_size"][0]),
		int(result["viewport_size"][1]),
		int(result["world_units"]),
		int(result["screen_units"]),
		int(result["render_frame_microseconds"]["p95"]),
		int(result["draw_calls"]["p95"]),
		output_path,
	])
	quit(0)


func _run_case(options: Dictionary) -> Dictionary:
	var requested_size: Vector2i = options["size"]
	var units_per_player := int(options["units_per_player"])
	var visible_per_team := mini(units_per_player, int(options["visible_per_team"]))
	var definition := _match_definition(units_per_player, visible_per_team)
	var map_data := RandomMapGenerator.generate(definition)
	var viewport := SubViewport.new()
	viewport.size = requested_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = "benchmark://e6-visible/%d" % units_per_player
	game.match_definition_override = definition
	game.map_definition_override = map_data
	viewport.add_child(game)
	for _frame in range(8):
		await process_frame
	game.set_process(false)
	game.game_controller.advance_frame(0.05, 1, 2)
	game.view_zoom = 1.0
	game.center_initial_view()
	game.sync_world_state()
	game.queue_redraw()
	if game.terrain_canvas != null:
		game.terrain_canvas.queue_redraw()
	await _render_frame(game)

	var snapshot_times: Array[int] = []
	for _sample in range(int(options["preparation_samples"])):
		var started := Time.get_ticks_usec()
		game.sync_world_state()
		snapshot_times.append(Time.get_ticks_usec() - started)
	var snapshot_breakdown := _measure_snapshot_breakdown(game, int(options["preparation_samples"]))
	var sync_stage_breakdown := _measure_sync_stage_breakdown(game, int(options["preparation_samples"]))
	var drawable_times: Array[int] = []
	var drawables: Array = []
	for _sample in range(int(options["preparation_samples"])):
		var started := Time.get_ticks_usec()
		drawables = game.current_world_drawables()
		drawable_times.append(Time.get_ticks_usec() - started)

	for _frame in range(int(options["warmup_frames"])):
		await _render_frame(game)
	if not String(options["capture_png"]).is_empty():
		game.pending_build_kind = "house"
		game.input_adapter.pointer_position = Vector2(requested_size.x * 0.62, requested_size.y * 0.48)
		await _render_frame(game)
		var capture_path := ProjectSettings.globalize_path(String(options["capture_png"]))
		DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
		var capture_error := viewport.get_texture().get_image().save_png(capture_path)
		if capture_error != OK:
			push_error("E6 visible capture could not save %s: %d" % [capture_path, capture_error])
		game.pending_build_kind = ""
	var frame_times: Array[int] = []
	var draw_calls: Array[int] = []
	var objects_in_frame: Array[int] = []
	var primitives_in_frame: Array[int] = []
	for _frame in range(int(options["sample_frames"])):
		frame_times.append(await _render_frame(game))
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		objects_in_frame.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
		primitives_in_frame.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var pan_frame_times: Array[int] = []
	for _frame in range(int(options["sample_frames"])):
		game.view_offset += Vector2(8.0, 0.0)
		game._sync_terrain_canvas()
		pan_frame_times.append(await _render_frame(game))
	game.game_controller.set_speed_multiplier(1.0)
	var active_probe = PerformanceProbe.new(maxi(64, int(options["sample_frames"]) + 8))
	game.game_controller.set_performance_probe(active_probe)
	for _frame in range(int(options["warmup_frames"])):
		await _active_fixed_render_frame(game)
	active_probe.clear()
	var active_start_tick: int = game.game_controller.tick_index
	var active_start_revision: int = game.presentation_revision
	var active_frame_times: Array[int] = []
	for _frame in range(int(options["sample_frames"])):
		active_frame_times.append(await _active_fixed_render_frame(game))
	var active_end_tick: int = game.game_controller.tick_index
	var active_end_revision: int = game.presentation_revision

	var snapshot_units: Array = game.presentation_snapshot.get("units", [])
	var screen_unit_ids := _screen_unit_ids(game, snapshot_units, requested_size)
	var screen_drawables := _screen_drawable_count(game, drawables, requested_size)
	var result := {
		"schema_version": 1,
		"case": String(options["case"]),
		"viewport_size": [requested_size.x, requested_size.y],
		"map_size": [MAP_SIDE, MAP_SIDE],
		"players": 2,
		"units_per_player": units_per_player,
		"world_units": game.simulation_world.get_units().size(),
		"snapshot_units": snapshot_units.size(),
		"screen_units": screen_unit_ids.size(),
		"world_buildings": game.simulation_world.get_buildings().size(),
		"snapshot_buildings": game.presentation_snapshot.get("buildings", []).size(),
		"world_resources": game.simulation_world.get_resources().size(),
		"snapshot_resources": game.presentation_snapshot.get("resources", []).size(),
		"visible_tile_bounds": _rect_to_dictionary(game.visible_tile_bounds()),
		"render_drawables": drawables.size(),
		"screen_drawables": screen_drawables,
		"snapshot_microseconds": _summary(snapshot_times),
		"snapshot_breakdown_microseconds": snapshot_breakdown,
		"sync_stage_breakdown_microseconds": sync_stage_breakdown,
		"drawable_build_microseconds": _summary(drawable_times),
		"render_frame_microseconds": _summary(frame_times),
		"pan_frame_microseconds": _summary(pan_frame_times),
		"active_frame_microseconds": _summary(active_frame_times),
		"active_fixed_ticks": active_end_tick - active_start_tick,
		"active_presentation_revisions": active_end_revision - active_start_revision,
		"active_probe": active_probe.report(),
		"draw_calls": _summary(draw_calls),
		"objects_in_frame": _summary(objects_in_frame),
		"primitives_in_frame": _summary(primitives_in_frame),
		"process": {
			"os": OS.get_name(),
			"processor": OS.get_processor_name(),
			"logical_processors": OS.get_processor_count(),
			"video_adapter": RenderingServer.get_video_adapter_name(),
			"video_vendor": RenderingServer.get_video_adapter_vendor(),
			"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			"memory_static_max_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
			"video_memory_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
			"texture_memory_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
			"buffer_memory_bytes": int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)),
		},
	}
	game.free()
	viewport.free()
	return result


func _measure_snapshot_breakdown(game, samples: int) -> Dictionary:
	var bounds: Rect2i = game.visible_tile_bounds(8)
	var base_options := {
		"include_navigation": false,
		"include_build_sites": false,
		"include_overview": true,
		"compact_render_entities": true,
		"entity_bounds": Rect2(Vector2(bounds.position), Vector2(bounds.size)),
		"always_include_entity_ids": [],
		"command_option_entity_ids": [],
	}
	var variants := {
		"full": {},
		"without_fog": {"include_fog_cells": false},
		"without_overview": {"include_overview": false},
		"without_scenario": {"include_scenario": false},
		"minimal": {
			"include_fog_cells": false,
			"include_overview": false,
			"include_scenario": false,
			"include_projectiles": false,
		},
	}
	var result: Dictionary = {}
	for name in variants:
		var measured_options: Dictionary = base_options.duplicate(true)
		measured_options.merge(variants[name], true)
		var times: Array[int] = []
		for _sample in range(samples):
			var started := Time.get_ticks_usec()
			SimulationSnapshot.presentation(game.simulation_world, game.game_controller.tick_index, game.PLAYER_TEAM, measured_options)
			times.append(Time.get_ticks_usec() - started)
		result[name] = _summary(times)
	var fog_times: Array[int] = []
	for _sample in range(samples):
		var started := Time.get_ticks_usec()
		game.simulation_world.get_fog_of_war().snapshot(game.PLAYER_TEAM)
		fog_times.append(Time.get_ticks_usec() - started)
	result["fog_copy_only"] = _summary(fog_times)
	return result


func _measure_sync_stage_breakdown(game, samples: int) -> Dictionary:
	var visible_bounds: Rect2i = game.visible_tile_bounds()
	var environment_bounds := Rect2i(visible_bounds.position - Vector2i(2, 2), visible_bounds.size + Vector2i(4, 4))
	var result: Dictionary = {}
	var stages := {
		"visible_bounds": func(): game.visible_tile_bounds(8),
		"environment_query": func(): game.environment_presentation_field.query(environment_bounds),
		"selectable_ids": func(): game.selectable_player_ids(),
		"selection_prune": func(): game.player_control_state.prune(game.selectable_player_ids()),
		"terrain_mesh_rebuild": func(): game.terrain_canvas.invalidate_content(),
		"hud_model": func(): game.hud_view_model.build(game.presentation_snapshot, game.player_control_state.selected_ids(), game.formation, "ru"),
		"hud_controls": func(): game.hud_controls.set_view_model(game.hud_model),
		"scenario_overlay": func(): game.scenario_overlay.set_snapshot(game.presentation_snapshot),
		"modal_overlay": func(): game.hud_modal_overlay.set_snapshot(game.presentation_snapshot),
	}
	for name in stages:
		var times: Array[int] = []
		for _sample in range(samples):
			var started := Time.get_ticks_usec()
			stages[name].call()
			times.append(Time.get_ticks_usec() - started)
		result[name] = _summary(times)
	return result


func _render_frame(game) -> int:
	var started := Time.get_ticks_usec()
	frame_post_draw_received = false
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)
	game.queue_redraw()
	if game.terrain_canvas != null:
		game.terrain_canvas.queue_redraw()
	for _attempt in range(12):
		await process_frame
		if frame_post_draw_received:
			return Time.get_ticks_usec() - started
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	return -1


func _active_fixed_render_frame(game) -> int:
	var started := Time.get_ticks_usec()
	game.game_controller.advance_frame(0.05, game.PLAYER_TEAM, game.ENEMY_TEAM)
	game.sync_world_state(false)
	game.process_presentation_events()
	frame_post_draw_received = false
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw, CONNECT_ONE_SHOT)
	game.queue_redraw()
	if game.terrain_canvas != null:
		game.terrain_canvas.queue_redraw()
	for _attempt in range(12):
		await process_frame
		if frame_post_draw_received:
			return Time.get_ticks_usec() - started
	if RenderingServer.frame_post_draw.is_connected(_on_frame_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_frame_post_draw)
	return -1


func _on_frame_post_draw() -> void:
	frame_post_draw_received = true


func _match_definition(units_per_player: int, visible_per_team: int) -> Dictionary:
	var center := Vector2(MAP_SIDE * 0.5, MAP_SIDE * 0.5)
	var entities: Array = []
	for team in [1, 2]:
		for index in range(units_per_player):
			var position := _visible_unit_position(team, index, visible_per_team, center)
			if index >= visible_per_team:
				position = _reserve_unit_position(team, index - visible_per_team, MAP_SIDE)
			entities.append({
				"category": "unit",
				"team": team,
				"kind": "clubman" if index % 4 != 0 else "villager",
				"position": position,
			})
	for team in [1, 2]:
		var side := -1.0 if team == 1 else 1.0
		for index in range(4):
			entities.append({
				"category": "building",
				"team": team,
				"kind": "barracks" if index % 2 == 0 else "house",
				"position": center + Vector2(side * (15.0 + index * 3.5), -8.0 + index * 5.0),
			})
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		entities.append({
			"category": "resource",
			"kind": "tree" if index % 3 != 0 else "stone_mine",
			"position": center + Vector2(cos(angle) * 24.0, sin(angle) * 18.0),
			"amount": 500,
			"placement_validated": true,
		})
	return {
		"schema_version": 1,
		"valid": true,
		"errors": [],
		"id": "e6_visible_%d" % units_per_player,
		"title": "E6 visible benchmark",
		"start_message": "E6 visible benchmark",
		"local_team": 1,
		"map": {
			"size": Vector2i(MAP_SIDE, MAP_SIDE),
			"seed": 60221,
			"generator": {
				"type": "coastal_land",
				"water_border": {"left": 0, "top": 0, "right": 0, "bottom": 0, "shore_width": 0, "land_terrain_id": 0},
			},
		},
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13, "start": center, "population_housing": units_per_player + 100, "population_limit": units_per_player + 100, "starting_resources": {"food": 2000, "wood": 2000, "stone": 2000, "gold": 2000}},
			{"team": 2, "controller": "human", "civilization_id": 13, "start": center + Vector2(4.0, 4.0), "population_housing": units_per_player + 100, "population_limit": units_per_player + 100, "starting_resources": {"food": 2000, "wood": 2000, "stone": 2000, "gold": 2000}},
		],
		"entities": entities,
		"alliances": [],
		"victory_rules": [{"type": "conquest"}],
	}


func _visible_unit_position(team: int, index: int, visible_count: int, center: Vector2) -> Vector2:
	var columns := maxi(1, ceili(sqrt(float(visible_count))))
	var rows := maxi(1, ceili(float(visible_count) / float(columns)))
	var column := index % columns
	var row := index / columns
	var spacing := 0.72
	var side_offset := -2.5 if team == 1 else 2.5
	return center + Vector2(
		side_offset + (float(column) - float(columns - 1) * 0.5) * spacing,
		(float(row) - float(rows - 1) * 0.5) * spacing
	)


func _reserve_unit_position(team: int, index: int, map_side: int) -> Vector2:
	var columns := 24
	var column := index % columns
	var row := index / columns
	var origin := Vector2(24.0, 24.0) if team == 1 else Vector2(map_side - 72.0, map_side - 72.0)
	return origin + Vector2(float(column), float(row)) * 1.35


func _screen_unit_ids(game, units: Array, viewport_size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var rectangle := Rect2(Vector2(-96.0, HUD_TOP - 96.0), Vector2(viewport_size.x + 192.0, viewport_size.y - HUD_TOP - HUD_BOTTOM + 192.0))
	for unit_value in units:
		var unit: Dictionary = unit_value
		if rectangle.has_point(game.world_to_screen(Vector2(unit.get("pos", Vector2.ZERO)))):
			result[int(unit.get("id", -1))] = true
	return result


func _screen_drawable_count(game, drawables: Array, viewport_size: Vector2i) -> int:
	var rectangle := Rect2(Vector2(-128.0, HUD_TOP - 128.0), Vector2(viewport_size.x + 256.0, viewport_size.y - HUD_TOP - HUD_BOTTOM + 256.0))
	var count := 0
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		if rectangle.has_point(game.world_to_screen(Vector2(drawable.get("world_anchor", Vector2.ZERO)))):
			count += 1
	return count


func _rect_to_dictionary(rectangle: Rect2i) -> Dictionary:
	return {
		"x": rectangle.position.x,
		"y": rectangle.position.y,
		"width": rectangle.size.x,
		"height": rectangle.size.y,
		"area": rectangle.get_area(),
	}


func _summary(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"count": 0, "p50": 0, "p95": 0, "max": 0, "mean": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	return {
		"count": sorted.size(),
		"p50": sorted[int(floor(float(sorted.size() - 1) * 0.50))],
		"p95": sorted[int(floor(float(sorted.size() - 1) * 0.95))],
		"max": sorted[-1],
		"mean": float(total) / float(sorted.size()),
	}


func _options(arguments: PackedStringArray) -> Dictionary:
	var result := {
		"case": "e6_visible",
		"size": DEFAULT_SIZE,
		"units_per_player": 500,
		"visible_per_team": 80,
		"warmup_frames": 30,
		"sample_frames": 120,
		"preparation_samples": 12,
		"output": DEFAULT_OUTPUT,
		"capture_png": "",
	}
	for argument in arguments:
		if argument.begins_with("--case="):
			result["case"] = argument.trim_prefix("--case=")
		elif argument.begins_with("--size="):
			result["size"] = _parse_size(argument.trim_prefix("--size="))
		elif argument.begins_with("--units-per-player="):
			result["units_per_player"] = maxi(1, int(argument.trim_prefix("--units-per-player=")))
		elif argument.begins_with("--visible-per-team="):
			result["visible_per_team"] = maxi(0, int(argument.trim_prefix("--visible-per-team=")))
		elif argument.begins_with("--warmup-frames="):
			result["warmup_frames"] = maxi(1, int(argument.trim_prefix("--warmup-frames=")))
		elif argument.begins_with("--sample-frames="):
			result["sample_frames"] = maxi(1, int(argument.trim_prefix("--sample-frames=")))
		elif argument.begins_with("--preparation-samples="):
			result["preparation_samples"] = maxi(1, int(argument.trim_prefix("--preparation-samples=")))
		elif argument.begins_with("--output="):
			result["output"] = argument.trim_prefix("--output=")
		elif argument.begins_with("--capture-png="):
			result["capture_png"] = argument.trim_prefix("--capture-png=")
	return result


func _parse_size(value: String) -> Vector2i:
	var parts := value.to_lower().split("x", false)
	if parts.size() != 2:
		return DEFAULT_SIZE
	var parsed := Vector2i(int(parts[0]), int(parts[1]))
	return parsed if parsed.x >= 320 and parsed.y >= 240 else DEFAULT_SIZE
