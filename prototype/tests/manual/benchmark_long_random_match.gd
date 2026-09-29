extends SceneTree

# Accelerated real main-scene workload: one sample per simulated minute.
# Keeps presentation/event consumption active, unlike simulation-only benches.
const Settings := preload("res://scripts/skirmish_settings.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Replay := preload("res://scripts/replay_system.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var output := "res://qa/performance/long-random-match.json"
	var minutes := 6
	var map_type := "coastal"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--map-type="):
			map_type = argument.trim_prefix("--map-type=")
		elif argument.begins_with("--minutes="):
			minutes = maxi(1, int(argument.trim_prefix("--minutes=")))
	var settings := Settings.default_settings()
	settings["map_type_id"] = map_type
	var built := Settings.build(settings)
	assert(bool(built.get("valid", false)), str(built.get("errors")))
	var game = load("res://main.tscn").instantiate()
	game.match_path = built["identity"]
	game.match_definition_override = built["definition"]
	game.map_definition_override = built["map_data"]
	root.add_child(game)
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	var probe := Probe.new(1200)
	game.game_controller.set_performance_probe(probe)
	var samples: Array = []
	var verifier := Replay.new()
	for minute in range(minutes):
		probe.clear()
		var ai_cycles: Array[int] = []
		var ordinary_cycles: Array[int] = []
		var planning_ticks: Array[int] = []
		var started := Time.get_ticks_usec()
		for step in range(1200):
			var plans_before: int = probe.sample_count("presentation.ai.snapshot")
			var cycle_started := Time.get_ticks_usec()
			game._process(0.05)
			game.current_world_drawables()
			var cycle_us := Time.get_ticks_usec() - cycle_started
			if probe.sample_count("presentation.ai.snapshot") > plans_before:
				ai_cycles.append(cycle_us)
				planning_ticks.append(game.game_controller.tick_index)
			else:
				ordinary_cycles.append(cycle_us)
			if step % 100 == 0:
				await process_frame
		var sample := {
			"minute": minute + 1,
			"wall_us": Time.get_ticks_usec() - started,
			"tick": game.game_controller.tick_index,
			"units": game.simulation_world.get_units().size(),
			"buildings": game.simulation_world.get_buildings().size(),
			"events": game.game_controller.event_stream.retained_count(),
			"replay_commands": game.game_controller.replay_recorder.command_records.size(),
			"projections": game.simulation_world.render_entity_projection_cache.projections_by_id.size(),
			"known_resources": game.simulation_world.get_known_resources(1).size(),
			"memory_bytes": OS.get_static_memory_usage(),
			"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
			"probe": probe.report(),
			"cycles_with_ai_us": Probe.summarize(ai_cycles),
			"cycles_without_ai_us": Probe.summarize(ordinary_cycles),
			"planning_ticks": planning_ticks,
		}
		sample["canonical_hash"] = verifier.world_state_hash(game.simulation_world, game.game_controller.tick_index, game.game_controller)
		samples.append(sample)
		print("LONG_MATCH minute=%d tick=%d units=%d wall_ms=%d memory=%d" % [minute + 1, sample["tick"], sample["units"], sample["wall_us"] / 1000, sample["memory_bytes"]])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file == null:
			push_error("Cannot write benchmark report: %s" % output)
			game.free()
			quit(1)
			return
		file.store_string(JSON.stringify(samples, "\t") + "\n")
		file.close()
	game.free()
	quit(0)
