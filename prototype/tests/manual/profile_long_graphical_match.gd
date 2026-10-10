extends Node
const Probe := preload("res://scripts/performance_probe.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Commands := preload("res://scripts/commands.gd")
const Dependency := preload("res://scripts/cache_dependency.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const SIZES := [Vector2i(640, 480), Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]
class LongProbe extends Probe:
	var ai_capture_count := 0
	func observe_microseconds(metric: String, duration_microseconds: int) -> void:
		super.observe_microseconds(metric, duration_microseconds)
		if metric == "presentation.ai.snapshot": ai_capture_count += 1
var root: Window:
	get: return get_tree().root
func quit(code: int = 0) -> void:
	get_tree().quit(code)

const MAX_FRAMES := 216000
var frame_samples: Array[int] = []
var measure_frames := false
var previous_frame_us := 0
func _process(_delta: float) -> void:
	if measure_frames:
		var now := Time.get_ticks_usec()
		if previous_frame_us > 0 and frame_samples.size() < MAX_FRAMES: frame_samples.append(now - previous_frame_us)
		previous_frame_us = now
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	var save_path := ""
	var output := ""
	var seconds := 1800.0
	var checkpoint_every := 600.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save="): save_path = argument.trim_prefix("--save=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--seconds="): seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--checkpoint-every="): checkpoint_every = maxf(15.0, float(argument.trim_prefix("--checkpoint-every=")))
	if save_path.is_empty() or output.is_empty() or FileAccess.file_exists(output) or DisplayServer.get_name() == "headless":
		push_error("Pass a save and a new output path to a graphical runtime")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	Engine.max_fps = 60
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await MatchReady.wait_for_ready(get_tree(), game, 120000): quit(1); return
	if not game.load_game_from_path(save_path): push_error(game.last_save_error); quit(1); return
	if not await MatchReady.wait_for_ready(get_tree(), game, 120000): quit(1); return
	# This diagnostic explicitly exercises the journal pilot; normal matches keep it disabled.
	game.game_controller.set_paused(false)
	var probe := LongProbe.new(2048)
	game.game_controller.set_performance_probe(probe)
	var initial_tick: int = game.game_controller.tick_index
	var previous_tick := initial_tick
	var completed_ticks := 0
	var initial_offset: Vector2 = game.view_offset
	var started := Time.get_ticks_usec()
	previous_frame_us = started
	measure_frames = true
	var frames: Array[int] = frame_samples
	var memory: Array = []
	var actions: Array = []
	var next_memory := 0.0
	var next_checkpoint := checkpoint_every
	var next_minimap := 30.0
	var next_order := 60.0
	var next_size := 0.0
	var size_index := 0
	var selection_epoch := -1
	var selected: Array[int] = []
	var sizes: Array = []
	var reserved_builders: Array[int] = []
	var build_orders := 0
	var build_target: Variant = null
	var placement_cursor := 0
	var build_queued_at := 0.0
	var completed_house_id := -1
	var completed_house_seen := false
	var cancelled_house_id := -1
	var cancelled_house_seen := false
	var cancellation_cursor: Dictionary = {}
	var explored_before: int = game.simulation_world.get_fog_of_war().personally_explored_by_player.get(game.local_player_team, {}).size()
	var canonical_failures := 0
	print("LONG_GRAPHICS ready tick=", initial_tick, " duration=", seconds)
	while Time.get_ticks_usec() - started < int(seconds * 1000000):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var elapsed := float(now - started) / 1000000.0
		if elapsed >= seconds: break
		if frames.size() >= MAX_FRAMES: push_error("Long-run frame limit exceeded"); game.free(); quit(1); return
		if elapsed >= 5.0 and frames.size() < 3: push_error("MainLoop frame observer did not run"); game.free(); quit(1); return
		var tick: int = game.game_controller.tick_index
		completed_ticks += maxi(0, tick - previous_tick)
		previous_tick = tick
		game.view_offset = initial_offset + Vector2(sin(elapsed * 0.4) * 480.0, cos(elapsed * 0.3) * 240.0)
		if selection_epoch != game.simulation_world.cache_epoch:
			selected.clear()
			for unit in game.simulation_world.get_units():
				if int(unit.get("team", 0)) == game.local_player_team and float(unit.get("hp", 0.0)) > 0.0:
					selected.append(int(unit["id"]))
					if selected.size() >= 40: break
			selection_epoch = game.simulation_world.cache_epoch
		if int(elapsed) % 10 < 5: game.player_control_state.replace_or_add(selected, false)
		else: game.player_control_state.clear()
		if elapsed >= next_size:
			var size: Vector2i = SIZES[size_index % SIZES.size()]
			DisplayServer.window_set_size(size)
			root.size = size
			sizes.append({"seconds": elapsed, "resolution": [size.x, size.y]})
			size_index += 1
			next_size += seconds / float(SIZES.size())
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var capture := output.get_base_dir().path_join("long-%dx%d.png" % [size.x, size.y])
			if image.save_png(capture) != OK: push_error("Cannot save graphic capture"); game.free(); quit(1); return
			actions.append({"type": "resize_and_capture", "seconds": elapsed, "path": capture})
		if elapsed >= next_minimap:
			var geometry: Dictionary = game.minimap_geometry()
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			event.position = geometry["center"]
			actions.append({"type": "minimap_input", "seconds": elapsed, "accepted": game.handle_minimap_input(event)})
			next_minimap += 30.0
		if elapsed >= next_order and not game.simulation_world.battle_over:
			var army: Array[int] = []
			var destination := Vector2.ZERO
			for unit in game.simulation_world.units:
				if int(unit.get("team", 0)) == game.local_player_team and float(unit.get("hp", 0.0)) > 0.0 and not reserved_builders.has(int(unit["id"])) and bool(unit.get("combat_enabled", false)) and not game.simulation_world.entity_is_worker(unit):
					army.append(int(unit["id"]))
					destination = Vector2(unit["pos"]) + Vector2(5.0 if int(elapsed) % 120 < 60 else -5.0, 3.0)
					if army.size() >= 40: break
			var group_kind := "army"
			if army.is_empty():
				group_kind = "workers"
				for unit in game.simulation_world.units:
					if int(unit.get("team", 0)) == game.local_player_team and float(unit.get("hp", 0.0)) > 0.0 and not reserved_builders.has(int(unit["id"])) and game.simulation_world.entity_is_worker(unit):
						army.append(int(unit["id"]))
						destination = Vector2(unit["pos"]) + Vector2(8.0 if int(elapsed) % 120 < 60 else -8.0, 5.0)
						if army.size() >= 40: break
			if not army.is_empty():
				var command := Commands.FormationMoveCommand.new(game.game_controller.tick_index + 1, army, destination, "line")
				game._queue_local_command(command)
				actions.append({"type": "formation_order", "seconds": elapsed, "units": army.size(), "group": group_kind, "queued": true})
			next_order += 60.0
		# Queue ordinary build/delete commands; never alter resources or units for QA.
		if build_orders < 2 and elapsed >= (30.0 if build_orders == 0 else 90.0) and build_target == null:
			for unit in game.simulation_world.units:
				if int(unit.get("team", 0)) == game.local_player_team and float(unit.get("hp", 0.0)) > 0.0 and game.simulation_world.entity_is_worker(unit) and not reserved_builders.has(int(unit["id"])):
					var center := Vector2(unit["pos"]).floor()
					# A deterministic bounded local search is split into 8 candidates per frame.
					for _candidate in range(8):
						var candidate := center + Vector2(placement_cursor % 17 - 8, placement_cursor / 17 - 8) + Vector2(0.5, 0.5)
						placement_cursor = (placement_cursor + 1) % 289
						if game.simulation_world.can_place_foundation(game.local_player_team, "house", candidate):
							build_target = candidate
							build_queued_at = elapsed
							reserved_builders.append(int(unit["id"]))
							var builders: Array[int] = [int(unit["id"])]
							game._queue_local_command(Commands.BuildCommand.new(tick + 1, builders, "house", candidate))
							actions.append({"type": "build_order", "seconds": elapsed, "target": [candidate.x, candidate.y], "queued": true, "cancel_later": build_orders == 1})
							break
					break
		if build_target != null:
			for building in game.simulation_world.buildings:
				if int(building.get("team", 0)) == game.local_player_team and String(building.get("kind", "")) == "house" and Vector2(building["pos"]).distance_squared_to(build_target) < 1.01:
					actions.append({"type": "foundation_created", "seconds": elapsed, "id": int(building["id"])})
					if build_orders == 1:
						var ids: Array[int] = [int(building["id"])]
						cancelled_house_id = int(building["id"])
						cancellation_cursor = Dependency.stamp(game.simulation_world, Dependency.ENTITIES)
						game._queue_local_command(Commands.DeleteEntityCommand.new(tick + 1, ids))
						actions.append({"type": "foundation_cancel_order", "seconds": elapsed, "id": int(building["id"])})
					else:
						completed_house_id = int(building["id"])
					build_orders += 1
					build_target = null
					placement_cursor = 0
					break
		if build_target != null and elapsed - build_queued_at > 5.0:
			build_target = null
			reserved_builders.pop_back()
			actions.append({"type": "build_retry", "seconds": elapsed})
		if completed_house_id > 0 and not completed_house_seen:
			var building: Variant = game.simulation_world.find_building(completed_house_id)
			if building != null and String(building.get("state", "")) == "complete":
				completed_house_seen = true
				actions.append({"type": "construction_complete", "seconds": elapsed, "id": completed_house_id})
		if cancelled_house_id > 0 and not cancelled_house_seen and game.simulation_world.find_building(cancelled_house_id) == null:
			var cancelled := Dependency.changes(game.simulation_world, Dependency.ENTITIES, cancellation_cursor)
			cancelled_house_seen = cancelled["removed_ids"].has(cancelled_house_id) and not game.simulation_world.entity_changes.versions_by_id.has(cancelled_house_id)
			actions.append({"type": "foundation_cancelled", "seconds": elapsed, "id": cancelled_house_id, "journal_removed": cancelled_house_seen})
		if elapsed >= next_memory:
			var world = game.simulation_world
			var row := {"seconds": elapsed, "tick": tick, "frames": frames.size(), "ai_captures": probe.ai_capture_count, "memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)), "video_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)), "units": world.units.size(), "resources": world.resource_nodes.size(), "buildings": world.buildings.size(), "entity_versions": world.entity_changes.versions_by_id.size(), "journal_batches": world.entity_changes.history.size(), "journal_ids": world.entity_changes.retained_ids, "rare_templates": world.production_system.option_template_cache.size(), "rare_template_bytes": world.production_system.option_template_cache_bytes, "ai_observers": game.ai_observation_store.observer_caches.size(), "ai_records": game.ai_decision_queue.records.size(), "jobs": game.task_coordinator.pending.size(), "world_jobs": world.task_coordinator.pending.size(), "route_world": world.pathfinder.cache.size(), "route_cells": world.pathfinder.cell_cache.size(), "route_smooth": world.pathfinder.smoothed_cell_cache.size(), "native_kernels": world.pathfinder.native_kernels.size(), "immutable_roots": Data.immutable_roots.size(), "battle_over": world.battle_over}
			memory.append(row)
			next_memory = elapsed + 15.0
			if int(elapsed) % 60 < 15: print("LONG_GRAPHICS progress ", JSON.stringify(row))
		if elapsed >= next_checkpoint:
			var io_started := Time.get_ticks_usec()
			var checkpoint := output.get_base_dir().path_join("longrun-checkpoint.json")
			game.game_controller.set_paused(true)
			var codec := Replay.new()
			var before_state: Dictionary = codec.world_snapshot(game.simulation_world, game.game_controller.tick_index, game.game_controller)
			var before := str(before_state.hash())
			print("LONG_GRAPHICS save_begin seconds=", elapsed)
			if not game.save_game_to_path(checkpoint, "Длительный графический прогон"): push_error(game.last_save_error); game.free(); quit(1); return
			if not game.load_game_from_path(checkpoint): push_error(game.last_save_error); game.free(); quit(1); return
			if not await MatchReady.wait_for_ready(get_tree(), game, 120000): game.free(); quit(1); return
			var after_state: Dictionary = codec.world_snapshot(game.simulation_world, game.game_controller.tick_index, game.game_controller)
			var after := str(after_state.hash())
			var equal := before_state == after_state
			if not equal: canonical_failures += 1
			print("LONG_GRAPHICS restored canonical_equal=", equal)
			actions.append({"type": "save_load", "seconds": elapsed, "hash_before": before, "hash_after": after, "equal": equal, "duration_us": Time.get_ticks_usec() - io_started})
			game.game_controller.set_performance_probe(probe)
			game.game_controller.set_paused(false)
			selection_epoch = -1
			previous_tick = game.game_controller.tick_index
			next_checkpoint += checkpoint_every
	await get_tree().process_frame
	measure_frames = false
	var native_classes := {"path": ClassDB.class_exists("RoRPathKernel"), "read_model": ClassDB.class_exists("RoRReadModelKernel")}
	if native_classes["path"]: native_classes["retained_movement"] = ClassDB.instantiate("RoRPathKernel").has_method("configure_movement_entities")
	if native_classes["read_model"]:
		native_classes["ai_projection"] = ClassDB.instantiate("RoRReadModelKernel").has_method("project_ai")
		native_classes["replay_encoding"] = ClassDB.instantiate("RoRReadModelKernel").has_method("encode_replay_variant")
	var result := {"runtime": {"debug": OS.is_debug_build(), "editor": Engine.is_editor_hint(), "version": Engine.get_version_info()}, "native_classes": native_classes, "save": save_path, "seconds_requested": seconds, "seconds_actual": float(Time.get_ticks_usec() - started) / 1000000.0, "headless": false, "release": not OS.is_debug_build() and not Engine.is_editor_hint(), "initial_tick": initial_tick, "final_tick": game.game_controller.tick_index, "ticks_completed": completed_ticks, "ai_captures": probe.ai_capture_count, "frame_us": Probe.summarize(frames), "memory": memory, "actions": actions, "sizes": sizes, "canonical_failures": canonical_failures, "entity_journal_enabled": true, "player_scenario": {"build_orders": build_orders, "house_completed": completed_house_seen, "foundation_cancelled_with_journal": cancelled_house_seen, "explored_before": explored_before, "explored_after": game.simulation_world.get_fog_of_war().personally_explored_by_player.get(game.local_player_team, {}).size()}, "probe": probe.report(), "sample_limits": {"frames": MAX_FRAMES, "metrics": 2048, "memory_interval_seconds": 15}, "measurement_note": "Natural full frames include capture/resize and explicit checkpoint I/O pauses; probe metrics retain the most recent 2048 samples. Source profile and packaged FPS are distinct."}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("Cannot save long-run report"); game.free(); quit(1); return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("LONG_GRAPHICS done ", result["frame_us"])
	game.free()
	quit(0 if canonical_failures == 0 and completed_ticks > 0 else 1)
