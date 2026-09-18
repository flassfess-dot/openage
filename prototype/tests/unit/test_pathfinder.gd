extends SceneTree

const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_astar_avoids_water_and_corners()
	test_smoothing_and_cache()
	test_blocked_destination_uses_nearest_cell()
	test_same_cell_exact_endpoints_do_not_alias()
	test_clearance_aware_route_avoids_narrow_shore()
	test_simulation_routes_around_town_center()
	test_native_kernel_matches_gdscript()

	if failures.is_empty():
		print("N-004 pathfinder tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_astar_avoids_water_and_corners() -> void:
	var grid = open_grid(Vector2i(9, 9))
	for y in range(1, 8):
		if y != 5:
			grid.set_terrain(Vector2i(4, y), "water")
	var finder = Pathfinder.new(grid)
	var cells := finder.find_cell_path(Vector2i(1, 1), Vector2i(7, 7))
	assert_true(not cells.is_empty(), "path exists through wall gap")
	assert_true(cells.has(Vector2i(4, 5)), "path uses wall gap")
	for index in range(1, cells.size()):
		assert_true(finder.line_walkable(cells[index - 1], cells[index]), "each step avoids water and corner cuts")


func test_smoothing_and_cache() -> void:
	var grid = open_grid(Vector2i(12, 12))
	var finder = Pathfinder.new(grid)
	var raw := finder.find_cell_path(Vector2i(2, 2), Vector2i(9, 7))
	var smooth := finder.smooth_cells(raw)
	assert_true(smooth.size() < raw.size(), "open path is smoothed")
	var first := finder.find_path(Vector2(2.5, 2.5), Vector2(9.5, 7.5))
	var second := finder.find_path(Vector2(2.5, 2.5), Vector2(9.5, 7.5))
	assert_equal(second, first, "cached path is deterministic")
	assert_equal(finder.cache_hits, 1, "second group-compatible query hits cache")


func test_blocked_destination_uses_nearest_cell() -> void:
	var grid = open_grid(Vector2i(8, 8))
	grid.rebuild([{"id": 4, "pos": Vector2(5.2, 5.2), "amount": 10}], [])
	var finder = Pathfinder.new(grid)
	var path := finder.find_path(Vector2(2.5, 2.5), Vector2(5.2, 5.2))
	assert_true(not path.is_empty(), "path to blocked target gets adjacent destination")
	var destination: Vector2 = path[path.size() - 1]
	assert_true(Vector2i(floori(destination.x), floori(destination.y)) != Vector2i(5, 5), "blocked target cell is not used")


func test_same_cell_exact_endpoints_do_not_alias() -> void:
	var grid = open_grid(Vector2i(12, 12))
	var finder = Pathfinder.new(grid)
	var first := finder.find_path(Vector2(6.0, 5.5), Vector2(6.28, 5.5))
	var returned := finder.find_path(Vector2(6.28, 5.5), Vector2(6.0, 5.5))
	assert_equal(first[first.size() - 1], Vector2(6.28, 5.5), "first exact same-cell endpoint")
	assert_equal(returned[returned.size() - 1], Vector2(6.0, 5.5), "return exact same-cell endpoint")


func test_clearance_aware_route_avoids_narrow_shore() -> void:
	var grid = NavigationGrid.new(Vector2i(10, 8))
	grid.configure_terrain(func(cell: Vector2i) -> String:
		if cell.y in [0, 7] or cell.x in [0, 9]:
			return "land"
		if cell.y == 3 and cell.x not in [2, 7]:
			return "land"
		return "water"
	)
	var finder = Pathfinder.new(grid)
	var small := finder.find_path(Vector2(2.5, 1.5), Vector2(7.5, 5.5), "water", -1, 0.2)
	var large := finder.find_path(Vector2(2.5, 1.5), Vector2(7.5, 5.5), "water", -1, 0.75)
	assert_true(not small.is_empty(), "small water unit can pass a one-cell channel")
	assert_true(large.is_empty(), "large water unit rejects a channel narrower than its footprint")


func test_simulation_routes_around_town_center() -> void:
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.set_gamespec({"units": {"town_center": {"hit_points": 600.0, "selection_radius": [1.5, 1.5, 2.0]}}})
	world.reset_game()
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(9.5, 12.5), false)
	world.assign_command_move([unit], Vector2(15.5, 12.5))
	assert_true(unit["path"].size() >= 2, "town center forces a routed path")
	var previous := Vector2i(floori(unit["pos"].x), floori(unit["pos"].y))
	for waypoint in unit["path"]:
		var next := Vector2i(floori(waypoint.x), floori(waypoint.y))
		assert_true(world.pathfinder.line_walkable(previous, next), "simulation waypoint segment is walkable")
		previous = next


func test_native_kernel_matches_gdscript() -> void:
	var native_finder = Pathfinder.new(open_grid(Vector2i(18, 15)))
	if not native_finder.uses_native_kernel():
		print("Native path kernel unavailable; deterministic fallback remains active")
		return
	var script_finder = Pathfinder.new(native_finder.grid)
	script_finder.set_native_enabled(false)
	for cell in [Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10), Vector2i(6, 11), Vector2i(6, 12), Vector2i(11, 4), Vector2i(12, 4), Vector2i(13, 4)]:
		native_finder.grid.set_terrain(cell, "water")
	var pairs := [
		[Vector2i(2, 2), Vector2i(15, 12)],
		[Vector2i(15, 12), Vector2i(2, 2)],
		[Vector2i(3, 11), Vector2i(14, 2)],
		[Vector2i(7, 6), Vector2i(14, 6)],
	]
	for pair in pairs:
		var expected: Array[Vector2i] = script_finder.find_cell_path(pair[0], pair[1])
		var actual: Array[Vector2i] = native_finder.find_cell_path(pair[0], pair[1])
		assert_equal(actual, expected, "native A* preserves deterministic path %s -> %s" % [pair[0], pair[1]])
	var native_clearance: Array[Vector2i] = native_finder.find_cell_path(Vector2i(2, 2), Vector2i(15, 12), "land", -1, 0.3)
	var script_clearance: Array[Vector2i] = script_finder.find_cell_path(Vector2i(2, 2), Vector2i(15, 12), "land", -1, 0.3)
	assert_equal(native_clearance, script_clearance, "native A* preserves clearance-aware path")


func open_grid(size: Vector2i):
	var grid = NavigationGrid.new(size)
	grid.configure_terrain(func(_cell: Vector2i) -> String: return "land")
	return grid


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
