extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Fog := preload("res://scripts/fog_of_war.gd")
const Commands := preload("res://scripts/commands.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Probe := preload("res://scripts/performance_probe.gd")
var failures: Array[String] = []


func _initialize() -> void:
	for native in [false, true]:
		test_discover_and_remember_obstacles(native)
		test_idle_explorer_remembers_obstacles(native)
		test_move_discovers_forest(native)
		test_formation_keeps_unknown_route(native)
	test_large_exploration_updates_native_mask_incrementally()
	for failure in failures:
		push_error(failure)
	print("Fog-aware navigation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func fixture(native: bool):
	var world = World.new(Vector2i(32, 22))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.pathfinder.set_native_enabled(native)
	return world


func test_discover_and_remember_obstacles(native: bool) -> void:
	var world = fixture(native)
	world.fog_of_war.ensure_player(1)
	var cells: Array = []
	for y in range(5, 17):
		cells.append(Vector2i(14, y))
	world.navigation_grid.occupy(cells, "resource", 400)
	var knowledge = world.movement_system.knowledge
	var planner = knowledge.planner(world, 1)
	var first: Array = planner.find_path(Vector2(3.5, 10.5), Vector2(27.5, 10.5), "land", -1, 0.3)
	check(first == [Vector2(27.5, 10.5)], "unknown forest does not influence route before exploration")
	check(knowledge.planner(world, 1) == planner, "unchanged navigation reuses the same team planner")
	for cell in cells:
		world.fog_of_war.reveal_explored_cell(1, cell)
	planner = knowledge.planner(world, 1)
	var known: Array = planner.find_path(Vector2(3.5, 10.5), Vector2(27.5, 10.5), "land", -1, 0.3)
	check(known.size() > 1, "discovered forest produces a detour (native=%s)" % native)
	var remembered_revision: int = planner.grid.revision
	world.navigation_grid.release_occupant(cells, "resource", 400)
	planner = knowledge.planner(world, 1)
	check(planner.grid.revision == remembered_revision and planner.grid.occupied_cells.has(Vector2i(14, 10)), "unseen forest removal cannot leak through navigation")
	for cell in cells:
		var index: int = cell.y * world.map_size.x + cell.x
		world.fog_of_war.states_by_player[1][index] = Fog.VISIBLE
		world.fog_of_war.path_dirty_by_player[1][index] = true
	world.fog_of_war.revision += 1
	planner = knowledge.planner(world, 1)
	check(planner.find_path(Vector2(3.5, 10.5), Vector2(27.5, 10.5), "land", -1, 0.3) == first, "revisiting the cleared forest updates its remembered obstruction")


func test_idle_explorer_remembers_obstacles(native: bool) -> void:
	var world = fixture(native)
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(12.5, 10.5), false)
	unit["components"]["vision"]["enabled"] = true
	unit["components"]["vision"]["range"] = 3.0
	var cells := [Vector2i(14, 10)]
	world.navigation_grid.occupy(cells, "resource", 700)
	world.update_fog_of_war()
	unit["pos"] = Vector2(3.5, 10.5)
	world.update_fog_of_war()
	world.navigation_grid.release_occupant(cells, "resource", 700)
	world.update_fog_of_war()
	var planner = world.movement_system.knowledge.planner(world, 1)
	check(planner.grid.occupied_cells.has(Vector2i(14, 10)), "idle sight records an obstacle before any move order and retains its hidden removal")


func test_large_exploration_updates_native_mask_incrementally() -> void:
	var world = World.new(Vector2i(96, 40))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var wall: Array = []
	for y in range(5, 35):
		wall.append(Vector2i(40, y))
	world.navigation_grid.occupy(wall, "resource", 800)
	var probe = Probe.new()
	world.pathfinder.performance_probe = probe
	var planner = world.movement_system.knowledge.planner(world, 1)
	if not planner.uses_native_kernel():
		return
	var origin := Vector2(3.5, 20.5)
	var goal := Vector2(80.5, 20.5)
	planner.find_path(origin, goal, "land", -1, 0.3)
	var before: int = int(probe.report().get("counters", {}).get("navigation.native_mask_rebuilds", 0))
	for y in range(40):
		for x in range(35, 61):
			world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	planner = world.movement_system.knowledge.planner(world, 1)
	check(planner.find_path(origin, goal, "land", -1, 0.3).size() > 1, "a large exploration batch discovers the forest")
	var counters: Dictionary = probe.report().get("counters", {})
	check(int(counters.get("navigation.native_mask_rebuilds", 0)) == before and int(counters.get("navigation.native_mask_updated_cells", 0)) >= 1040, "exploring over 512 cells patches native navigation without a full map rebuild")


func test_move_discovers_forest(native: bool) -> void:
	var world = fixture(native)
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3.5, 10.5), false)
	unit["components"]["vision"]["enabled"] = true
	unit["components"]["vision"]["range"] = 3.0
	world.update_fog_of_war()
	var cells: Array = []
	for y in range(5, 17):
		cells.append(Vector2i(14, y))
	world.configure_static_obstructions([{"id": -77, "occupied_cells": cells}])
	world.rebuild_navigation_grid()
	var target := Vector2(27.5, 10.5)
	world.assign_command_move([unit], target)
	check(unit["path"] == [target], "unit initially heads directly toward the unknown destination")
	var saw_detour := false
	var crossed_obstacle := false
	for unused in range(1800):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index(false)
		world.update_fog_of_war()
		saw_detour = saw_detour or absf(float(unit["pos"].y) - 10.5) > 3.0
		crossed_obstacle = crossed_obstacle or Vector2i(Vector2(unit["pos"]).floor()) in cells
		if Vector2(unit["pos"]).distance_to(target) < 0.2:
			break
	check(saw_detour and not crossed_obstacle and Vector2(unit["pos"]).distance_to(target) < 0.2, "unit discovers, avoids and completes its forest route (native=%s pos=%s task=%s path=%s target=%s reason=%s known=%s)" % [native, unit["pos"], unit["task"], unit["path"], unit["target"], unit["diagnostic_reason"], world.movement_system.knowledge.planner(world, 1).grid.occupied_cells.keys()])


func test_formation_keeps_unknown_route(native: bool) -> void:
	var world = fixture(native)
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(3.5, 9.5), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(3.5, 11.5), false)
	var cells: Array = []
	for y in range(4, 18):
		cells.append(Vector2i(14, y))
	world.navigation_grid.occupy(cells, "resource", 500)
	var controller = Controller.new(world)
	var command = Commands.FormationMoveCommand.new(0, [int(first["id"]), int(second["id"])], Vector2(27.5, 10.5), "RECTANGLE")
	controller.enqueue_command(command, true, 1)
	controller.process_commands()
	check(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "formation accepts a destination beyond unexplored obstacles")
	for unit in [first, second]:
		check(unit["path"].all(func(point): return absf(point.y - 10.5) < 3.0), "formation corridor does not reveal the hidden forest (native=%s)" % native)


func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
