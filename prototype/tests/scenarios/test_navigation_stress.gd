extends SceneTree

const Footprint := preload("res://scripts/footprint.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_hundred_opposing_units()
	test_crossing_groups_with_shared_destination()
	test_narrow_forest_and_building_ring()

	if failures.is_empty():
		print("N-008 navigation stress tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_hundred_opposing_units() -> void:
	var world = SimulationWorld.new(Vector2i(64, 64))
	var moving_right: Array = []
	var moving_left: Array = []
	for index in range(50):
		var y := 6.0 + float(index)
		var right: Dictionary = world.add_unit(1, "clubman", Vector2(20.0, y), false)
		var left: Dictionary = world.add_unit(1, "clubman", Vector2(24.0, y), false)
		moving_right.append(right)
		moving_left.append(left)
		world.assign_command_move([right], Vector2(27.0, y))
		world.assign_command_move([left], Vector2(17.0, y))
	for _tick in range(90):
		for unit in world.get_units():
			unit["previous_pos"] = unit["pos"]
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
	var progressed_right := moving_right.filter(func(unit): return unit["pos"].x > 22.0).size()
	var progressed_left := moving_left.filter(func(unit): return unit["pos"].x < 22.0).size()
	assert_true(progressed_right >= 40, "most right-moving units pass the meeting line")
	assert_true(progressed_left >= 40, "most left-moving units pass the meeting line")
	for unit in world.get_units():
		assert_true(is_finite(unit["pos"].x) and is_finite(unit["pos"].y), "stress positions remain finite")
		assert_true(unit["pos"].x >= 0.0 and unit["pos"].y >= 0.0 and unit["pos"].x <= 64.0 and unit["pos"].y <= 64.0, "stress positions stay in world")


func test_crossing_groups_with_shared_destination() -> void:
	var world = SimulationWorld.new(Vector2i(48, 48))
	var destinations: Dictionary = {}
	for index in range(24):
		var unit: Dictionary = world.add_unit(1, "archer", Vector2(8.0 + float(index % 6), 8.0 + float(index / 6)), false)
		world.assign_command_move([unit], Vector2(30.0, 30.0))
		var reserved: Vector2 = unit["reserved_destination"]
		var key := "%0.3f:%0.3f" % [reserved.x, reserved.y]
		assert_true(not destinations.has(key), "shared destination assigns a unique slot")
		destinations[key] = true
	assert_equal(destinations.size(), 24, "all crossing-group destinations are unique")


func test_narrow_forest_and_building_ring() -> void:
	var grid = NavigationGrid.new(Vector2i(40, 40))
	grid.configure_terrain(func(_cell: Vector2i) -> String: return "land")
	var resources: Array = []
	for y in range(2, 38):
		if y in [19, 20]:
			continue
		resources.append({"id": 100 + y, "pos": Vector2(20.2, y + 0.2), "amount": 75})
	var building_footprint := Footprint.building({"selection_radius": [2.5, 2.5, 3.0]}, Vector2(30, 20))
	var building := {"id": 500, "pos": Vector2(30, 20), "hp": 500.0, "occupied_cells": building_footprint["occupied_cells"]}
	grid.rebuild(resources, [building])
	var finder = Pathfinder.new(grid)
	for start_y in [6.5, 12.5, 19.5, 27.5, 33.5]:
		var path := finder.find_path(Vector2(5.5, start_y), Vector2(35.5, start_y))
		assert_true(not path.is_empty(), "forest passage path exists from y=%s" % start_y)
		var previous := Vector2i(5, floori(start_y))
		for waypoint in path:
			var next := Vector2i(floori(waypoint.x), floori(waypoint.y))
			assert_true(finder.line_walkable(previous, next), "forest/building segment stays walkable")
			previous = next


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
