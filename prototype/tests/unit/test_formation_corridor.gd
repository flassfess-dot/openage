extends SceneTree

const FormationCorridor := preload("res://scripts/formation_corridor.gd")
const FormationGeometry := preload("res://scripts/formation_geometry.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_narrow_door_compresses_and_restores()
	test_open_route_keeps_preferred_width()

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
	assert_vector_close(waypoints[waypoints.size() - 1], Vector2(16.5, 9.5), "final stage restores requested line")


func test_open_route_keeps_preferred_width() -> void:
	var grid = NavigationGrid.new(Vector2i(24, 16))
	grid.configure_terrain(func(_cell): return "grass")
	var finder = Pathfinder.new(grid)
	var plan := FormationCorridor.plan(Vector2(5.5, 8.5), Vector2(18.5, 8.5), FormationGeometry.BLOCK, 7, 1.0, 0.3, finder, grid)
	assert_equal(plan["has_compression"], false, "open field needs no compression")
	for mode in plan["modes"]:
		assert_equal(mode, "preferred", "open route preserves selected form")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
