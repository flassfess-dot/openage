extends SceneTree

const GameController := preload("res://scripts/game_controller.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")


func _initialize() -> void:
	var options := _options(OS.get_cmdline_user_args())
	var result := _run_case(options)
	var output_path := ProjectSettings.globalize_path(String(options["output"]))
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("E6 benchmark cannot write %s" % output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("E6-001 benchmark case=%s players=%d units=%d map=%dx%d tick_p95_us=%d output=%s" % [
		String(result["case"]),
		int(result["players"]),
		int(result["entity_count"]),
		int(result["map_size"][0]),
		int(result["map_size"][1]),
		int(result["probe"]["metrics_microseconds"]["controller.fixed_tick"]["p95"]),
		output_path,
	])
	quit(0)


func _run_case(options: Dictionary) -> Dictionary:
	var player_count := int(options["players"])
	var units_per_player := int(options["units_per_player"])
	var map_side := int(options["map_side"])
	var warmup_ticks := int(options["warmup_ticks"])
	var sample_ticks := int(options["sample_ticks"])
	var setup_started := Time.get_ticks_usec()
	var world = SimulationWorld.new(Vector2i(map_side, map_side))
	var players: Array = []
	for team in range(1, player_count + 1):
		players.append({"team": team, "controller": "ai", "civilization_id": 13})
	world.configure_players(players)
	world.begin_bulk_load()
	for team in range(1, player_count + 1):
		for index in range(units_per_player):
			var unit: Dictionary = world.add_unit(team, "clubman", _unit_position(team, index, player_count, map_side), false)
			unit["stance"] = "passive"
			unit["attack_autonomous"] = false
			unit["acquisition_range"] = 0.0
	world.end_bulk_load()
	var setup_microseconds := Time.get_ticks_usec() - setup_started

	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var probe = PerformanceProbe.new(maxi(64, sample_ticks + 8))
	controller.set_performance_probe(probe)
	for _tick in range(warmup_ticks):
		controller.advance_frame(0.05, 1, 2)
	probe.clear()
	var benchmark_started := Time.get_ticks_usec()
	for _tick in range(sample_ticks):
		controller.advance_frame(0.05, 1, 2)
	var benchmark_microseconds := Time.get_ticks_usec() - benchmark_started
	var replay = ReplaySystem.new()
	var final_hash := replay.world_state_hash(world, controller.tick_index, controller)
	return {
		"schema_version": 1,
		"case": String(options["case"]),
		"workload": "passive_full_population",
		"players": player_count,
		"units_per_player": units_per_player,
		"entity_count": world.get_units().size(),
		"map_size": [map_side, map_side],
		"map_cells": map_side * map_side,
		"warmup_ticks": warmup_ticks,
		"sample_ticks": sample_ticks,
		"setup_microseconds": setup_microseconds,
		"sample_wall_microseconds": benchmark_microseconds,
		"canonical_hash": final_hash,
		"probe": probe.report(),
		"process": {
			"os": OS.get_name(),
			"processor": OS.get_processor_name(),
			"logical_processors": OS.get_processor_count(),
			"memory_static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
			"memory_static_max_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		},
	}


func _unit_position(team: int, index: int, player_count: int, map_side: int) -> Vector2:
	var region_columns := ceili(sqrt(float(player_count)))
	var region_rows := ceili(float(player_count) / float(region_columns))
	var region_column := (team - 1) % region_columns
	var region_row := (team - 1) / region_columns
	var region_width := maxi(8, map_side / region_columns)
	var region_height := maxi(8, map_side / region_rows)
	var usable_width := maxi(1, region_width - 4)
	var x := region_column * region_width + 2 + index % usable_width
	var y := region_row * region_height + 2 + index / usable_width
	return Vector2(clampi(x, 1, map_side - 2), clampi(y, 1, map_side - 2)) + Vector2(0.5, 0.5)


func _options(arguments: PackedStringArray) -> Dictionary:
	var result := {
		"case": "area_x4_2p",
		"players": 2,
		"units_per_player": 500,
		"map_side": 400,
		"warmup_ticks": 2,
		"sample_ticks": 10,
		"output": "res://qa/performance/e6-area-x4-2p.json",
	}
	for argument in arguments:
		var separator := argument.find("=")
		if separator <= 2:
			continue
		var key := argument.substr(2, separator - 2).replace("-", "_")
		var value := argument.substr(separator + 1)
		if key in ["players", "units_per_player", "map_side", "warmup_ticks", "sample_ticks"]:
			result[key] = maxi(0, int(value))
		elif key in ["case", "output"]:
			result[key] = value
	result["players"] = clampi(int(result["players"]), 2, 8)
	result["units_per_player"] = maxi(1, int(result["units_per_player"]))
	result["map_side"] = maxi(32, int(result["map_side"]))
	result["warmup_ticks"] = maxi(0, int(result["warmup_ticks"]))
	result["sample_ticks"] = maxi(1, int(result["sample_ticks"]))
	return result
