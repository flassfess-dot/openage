extends SceneTree

const FormationCorridor := preload("res://scripts/formation_corridor.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_narrow_door_compresses_and_restores()
	test_open_route_keeps_preferred_width()
	test_water_route_uses_the_member_navigation_domain()
	test_adaptive_width_and_blocked_side()
	test_obstacle_bends_and_single_cell_goal()
	test_native_corridor_matches_reference()

	if failures.is_empty():
		print("F-008 formation corridor tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_narrow_door_compresses_and_restores() -> void:
	var grid = NavigationGrid.new(Vector2i(20, 13))
	grid.configure_terrain(func(_cell): return "grass")
	var wall: Array = []
	for y in range(13):
		if y != 6:
			wall.append(Vector2i(10, y))
	grid.occupy(wall, "building", 100)
	var finder = Pathfinder.new(grid)
	var plan := FormationCorridor.plan(Vector2(3.5, 6.5), Vector2(16.5, 6.5), FormationGeometry.LINE, 7, 1.0, 0.3, finder, grid)
	assert_true(not plan["route"].is_empty(), "group route crosses doorway")
	assert_true(plan["has_compression"], "wide line detects narrow doorway")
	assert_true(plan["modes"].has("compressed"), "route contains compressed segment")
	assert_equal(plan["modes"][plan["modes"].size() - 1], "preferred", "formation restores after doorway")
	var waypoints := FormationCorridor.member_waypoints(plan, 7, FormationGeometry.LINE, 1.0, Vector2(1, 0), 0)
	assert_true(waypoints.size() >= 2, "member receives compression and restoration stages")
	assert_vector_close(waypoints[waypoints.size() - 1], FormationGeometry.world_slots(FormationGeometry.local_slots(7, FormationGeometry.LINE), Vector2(16.5, 6.5), Vector2.RIGHT)[0], "final stage restores requested line")


func test_open_route_keeps_preferred_width() -> void:
	var grid = NavigationGrid.new(Vector2i(24, 16))
	grid.configure_terrain(func(_cell): return "grass")
	var finder = Pathfinder.new(grid)
	var plan := FormationCorridor.plan(Vector2(5.5, 8.5), Vector2(18.5, 8.5), FormationGeometry.BLOCK, 7, 1.0, 0.3, finder, grid)
	assert_equal(plan["has_compression"], false, "open field needs no compression")
	for mode in plan["modes"]:
		assert_equal(mode, "preferred", "open route preserves selected form")


func test_water_route_uses_the_member_navigation_domain() -> void:
	var grid = NavigationGrid.new(Vector2i(16, 12))
	grid.configure_terrain(func(_cell): return "water")
	var finder = Pathfinder.new(grid)
	var plan := FormationCorridor.plan(Vector2(2.5, 5.5), Vector2(13.5, 5.5), FormationGeometry.LINE, 3, 1.0, 0.3, finder, grid, "water", 3)
	assert_true(not plan["route"].is_empty(), "water formation receives a naval corridor")
	assert_true(plan["route"].all(func(point): return grid.is_walkable_for(Vector2i(floori(point.x), floori(point.y)), "water", 3)), "naval corridor remains on water-accessible cells")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func test_adaptive_width_and_blocked_side() -> void:
	var grid = NavigationGrid.new(Vector2i(40, 30))
	grid.configure_terrain(func(cell): return "grass" if cell.y >= 12 and cell.y <= 16 else "water")
	var finder = Pathfinder.new(grid)
	var plan := FormationCorridor.plan(Vector2(6.5, 14.5), Vector2(30.5, 14.5), FormationGeometry.LINE, 20, 1, 0.3, finder, grid)
	assert_true(plan["columns"].any(func(count): return count >= 2 and count <= 4), "medium corridor uses several columns")
	var near_wall := FormationCorridor.plan(Vector2(6.5, 12.5), Vector2(30.5, 12.5), FormationGeometry.LINE, 7, 1, 0.3, finder, grid)
	assert_true(near_wall["has_compression"], "free space on one side cannot hide the wall on the other")
	assert_equal(near_wall["modes"][-1], "compressed", "destination inside the gap stays compact")


func test_obstacle_bends_and_single_cell_goal() -> void:
	var grid = NavigationGrid.new(Vector2i(30, 25))
	grid.configure_terrain(func(_cell): return "grass")
	var cells: Array = []
	for y in range(7, 18): cells.append(Vector2i(15, y))
	grid.occupy(cells, "building", 10)
	var finder = Pathfinder.new(grid)
	var plan := FormationCorridor.plan(Vector2(5.5, 12.5), Vector2(24.5, 12.5), FormationGeometry.COLUMN, 1, 1, 0.3, finder, grid)
	var points := FormationCorridor.member_waypoints(plan, 1, FormationGeometry.COLUMN, 1, Vector2.RIGHT, 0)
	assert_true(points.size() > 1, "individual waypoints retain the common obstacle detour")
	var same_cell := FormationCorridor.plan(Vector2(5.2, 5.2), Vector2(5.7, 5.7), FormationGeometry.LINE, 2, 1, 0.3, finder, grid)
	assert_equal(FormationCorridor.member_waypoint_sets(same_cell, 2, FormationGeometry.LINE, 1, Vector2.RIGHT).size(), 2, "short same-cell reform has destinations")


func test_native_corridor_matches_reference() -> void:
	var grid = NavigationGrid.new(Vector2i(90, 65))
	grid.configure_terrain(func(_cell): return "grass")
	var walls: Array = []
	for x in [22, 45, 68]:
		for y in range(7, 58):
			if (y < 25 if x == 45 else y > 39): continue
			walls.append(Vector2i(x, y))
	grid.occupy(walls, "building", 100)
	var native = Pathfinder.new(grid)
	if not native.uses_native_kernel():
		failures.append("native kernel required to verify corridor equivalence")
		return
	var reference = Pathfinder.new(grid)
	reference.set_native_enabled(false)
	for endpoints in [[Vector2(4.5, 30.5), Vector2(84.5, 30.5)], [Vector2(4.5, 3.5), Vector2(80.5, 3.5)], [Vector2(7.1, 6.2), Vector2(7.8, 6.7)]]:
		for radius in [0.3, 0.6]:
			var expected := FormationCorridor.plan(endpoints[0], endpoints[1], FormationGeometry.LINE, 7, 1.3, radius, reference, grid)
			var actual := FormationCorridor.plan(endpoints[0], endpoints[1], FormationGeometry.LINE, 7, 1.3, radius, native, grid)
			assert_equal(actual, expected, "native corridor retains route, bends, compression and deployment (radius=%s)" % radius)
