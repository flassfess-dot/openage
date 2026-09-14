extends SceneTree

const SimulationTickPipeline := preload("res://scripts/simulation_tick_pipeline.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_pipeline_executes_registered_order()
	test_world_exposes_stable_tick_order()
	if failures.is_empty():
		print("I1-005 simulation tick pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_pipeline_executes_registered_order() -> void:
	var pipeline = SimulationTickPipeline.new()
	var trace: Array[String] = []
	pipeline.add_active("first", func(context): trace.append("first:%d" % int(context["tick"])))
	pipeline.add_active("second", func(context): trace.append("second:%d" % int(context["tick"])))
	pipeline.add_completed("terminal", func(context): trace.append("terminal:%d" % int(context["tick"])))
	assert_equal(pipeline.run(false, {"tick": 3}), ["first", "second"], "active pipeline reports executed order")
	assert_equal(trace, ["first:3", "second:3"], "active pipeline executes in registration order")
	trace.clear()
	assert_equal(pipeline.run(true, {"tick": 4}), ["terminal"], "completed pipeline has separate order")
	assert_equal(trace, ["terminal:4"], "completed pipeline executes only terminal systems")


func test_world_exposes_stable_tick_order() -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	assert_equal(world.tick_system_order(), [
		"capture_previous_positions", "ai_distress", "trade_goods", "unit_orders", "capturable_objectives", "static_combat", "death_lifecycle", "resource_lifecycle", "production", "projectiles",
		"victory", "purge", "spatial_index", "fog", "component_sync",
	], "active world tick order")
	assert_equal(world.tick_system_order(true), [
		"death_lifecycle", "resource_lifecycle", "projectiles", "purge", "spatial_index", "fog", "component_sync",
	], "completed world tick order")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
