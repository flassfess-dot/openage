extends SceneTree

const Footprint := preload("res://scripts/footprint.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_terrain_and_bounds()
	test_dynamic_resource_and_building_occupancy()
	test_surface_components()

	if failures.is_empty():
		print("N-003 navigation grid tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_terrain_and_bounds() -> void:
	var grid = NavigationGrid.new(Vector2i(16, 16))
	assert_equal(grid.terrain(Vector2i(0, 5)), "water", "water terrain")
	assert_equal(grid.is_walkable(Vector2i(0, 5)), false, "water is blocked")
	assert_equal(grid.terrain(Vector2i(2, 5)), "shore", "shore terrain")
	assert_equal(grid.is_walkable(Vector2i(2, 5)), true, "shore is walkable")
	assert_equal(grid.is_walkable(Vector2i(5, 5)), true, "land is walkable")
	assert_equal(grid.is_walkable(Vector2i(-1, 5)), false, "outside grid is blocked")


func test_dynamic_resource_and_building_occupancy() -> void:
	var grid = NavigationGrid.new(Vector2i(20, 20))
	var resource := {"id": 8, "pos": Vector2(7.2, 8.7), "amount": 75}
	var footprint := Footprint.building({"selection_radius": [1.5, 1.5, 2.0]}, Vector2(12, 12))
	var building := {"id": 20, "pos": Vector2(12, 12), "hp": 100.0, "occupied_cells": footprint["occupied_cells"]}
	grid.rebuild([resource], [building])
	assert_equal(grid.is_walkable(Vector2i(7, 8)), false, "resource cell blocked")
	assert_equal(grid.occupants(Vector2i(7, 8))[0]["category"], "resource", "resource occupant category")
	assert_equal(grid.is_walkable(Vector2i(12, 12)), false, "building center blocked")
	assert_equal(grid.occupants(Vector2i(12, 12))[0]["category"], "building", "building occupant category")
	resource["amount"] = 0
	building["hp"] = 0.0
	grid.rebuild([resource], [building])
	assert_equal(grid.is_walkable(Vector2i(7, 8)), true, "depleted resource releases cell")
	assert_equal(grid.is_walkable(Vector2i(12, 12)), true, "destroyed building releases cells")


func test_surface_components() -> void:
	var grid = NavigationGrid.new(Vector2i(12, 8))
	grid.configure_terrain(func(cell): return "water" if cell.x == 6 else "grass")
	var left := grid.surface_component_id(Vector2i(2, 3), "land")
	var same_left := grid.surface_component_id(Vector2i(5, 6), "land")
	var right := grid.surface_component_id(Vector2i(9, 3), "land")
	assert_equal(left, same_left, "one landmass shares a stable surface component")
	assert_true(left != right, "water separates land surface components")
	grid.rebuild([{"id": 8, "pos": Vector2(3.5, 3.5), "amount": 10}], [])
	assert_equal(grid.surface_component_id(Vector2i(5, 6), "land"), left, "dynamic occupancy does not invalidate geographic components")
	grid.set_terrain(Vector2i(6, 3), "grass")
	assert_equal(grid.surface_component_id(Vector2i(2, 3), "land"), grid.surface_component_id(Vector2i(9, 3), "land"), "terrain edits invalidate and reconnect cached components")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
