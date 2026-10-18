extends SceneTree

# Acceptance check for the archived visual fixture; excluded from a clean
# checkout's automatic suite, which has no captured map.bin.

const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const DIRECTORY := "res://qa/river-islands-one-20261018"
var failures: Array[String] = []

# Inspect the exact map shown in the preview, without generating other seeds.
func _initialize() -> void:
	var file := FileAccess.open(DIRECTORY.path_join("map.bin"), FileAccess.READ)
	if file == null:
		push_error("Capture the single river-islands preview before running this check")
		quit(1)
		return
	var built: Dictionary = file.get_var()
	var data: Dictionary = built["map_data"]
	var size: Vector2i = data["size"]
	var rivers: Dictionary = data["rivers"]
	check(Rules.terrain_id_for_logical(Rules.logical_for_terrain_id(Rivers.SHOAL)) == Rivers.SHOAL, "Shoal navigation class survives logical terrain conversion")
	var network := Rivers.inspect(rivers)
	check(bool(network["valid"]), "River graph drains to the sea with increasing runoff")
	check(int(network["confluences"]) > 0, "Map contains tributary confluences")
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(size)
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world, built["definition"], data)
	var grid = world.navigation_grid
	var masks: Dictionary = {}
	for restriction in [3, 6, 7]:
		masks[restriction] = grid.native_walkability_mask("land" if restriction == 7 else "water", restriction)
	var types: Dictionary = {}
	for i in range(size.x * size.y):
		if rivers["mask"][i] == 0: continue
		var kind := int(data["terrain_ids"][i])
		types[kind] = int(types.get(kind, 0)) + 1
		check(kind == int(rivers["terrain_types"][i]), "Ecology preserves river depth and sediment bars")
		if kind != Rivers.SHOAL: continue
		var cell := Vector2i(i % size.x, i / size.x)
		check(not grid.is_walkable_for(cell, "water") and not grid.is_walkable_for(cell, "land"), "Shoal blocks logical land and ship navigation")
		for restriction in [3, 6, 7]:
			check(masks[restriction][i] == 0 and not grid.is_walkable_for(cell, "water", restriction), "Shoal blocks native and script source restrictions")
	for kind in [1, 6, 15, 22]: check(int(types.get(kind, 0)) > 0, "River includes terrain class %d" % kind)
	for resource in data["resources"]:
		var cell := Vector2i(resource["position"])
		check(rivers["mask"][cell.y * size.x + cell.x] == 0, "Resources leave the river and its bars unobstructed")
	var nodes: Dictionary = {}
	for node in rivers["nodes"]: nodes[node["cell"]] = node
	for node in nodes.values():
		if float(node["discharge"]) < float(rivers["runoff_threshold"]) * 3.0: continue
		var from := Vector2(node["cell"]) + Vector2.ONE * 0.5
		var to := Vector2(node["downstream"]) + Vector2.ONE * 0.5
		check(grid.is_segment_walkable_for(from, to, 0.5, "water", 3), "Main channel preserves ship clearance at every bend and confluence")
	var candidates: Array = rivers["nodes"].filter(func(node): return int(node["mouth_distance"]) >= 8 and int(data["terrain_ids"][node["cell"].y * size.x + node["cell"].x]) == 22)
	candidates.sort_custom(func(a, b): return float(a["discharge"]) * float(a["mouth_distance"]) > float(b["discharge"]) * float(b["mouth_distance"]))
	var checked_basins: Dictionary = {}
	var routes: Array = []
	var movement_cases: Array = []
	for node in candidates:
		if checked_basins.has(node["basin"]): continue
		var mouth: Dictionary = node
		while not bool(mouth["is_mouth"]): mouth = nodes[mouth["downstream"]]
		var goal := Vector2(node["cell"]) + Vector2.ONE * 0.5
		var sea := Vector2(mouth["downstream"]) + Vector2.ONE * 0.5
		var outward := Vector2(mouth["downstream"] - mouth["cell"]).normalized()
		for step in range(2, 9):
			var point := Vector2(Vector2i(sea + outward * step)) + Vector2.ONE * 0.5
			var cell := Vector2i(point)
			if grid.contains(cell) and rivers["mask"][cell.y * size.x + cell.x] == 0 and grid.is_segment_walkable_for(sea, point, 0.5, "water", 3):
				sea = point
				break
		if not grid.is_position_walkable_for(sea, 0.5, "water", 3) or not grid.is_position_walkable_for(goal, 0.5, "water", 3): continue
		for restriction in [3, 6]:
			var path: Array = world.pathfinder.find_path(sea, goal, "water", restriction, 0.5)
			check(not path.is_empty() and Vector2(path.back()).distance_to(goal) < 0.75, "Ship restriction %d reaches the lower river from the sea" % restriction)
			var previous := sea
			var blocked_segments: Array = []
			for point in path:
				var clear: bool = grid.is_segment_walkable_for(previous, point, 0.5, "water", restriction)
				check(clear, "Ship route respects clearance and shoals")
				if not clear: blocked_segments.append([str(previous), str(point)])
				previous = point
			routes.append({"restriction": restriction, "sea": str(sea), "river": str(goal), "path_points": path.size(), "blocked_segments": blocked_segments})
		checked_basins[node["basin"]] = true
		movement_cases.append({"sea": sea, "river": goal})
		if checked_basins.size() >= 3: break
	check(not routes.is_empty(), "A lower river is actually navigable from the sea")
	var arrivals: Array = []
	var controller = Controller.new(world)
	for movement in movement_cases:
		var ship: Dictionary = world.add_unit(1, "fishing_boat", movement["sea"], false)
		check(ship.get("movement_domain") == "water", "Movement fixture uses an actual ship")
		var command = Commands.MoveCommand.new(1, [int(ship["id"])], movement["river"])
		controller.enqueue_command(command, true, 1)
		controller.advance_frame(0.05, 1, 2)
		check(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "River movement command is accepted")
		for tick in range(1800):
			controller.advance_frame(0.05, 1, 2)
			if ship["pos"].distance_to(movement["river"]) < 0.75: break
		var arrived: bool = ship["pos"].distance_to(movement["river"]) < 0.75
		check(arrived, "Ship actually arrives inside the river without sticking on a shoal")
		arrivals.append({"arrived": arrived, "position": str(ship["pos"]), "goal": str(movement["river"])})
	var islands := _land_components(data)
	var land := 0
	for area in islands: land += area
	var report := {"valid": failures.is_empty(), "errors": failures, "seed": data["seed"], "network": network,
		"river_terrain_cells": types, "native_masks": grid.mask_kernel != null, "ship_routes": routes, "ship_arrivals": arrivals,
		"islands_over_12_cells": islands.filter(func(area): return area >= 12).size(),
		"largest_island_cells": islands.max(), "largest_island_land_fraction": float(islands.max()) / maxi(1, land)}
	FileAccess.open(DIRECTORY.path_join("navigation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	world.task_coordinator.shutdown()
	for failure in failures: push_error(failure)
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _land_components(data: Dictionary) -> Array[int]:
	var size: Vector2i = data["size"]
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	for i in range(mask.size()): mask[i] = int(data["terrain_ids"][i] not in Rules.WATER_TERRAIN_IDS)
	var areas: Array[int] = []
	for i in range(mask.size()):
		if mask[i] == 0: continue
		var queue := PackedInt32Array([i])
		mask[i] = 0
		var cursor := 0
		while cursor < queue.size():
			var at := queue[cursor]
			cursor += 1
			for next in Navigation.neighbors(at, size):
				if mask[next] != 0:
					mask[next] = 0
					queue.append(next)
		areas.append(queue.size())
	return areas

func check(value: bool, context: String) -> void:
	if not value and context not in failures: failures.append(context)
