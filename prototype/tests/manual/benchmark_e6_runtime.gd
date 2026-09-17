extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
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
	var unit_ids_by_team: Dictionary = {}
	var formation_start_positions: Dictionary = {}
	if String(options["workload"]) == "formation_march":
		var local_slots := FormationGeometry.local_slots(units_per_player, FormationGeometry.BLOCK, 1.0)
		for team in range(1, player_count + 1):
			formation_start_positions[team] = FormationGeometry.world_slots(local_slots, _formation_start(team, player_count, map_side), Vector2.DOWN)
	for team in range(1, player_count + 1):
		players.append({"team": team, "controller": "ai", "civilization_id": 13})
	world.configure_players(players)
	world.begin_bulk_load()
	for team in range(1, player_count + 1):
		var team_unit_ids: Array[int] = []
		var prepared_positions: Array = formation_start_positions.get(team, [])
		for index in range(units_per_player):
			var spawn_position: Vector2
			if String(options["workload"]) == "combat_contact":
				spawn_position = _combat_position(team, index, units_per_player, player_count, map_side)
			else:
				spawn_position = prepared_positions[index] if index < prepared_positions.size() else _unit_position(team, index, player_count, map_side)
			var unit: Dictionary = world.add_unit(team, "clubman", spawn_position, false)
			unit["stance"] = "passive"
			unit["attack_autonomous"] = false
			unit["acquisition_range"] = 0.0
			if String(options["workload"]) == "combat_contact":
				unit["max_hp"] = 1000.0
				unit["hp"] = 1000.0
			team_unit_ids.append(int(unit["id"]))
		unit_ids_by_team[team] = team_unit_ids
	world.end_bulk_load()
	var setup_microseconds := Time.get_ticks_usec() - setup_started

	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var probe = PerformanceProbe.new(maxi(64, sample_ticks + 8))
	controller.set_performance_probe(probe)
	var command_phase: Dictionary = {}
	if String(options["workload"]) in ["formation_march", "formation_assemble", "group_click_reservation"]:
		probe.clear()
		for team in range(1, player_count + 1):
			var ids: Array[int] = unit_ids_by_team[team]
			if String(options["workload"]) == "group_click_reservation":
				controller.enqueue_command(Commands.MoveCommand.new(controller.tick_index + 1, ids, _formation_destination(team, player_count, map_side)), true, team)
			else:
				controller.enqueue_command(Commands.FormationMoveCommand.new(
					controller.tick_index + 1,
					ids,
					_formation_destination(team, player_count, map_side),
					FormationGeometry.BLOCK,
					Vector2.DOWN
				), true, team)
		var command_started := Time.get_ticks_usec()
		controller.advance_frame(0.05, 1, 2)
		command_phase = {
			"wall_microseconds": Time.get_ticks_usec() - command_started,
			"probe": probe.report(),
			"accepted": _command_result_count(controller.command_results, true),
			"rejected": _command_result_count(controller.command_results, false),
		}
	elif String(options["workload"]) == "individual_crossing":
		probe.clear()
		var movement_setup_started := Time.get_ticks_usec()
		var assigned := 0
		for team in range(1, player_count + 1):
			var ids: Array[int] = unit_ids_by_team[team]
			for index in range(ids.size()):
				var unit = world.find_unit(ids[index])
				assigned += int(world.assign_command_move([unit], _individual_destination(team, index, player_count, map_side)))
		command_phase = {
			"wall_microseconds": Time.get_ticks_usec() - movement_setup_started,
			"probe": probe.report(),
			"accepted": assigned,
			"rejected": player_count * units_per_player - assigned,
		}
	elif String(options["workload"]) == "combat_contact":
		probe.clear()
		var combat_setup_started := Time.get_ticks_usec()
		var combat_assigned := 0
		for first_team in range(1, player_count + 1, 2):
			var second_team := first_team + 1
			if second_team > player_count:
				break
			var first_ids: Array[int] = unit_ids_by_team[first_team]
			var second_ids: Array[int] = unit_ids_by_team[second_team]
			for index in range(mini(first_ids.size(), second_ids.size())):
				var first = world.find_unit(first_ids[index])
				var second = world.find_unit(second_ids[index])
				combat_assigned += int(world.assign_command_attack([first], int(second["id"])))
				combat_assigned += int(world.assign_command_attack([second], int(first["id"])))
		command_phase = {
			"wall_microseconds": Time.get_ticks_usec() - combat_setup_started,
			"probe": probe.report(),
			"accepted": combat_assigned,
			"rejected": player_count * units_per_player - combat_assigned,
		}
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
		"workload": String(options["workload"]),
		"players": player_count,
		"units_per_player": units_per_player,
		"entity_count": world.get_units().size(),
		"map_size": [map_side, map_side],
		"map_cells": map_side * map_side,
		"warmup_ticks": warmup_ticks,
		"sample_ticks": sample_ticks,
		"setup_microseconds": setup_microseconds,
		"command_phase": command_phase,
		"sample_wall_microseconds": benchmark_microseconds,
		"active_units_after_sample": world.get_units().filter(func(unit): return String(unit.get("task", "idle")) != "idle").size(),
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


