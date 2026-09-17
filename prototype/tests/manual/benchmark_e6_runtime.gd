extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const GameController := preload("res://scripts/game_controller.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const GATHERERS_PER_RESOURCE := 2
const RESOURCES_PER_DROP_SITE := 8


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
	var workload := String(options["workload"])
	if workload == "gather_economy":
		var catalog = ResourceCatalog.new()
		catalog.load()
		world.set_gamespec(catalog.gamespec_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
	var players: Array = []
	var unit_ids_by_team: Dictionary = {}
	var formation_start_positions: Dictionary = {}
	var gather_resource_ids_by_team: Dictionary = {}
	if workload == "formation_march":
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
		var gather_resources: Array[int] = []
		var gather_positions: Array[Vector2] = []
		if workload == "gather_economy":
			var resource_count := ceili(float(units_per_player) / float(GATHERERS_PER_RESOURCE))
			var drop_site_count := ceili(float(resource_count) / float(RESOURCES_PER_DROP_SITE))
			for drop_site_index in range(drop_site_count):
				world.add_building(
					1000000 + team * 1000 + drop_site_index,
					"granary",
					_gather_drop_site_position(team, drop_site_index, drop_site_count, player_count, map_side),
					team
				)
			for resource_index in range(resource_count):
				var resource_position := _gather_resource_position(team, resource_index, resource_count, player_count, map_side)
				var resource: Dictionary = world.add_scenario_resource("berries", resource_position, 10000)
				gather_resources.append(int(resource["id"]))
				gather_positions.append(Vector2(resource["pos"]))
		for index in range(units_per_player):
			var spawn_position: Vector2
			if workload == "combat_contact":
				spawn_position = _combat_position(team, index, units_per_player, player_count, map_side)
			elif workload == "gather_economy":
				spawn_position = _gather_worker_position(index, units_per_player, gather_positions)
			else:
				spawn_position = prepared_positions[index] if index < prepared_positions.size() else _unit_position(team, index, player_count, map_side)
			var unit_kind := "villager" if workload == "gather_economy" else "clubman"
			var unit: Dictionary = world.add_unit(team, unit_kind, spawn_position, false)
			unit["stance"] = "passive"
			unit["attack_autonomous"] = false
			unit["acquisition_range"] = 0.0
			if workload == "combat_contact":
				unit["max_hp"] = 1000.0
				unit["hp"] = 1000.0
			team_unit_ids.append(int(unit["id"]))
		unit_ids_by_team[team] = team_unit_ids
		if workload == "gather_economy":
			gather_resource_ids_by_team[team] = gather_resources
	world.end_bulk_load()
	var setup_microseconds := Time.get_ticks_usec() - setup_started

	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var probe = PerformanceProbe.new(maxi(64, sample_ticks + 8))
	controller.set_performance_probe(probe)
	var command_phase: Dictionary = {}
	if workload in ["formation_march", "formation_assemble", "group_click_reservation"]:
		probe.clear()
		for team in range(1, player_count + 1):
			var ids: Array[int] = unit_ids_by_team[team]
			if workload == "group_click_reservation":
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
	elif workload == "individual_crossing":
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
	elif workload == "combat_contact":
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
	elif workload == "gather_economy":
		probe.clear()
		var gather_setup_started := Time.get_ticks_usec()
		var gather_assigned := 0
		for team in range(1, player_count + 1):
			var ids: Array[int] = unit_ids_by_team[team]
			var resource_ids: Array[int] = gather_resource_ids_by_team[team]
			for resource_index in range(resource_ids.size()):
				var workers: Array = []
				var first_worker := resource_index * GATHERERS_PER_RESOURCE
				var last_worker := mini(ids.size(), first_worker + GATHERERS_PER_RESOURCE)
				for worker_index in range(first_worker, last_worker):
					workers.append(world.find_unit(ids[worker_index]))
				world.assign_command_gather(workers, resource_ids[resource_index])
				gather_assigned += workers.filter(func(worker): return String(worker.get("task", "idle")) == "gather").size()
		command_phase = {
			"wall_microseconds": Time.get_ticks_usec() - gather_setup_started,
			"probe": probe.report(),
			"accepted": gather_assigned,
			"rejected": player_count * units_per_player - gather_assigned,
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
		"workload_state": _workload_state(world, player_count, workload),
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


func _workload_state(world, player_count: int, workload: String) -> Dictionary:
	if workload != "gather_economy":
		return {}
	var gather_cycles := 0
	var deposit_cycles := 0
	var carrying_units := 0
	for unit in world.get_units():
		gather_cycles += int(unit.get("gather_cycles", 0))
		deposit_cycles += int(unit.get("deposit_cycles", 0))
		carrying_units += int(float(unit.get("carried_amount", 0.0)) > 0.0)
	var food_by_team: Dictionary = {}
	for team in range(1, player_count + 1):
		food_by_team[String.num_int64(team)] = world.get_resource_amount(team, 0)
	return {
		"resource_nodes": world.get_resources().size(),
		"drop_sites": world.get_buildings().size(),
		"gather_cycles": gather_cycles,
		"deposit_cycles": deposit_cycles,
		"carrying_units": carrying_units,
		"food_by_team": food_by_team,
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


func _team_region(team: int, player_count: int, map_side: int) -> Rect2:
	var region_columns := ceili(sqrt(float(player_count)))
	var region_rows := ceili(float(player_count) / float(region_columns))
	var region_column := (team - 1) % region_columns
	var region_row := (team - 1) / region_columns
	var region_width := float(map_side) / float(region_columns)
	var region_height := float(map_side) / float(region_rows)
	return Rect2(Vector2(region_column * region_width, region_row * region_height), Vector2(region_width, region_height))


func _gather_drop_site_position(team: int, drop_site_index: int, drop_site_count: int, player_count: int, map_side: int) -> Vector2:
	var region := _team_region(team, player_count, map_side)
	var columns := ceili(sqrt(float(drop_site_count)))
	var rows := ceili(float(drop_site_count) / float(columns))
	var column := drop_site_index % columns
	var row := drop_site_index / columns
	var margin := 10.0
	var usable := Vector2(maxf(1.0, region.size.x - margin * 2.0), maxf(1.0, region.size.y - margin * 2.0))
	return region.position + Vector2(margin, margin) + Vector2(
		(float(column) + 0.5) * usable.x / float(columns),
		(float(row) + 0.5) * usable.y / float(rows)
	)


func _gather_resource_position(team: int, resource_index: int, resource_count: int, player_count: int, map_side: int) -> Vector2:
	var drop_site_index := resource_index / RESOURCES_PER_DROP_SITE
	var drop_site_count := ceili(float(resource_count) / float(RESOURCES_PER_DROP_SITE))
	var center := _gather_drop_site_position(team, drop_site_index, drop_site_count, player_count, map_side)
	var offsets := [
		Vector2(0.0, -6.5),
		Vector2(4.6, -4.6),
		Vector2(6.5, 0.0),
		Vector2(4.6, 4.6),
		Vector2(0.0, 6.5),
		Vector2(-4.6, 4.6),
		Vector2(-6.5, 0.0),
		Vector2(-4.6, -4.6),
	]
	# Integer-centered source footprints leave stable perimeter cells around the
	# source on the navigation grid; fractional centers can turn the benchmark
	# into a placement-geometry rejection test instead of an economy workload.
	return (center + offsets[resource_index % RESOURCES_PER_DROP_SITE]).round()


func _gather_worker_position(index: int, units_per_player: int, resource_positions: Array[Vector2]) -> Vector2:
	var resource_index := mini(resource_positions.size() - 1, index / GATHERERS_PER_RESOURCE)
	var local_index := index % GATHERERS_PER_RESOURCE
	var local_count := mini(GATHERERS_PER_RESOURCE, units_per_player - resource_index * GATHERERS_PER_RESOURCE)
	var angle := TAU * float(local_index) / float(maxi(1, local_count))
	return resource_positions[resource_index] + Vector2(cos(angle), sin(angle)) * 1.35


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
	if String(result["workload"]) not in ["passive_full_population", "formation_march", "formation_assemble", "individual_crossing", "group_click_reservation", "combat_contact", "gather_economy"]:
		result["workload"] = "passive_full_population"
	result["players"] = clampi(int(result["players"]), 2, 8)
	result["units_per_player"] = maxi(1, int(result["units_per_player"]))
	result["map_side"] = maxi(32, int(result["map_side"]))
	result["warmup_ticks"] = maxi(0, int(result["warmup_ticks"]))
	result["sample_ticks"] = maxi(1, int(result["sample_ticks"]))
	return result
