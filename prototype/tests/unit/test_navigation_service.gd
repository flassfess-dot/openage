extends SceneTree

const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const NavigationService := preload("res://scripts/navigation_service.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_deterministic_request_result_envelope()
	test_unreachable_result()
	test_world_records_latest_request()

	if failures.is_empty():
		print("I4-001 navigation request/result tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_deterministic_request_result_envelope() -> void:
	var service: NavigationService = service_for_terrain("grass")
	var first: Dictionary = service.request_path(7, Vector2(1.5, 1.5), Vector2(6.5, 6.5), "land", -1, "move")
	var second: Dictionary = service.request_path(7, Vector2(1.5, 1.5), Vector2(6.5, 6.5), "land", -1, "replan")
	assert_equal(first["request_id"], 1, "first request owns deterministic ID")
	assert_equal(second["request_id"], 2, "second request owns next deterministic ID")
	assert_equal(first["path"], second["path"], "same navigation state yields identical path")
	assert_equal(first["status"], "resolved", "reachable request has explicit status")
	assert_equal(first["grid_revision"], second["grid_revision"], "result records navigation revision")
	assert_equal(service.result_for(1)["entity_id"], 7, "result can be correlated by request ID")


func test_unreachable_result() -> void:
	var service: NavigationService = service_for_terrain("water")
	var result: Dictionary = service.request_path(4, Vector2(1.5, 1.5), Vector2(6.5, 6.5), "land")
	assert_equal(result["status"], "unreachable", "unreachable request is not an ambiguous empty array")
	assert_equal(result["reason"], "no_path", "unreachable result has stable reason")
	assert_equal(result["path"], [], "unreachable result carries empty route")


func test_world_records_latest_request() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(1.5, 1.5), false)
	world.assign_command_move([unit], Vector2(9.5, 9.5))
	assert_equal(unit["path_request_id"], 1, "world stores path request correlation")
	assert_equal(unit["path_status"], "resolved", "world exposes resolved status")
	assert_equal(unit["path_grid_revision"], world.navigation_grid.revision, "world records path grid revision")
	assert_true(not unit["path"].is_empty(), "world consumes path only from result envelope")


func service_for_terrain(kind: String) -> NavigationService:
	var grid = NavigationGrid.new(Vector2i(8, 8))
	grid.configure_terrain(func(_cell): return kind)
	return NavigationService.new(Pathfinder.new(grid))


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
