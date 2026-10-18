extends SceneTree

# Acceptance check for the archived visual fixture; excluded from a clean
# checkout's automatic suite, which has no captured map.bin.

const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Rivers := preload("res://scripts/random_map_rivers.gd")
const Geography := preload("res://scripts/random_map_watershed_world.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const DIRECTORY := "res://qa/continental-one-20261018"
var failures: Array[String] = []

func _initialize() -> void:
	var file := FileAccess.open(DIRECTORY.path_join("map.bin"), FileAccess.READ)
	if file == null:
		push_error("Capture the one continental map first")
		quit(1)
		return
	var built: Dictionary = file.get_var()
	var data: Dictionary = built["map_data"]
	check(Rivers.inspect(data["rivers"])["valid"], "Runoff and downstream drainage remain valid")
	check(not data["lakes"].is_empty(), "Continental map includes relief-basin lakes")
	check(not data["fords"].is_empty(), "Continental map includes natural river fords")
	check(Rules.terrain_id_for_logical("shallows") == 4, "Ford retains original shallows class")
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world, built["definition"], data)
	var grid = world.navigation_grid
	var masks: Dictionary = {}
	for restriction in [3, 6, 7]: masks[restriction] = grid.native_walkability_mask("land" if restriction == 7 else "water", restriction)
	var ford_paths: Array = []
	for ford in data["fords"]:
		for cell in ford["cells"]:
			var i: int = cell.y * grid.size.x + cell.x
			check(int(data["terrain_ids"][i]) == 4, "Final ford surface remains original shallows")
			for restriction in [3, 6, 7]:
				check(masks[restriction][i] != 0 and grid.is_walkable_for(cell, "land" if restriction == 7 else "water", restriction), "Native and script masks admit infantry and both ship restrictions on every ford cell")
		var a: Vector2 = ford["bank_a"]
		var b: Vector2 = ford["bank_b"]
		check(grid.is_segment_walkable_for(a, b, 0.3, "land", 7), "Ford connects both banks with infantry clearance")
		var path: Array = world.pathfinder.find_path(a, b, "land", 7, 0.3)
		check(not path.is_empty() and Vector2(path.back()).distance_to(b) < 0.5, "Infantry path reaches the opposite bank")
		ford_paths.append({"bank_a": str(a), "bank_b": str(b), "path_points": path.size()})
	for lake in data["lakes"]:
		check(lake["origin"] == "filled_relief_depression", "Lakes occupy drainage depressions")
		for i in lake["cells"]: check(int(data["terrain_ids"][i]) in [1, 22], "Lake shoreline and deeper interior survive ecology")
	for resource in data["resources"]:
		var cell := Vector2i(resource["position"])
		check(data["rivers"]["mask"][cell.y * grid.size.x + cell.x] == 0, "River, lake and ford approaches remain free of resources")
	var controller = Controller.new(world)
	var arrivals: Array = []
	for ford in data["fords"].slice(0, mini(3, data["fords"].size())):
		var center := Vector2(ford["center"]) + Vector2.ONE * 0.5
		var cross_axis: Vector2 = (ford["bank_b"] - ford["bank_a"]).normalized()
		var tangent := Vector2(-cross_axis.y, cross_axis.x)
		for kind in ["clubman", "fishing_boat"]:
			var from: Vector2 = ford["bank_a"] if kind == "clubman" else center - tangent
			var goal: Vector2 = ford["bank_b"] if kind == "clubman" else center + tangent
			var unit: Dictionary = world.add_unit(1, kind, from, false)
			check(unit["pos"].distance_to(from) < 0.5, "Crossing fixture starts at its requested ford position")
			var command = Commands.MoveCommand.new(1, [int(unit["id"])], goal)
			controller.enqueue_command(command, true, 1)
			controller.advance_frame(0.05, 1, 2)
			check(controller.get_command_result(command.sequence_id).get("accepted", false), "Ford crossing move command is accepted")
			for tick in range(700):
				controller.advance_frame(0.05, 1, 2)
				if unit["pos"].distance_to(goal) < 0.45: break
			var arrived: bool = unit["pos"].distance_to(goal) < 0.45
			check(arrived, "%s actually crosses the ford" % kind)
			arrivals.append({"kind": kind, "arrived": arrived, "start": str(from), "goal": str(goal), "position": str(unit["pos"])})
	world.task_coordinator.shutdown()
	var highlands := Geography.geography(Vector2i(160, 160), "highlands", 41721)
	check(not highlands["lakes"].is_empty(), "Highlands also permit lakes in suitable relief depressions")
	var first := Geography.geography(Vector2i(72, 72), "continental", 41721)
	var second := Geography.geography(Vector2i(72, 72), "continental", 41721)
	check(first["terrain"] == second["terrain"] and first["lakes"] == second["lakes"] and first["fords"] == second["fords"], "Same seed reproduces land, lakes and fords")
	var report := {"valid": failures.is_empty(), "errors": failures, "seed": data["seed"], "lakes": data["lakes"].size(),
		"fords": data["fords"].size(), "ford_paths": ford_paths, "actual_crossings": arrivals,
		"highland_lakes_160": highlands["lakes"].size(), "small_continental_lakes_72": first["lakes"].size()}
	FileAccess.open(DIRECTORY.path_join("navigation.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func check(value: bool, context: String) -> void:
	if not value and context not in failures: failures.append(context)