func _formation_destination(team: int, player_count: int, map_side: int) -> Vector2:
	var region_columns := ceili(sqrt(float(player_count)))
	var region_rows := ceili(float(player_count) / float(region_columns))
	var region_column := (team - 1) % region_columns
	var region_row := (team - 1) / region_columns
	var region_width := maxi(8, map_side / region_columns)
	var region_height := maxi(8, map_side / region_rows)
	return Vector2(
		region_column * region_width + region_width * 0.5,
		region_row * region_height + region_height - 24.0
	)


func _individual_destination(team: int, index: int, player_count: int, map_side: int) -> Vector2:
	var region_columns := ceili(sqrt(float(player_count)))
	var region_rows := ceili(float(player_count) / float(region_columns))
	var region_column := (team - 1) % region_columns
	var region_row := (team - 1) / region_columns
	var region_width := maxi(8, map_side / region_columns)
	var region_height := maxi(8, map_side / region_rows)
	var usable_width := maxi(1, region_width - 4)
	var source_column := index % usable_width
	var destination_column := (source_column + maxi(1, usable_width / 2)) % usable_width
	var row := index / usable_width
	return Vector2(
		clampi(region_column * region_width + 2 + destination_column, 1, map_side - 2),
		clampi(region_row * region_height + 2 + row, 1, map_side - 2)
	) + Vector2(0.5, 0.5)


func _combat_position(team: int, index: int, units_per_player: int, player_count: int, map_side: int) -> Vector2:
	var pair_index := (team - 1) / 2
	var pair_count := maxi(1, ceili(float(player_count) / 2.0))
	var arena_columns := ceili(sqrt(float(pair_count)))
	var arena_rows := ceili(float(pair_count) / float(arena_columns))
	var arena_column := pair_index % arena_columns
	var arena_row := pair_index / arena_columns
	var arena_width := float(map_side) / float(arena_columns)
	var arena_height := float(map_side) / float(arena_rows)
	var columns := maxi(1, ceili(sqrt(float(units_per_player))))
	var column := index % columns
	var row := index / columns
	var spacing := 1.4
	var grid_width := float(columns - 1) * spacing
	var grid_height := float(ceili(float(units_per_player) / float(columns)) - 1) * spacing
	var side_offset := -0.35 if team % 2 == 1 else 0.35
	return Vector2(
		arena_column * arena_width + arena_width * 0.5 - grid_width * 0.5 + float(column) * spacing + side_offset,
		arena_row * arena_height + arena_height * 0.5 - grid_height * 0.5 + float(row) * spacing
	)


func _formation_start(team: int, player_count: int, map_side: int) -> Vector2:
	var region_columns := ceili(sqrt(float(player_count)))
	var region_rows := ceili(float(player_count) / float(region_columns))
	var region_column := (team - 1) % region_columns
	var region_row := (team - 1) / region_columns
	var region_width := maxi(8, map_side / region_columns)
	var region_height := maxi(8, map_side / region_rows)
	return Vector2(
		region_column * region_width + region_width * 0.5,
		region_row * region_height + 24.0
	)


func _command_result_count(results: Dictionary, accepted: bool) -> int:
	var count := 0
	for result in results.values():
		if bool(result.get("accepted", false)) == accepted:
			count += 1
	return count


func _options(arguments: PackedStringArray) -> Dictionary:
	var result := {
		"case": "area_x4_2p",
		"workload": "passive_full_population",
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
		elif key in ["case", "output", "workload"]:
			result[key] = value
	if String(result["workload"]) not in ["passive_full_population", "formation_march", "formation_assemble", "individual_crossing", "group_click_reservation", "combat_contact"]:
		result["workload"] = "passive_full_population"
	result["players"] = clampi(int(result["players"]), 2, 8)
	result["units_per_player"] = maxi(1, int(result["units_per_player"]))
	result["map_side"] = maxi(32, int(result["map_side"]))
	result["warmup_ticks"] = maxi(0, int(result["warmup_ticks"]))
	result["sample_ticks"] = maxi(1, int(result["sample_ticks"]))
	return result
