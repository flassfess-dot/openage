extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const PerformanceProbe := preload("res://scripts/performance_probe.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_summary_and_bounded_storage()
	test_observability_does_not_change_simulation()
	if failures.is_empty():
		print("E6-001 performance observability tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_summary_and_bounded_storage() -> void:
	var probe = PerformanceProbe.new(4)
	for value in [10, 20, 30, 40, 50]:
		probe.observe_microseconds("tick", value)
	probe.increment("paths", 2)
	probe.increment("paths", 3)
	var report: Dictionary = probe.report()
	var tick: Dictionary = report["metrics_microseconds"]["tick"]
	assert_equal(int(tick["count"]), 4, "sample storage is bounded")
	assert_equal(int(tick["p50"]), 30, "nearest-rank p50 is stable")
	assert_equal(int(tick["p95"]), 50, "nearest-rank p95 is stable")
	assert_equal(int(tick["max"]), 50, "maximum is stable")
	assert_equal(int(report["counters"]["paths"]), 5, "counters accumulate")


func test_observability_does_not_change_simulation() -> void:
	var baseline := moving_runtime(false)
	var measured := moving_runtime(true)
	for step in range(6):
		baseline["controller"].advance_frame(0.05, 1, 2)
		measured["controller"].advance_frame(0.05, 1, 2)
	var replay = ReplaySystem.new()
	var baseline_hash := replay.world_state_hash(baseline["world"], baseline["controller"].tick_index, baseline["controller"])
	var measured_hash := replay.world_state_hash(measured["world"], measured["controller"].tick_index, measured["controller"])
	assert_equal(measured_hash, baseline_hash, "wall-clock observability is absent from canonical state")
	var report: Dictionary = measured["probe"].report()
	assert_equal(int(report["metrics_microseconds"]["controller.fixed_tick"]["count"]), 6, "one fixed-tick sample is recorded per tick")
	assert_equal(int(report["metrics_microseconds"]["simulation.system.unit_orders"]["count"]), 6, "central systems expose per-tick cost")
	assert_true(int(report["counters"].get("navigation.path_queries", 0)) >= 1, "path queries are counted")
	assert_true(
		int(report["counters"].get("navigation.direct_path_hits", 0)) + int(report["counters"].get("navigation.expanded_nodes", 0)) >= 1,
		"direct and searched path resolutions are observable"
	)


func moving_runtime(measured: bool) -> Dictionary:
	var world = SimulationWorld.new(Vector2i(32, 32))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(2.5, 2.5), false)
	world.add_unit(2, "clubman", Vector2(29.5, 29.5), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var probe = PerformanceProbe.new()
	if measured:
		controller.set_performance_probe(probe)
	controller.enqueue_command(Commands.MoveCommand.new(1, [unit["id"]], Vector2(20.5, 2.5)))
	return {"world": world, "controller": controller, "probe": probe}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
