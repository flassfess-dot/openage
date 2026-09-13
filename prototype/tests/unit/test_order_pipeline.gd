extends SceneTree

const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_phase_contract()
	test_move_pipeline()
	test_attack_pipeline()
	test_gather_and_stop_pipeline()

	if failures.is_empty():
		print("S-002 order pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_phase_contract() -> void:
	assert_equal(OrderPipeline.PHASES, [
		"AcquireTarget", "PlanPath", "MoveIntoRange", "FaceTarget",
		"PerformAction", "Recover", "RepeatOrComplete",
	], "canonical order phases")


func test_move_pipeline() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(6.0, 6.0), false)
	world.assign_command_move([unit], Vector2(6.02, 6.0))
	var active: Dictionary = OrderPipeline.current(unit)
	assert_equal(active["type"], "move", "move order type")
	assert_equal(active["phase"], OrderPipeline.MOVE_INTO_RANGE, "move reaches path phase")
	for unused in range(3):
		world.move_unit(unit, 0.1)
		if unit["task"] == "idle":
			break
	var completed: Dictionary = OrderPipeline.current(unit)
	assert_true(completed["completed"], "move order completes")
	assert_equal(completed["completion_reason"], "destination_reached", "move completion reason")
	assert_subsequence(completed["history"], [OrderPipeline.ACQUIRE_TARGET, OrderPipeline.PLAN_PATH, OrderPipeline.MOVE_INTO_RANGE, OrderPipeline.REPEAT_OR_COMPLETE], "move phase order")


func test_attack_pipeline() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 5.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(5.6, 5.0), false)
	attacker["attack_period"] = 0.3
	world.assign_command_attack([attacker], int(target["id"]))
	for unused in range(5):
		world.update_units(0.1, 1, 2)
	var order: Dictionary = OrderPipeline.current(attacker)
	assert_equal(order["type"], "attack", "attack order type")
	assert_true(float(target["hp"]) < float(target["max_hp"]), "PerformAction applies attack")
	assert_subsequence(order["history"], [
		OrderPipeline.ACQUIRE_TARGET,
		OrderPipeline.PLAN_PATH,
		OrderPipeline.MOVE_INTO_RANGE,
		OrderPipeline.FACE_TARGET,
		OrderPipeline.PERFORM_ACTION,
		OrderPipeline.RECOVER,
		OrderPipeline.REPEAT_OR_COMPLETE,
	], "attack phase order")


func test_gather_and_stop_pipeline() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7.5, 7.5), false)
	var resource: Dictionary = world.add_resource("tree", Vector2(8.0, 7.5), 8)
	world.assign_command_gather([worker], int(resource["id"]))
	for unused in range(20):
		world.update_units(0.1, 1, 2)
		world.rebuild_spatial_index()
		if int(worker.get("gather_cycles", 0)) > 0:
			break
	var gathering: Dictionary = OrderPipeline.current(worker)
	assert_equal(gathering["type"], "gather", "gather order type")
	assert_subsequence(gathering["history"], [OrderPipeline.ACQUIRE_TARGET, OrderPipeline.FACE_TARGET, OrderPipeline.PERFORM_ACTION, OrderPipeline.RECOVER], "gather phase order")
	world.halt_unit(worker, "stop")
	var stopped: Dictionary = OrderPipeline.current(worker)
	assert_true(stopped["completed"], "stop completes active order")
	assert_equal(stopped["completion_reason"], "stop", "stop completion reason")
	assert_equal(worker["task"], "idle", "stop clears legacy task")


func assert_subsequence(actual: Array, expected: Array, context: String) -> void:
	var cursor := 0
	for value in actual:
		if cursor < expected.size() and value == expected[cursor]:
			cursor += 1
	if cursor != expected.size():
		failures.append("%s: expected subsequence %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
