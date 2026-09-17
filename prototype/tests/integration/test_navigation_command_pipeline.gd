extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_reachable_command_resolves_and_arrives()
	test_open_group_move_registers_shared_validation()
	test_blocked_group_move_falls_back_to_individual_paths()
	test_unreachable_command_is_explicitly_rejected()

	if failures.is_empty():
		print("I4-002 navigation command integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_reachable_command_resolves_and_arrives() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(2.5, 2.5), false)
	world.add_unit(2, "clubman", Vector2(17.5, 17.5), false)
	var controller = GameController.new(world)
	var destination := Vector2(10.5, 9.5)
	var command = Commands.MoveCommand.new(1, [int(unit["id"])], destination)
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "reachable move is accepted")
	assert_equal(unit["path_status"], "resolved", "accepted move consumed resolved path result")
	assert_true(int(unit["path_request_id"]) > 0, "accepted move exposes request correlation")
	for _tick in range(500):
		controller.advance_frame(0.05, 1, 2)
		if String(unit["task"]) == "idle":
			break
	assert_equal(unit["task"], "idle", "unit completes reachable movement")
	assert_true(unit["pos"].distance_to(unit["reserved_destination"]) < 0.08, "unit occupies its reserved endpoint")


func test_open_group_move_registers_shared_validation() -> void:
	var world = open_world()
	var ids: Array[int] = []
	var destinations: Dictionary = {}
	for index in range(12):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(2.5 + index % 4, 2.5 + index / 4), false)
		ids.append(int(unit["id"]))
	var controller = GameController.new(world)
	var probe = PerformanceProbe.new()
	controller.set_performance_probe(probe)
	var command = Commands.MoveCommand.new(1, ids, Vector2(14.0, 14.0))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "open group move is accepted")
	assert_equal(int(probe.report().get("counters", {}).get("navigation.prevalidated_group_segments", 0)), ids.size(), "one open-envelope validation registers every direct member route")
	for unit_id in ids:
		var unit: Dictionary = world.find_unit(unit_id)
		var key := str(unit["reserved_destination"])
		assert_true(not destinations.has(key), "group move retains unique endpoint reservations")
		destinations[key] = true


func test_blocked_group_move_falls_back_to_individual_paths() -> void:
	var world = open_world()
	world.navigation_grid.set_terrain(Vector2i(8, 8), "water")
	var ids: Array[int] = []
	for index in range(4):
		var unit: Dictionary = world.add_unit(1, "clubman", Vector2(2.5, 2.5 + index), false)
		ids.append(int(unit["id"]))
	var controller = GameController.new(world)
	var probe = PerformanceProbe.new()
	controller.set_performance_probe(probe)
	var command = Commands.MoveCommand.new(1, ids, Vector2(14.0, 14.0))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	var report: Dictionary = probe.report()
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "blocked group move remains routable around the obstacle")
	assert_equal(int(report.get("counters", {}).get("navigation.prevalidated_group_segments", 0)), 0, "blocked envelope is not marked prevalidated")
	assert_equal(int(report.get("metrics_microseconds", {}).get("navigation.path_query", {}).get("count", 0)), ids.size(), "blocked envelope runs one individual path query per member")


func test_unreachable_command_is_explicitly_rejected() -> void:
	var world = SimulationWorld.new(Vector2i(10, 10))
	world.navigation_grid.configure_terrain(func(_cell): return "water")
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(2.5, 2.5), false)
	world.add_unit(2, "clubman", Vector2(8.5, 8.5), false)
	var controller = GameController.new(world)
	var command = Commands.MoveCommand.new(1, [int(unit["id"])], Vector2(7.5, 7.5))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	var result := controller.get_command_result(command.sequence_id)
	assert_equal(result["accepted"], false, "unreachable move is not acknowledged as success")
	assert_equal(result["reason"], "no_path", "unreachable move exposes stable rejection")
	assert_equal(unit["path_status"], "unreachable", "unit retains navigation result for diagnostics")
	assert_equal(unit["task"], "idle", "unreachable move leaves unit in stable state")


func open_world():
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	return world


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
