extends SceneTree

const Footprint := preload("res://scripts/footprint.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_terrain_and_bounds()
	test_dynamic_resource_and_building_occupancy()

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


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
