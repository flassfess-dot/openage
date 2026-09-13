extends SceneTree

const DestinationReservations := preload("res://scripts/destination_reservations.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_destinations_are_unique_and_deterministic()
	test_move_completion_requires_reserved_place()

	if failures.is_empty():
		print("N-006 destination reservation tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_destinations_are_unique_and_deterministic() -> void:
	var grid = NavigationGrid.new(Vector2i(12, 12))
	grid.configure_terrain(func(_cell: Vector2i) -> String: return "land")
	var reservations = DestinationReservations.new()
	var first: Vector2 = reservations.reserve(1, Vector2(6.0, 6.0), 0.3, grid, 10)
	var second: Vector2 = reservations.reserve(2, Vector2(6.0, 6.0), 0.3, grid, 10)
	assert_equal(first, Vector2(6.0, 6.0), "first unit keeps requested slot")
	assert_true(second != first, "second unit gets another slot")
	assert_true(second.distance_to(first) >= 0.62, "reserved footprints do not overlap")
	var repeated = DestinationReservations.new()
	repeated.reserve(1, Vector2(6.0, 6.0), 0.3, grid, 10)
	assert_equal(repeated.reserve(2, Vector2(6.0, 6.0), 0.3, grid, 10), second, "tie-break is deterministic")


func test_move_completion_requires_reserved_place() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(3.0, 3.0), false)
	world.assign_command_move([unit], Vector2(7.0, 7.0))
	assert_equal(unit["task"], "move", "move starts with reservation")
	assert_equal(unit["reserved_destination"], Vector2(7.0, 7.0), "destination is reserved")
	unit["pos"] = Vector2(6.8, 7.0)
	assert_equal(world.destination_reservations.is_occupied(unit), false, "nearby is not occupied")
	unit["pos"] = Vector2(7.0, 7.0)
	assert_equal(world.destination_reservations.is_occupied(unit), true, "exact slot is occupied")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
