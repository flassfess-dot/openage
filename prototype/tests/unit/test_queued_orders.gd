extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_shift_move_waits_for_active_route()
	test_unavailable_stage_is_skipped()
	test_depleted_resource_stage_is_skipped()
	test_dead_target_stage_is_skipped()
	test_bounded_queue_rejects_overflow()
	test_replay_and_canonical_state_preserve_queue()
	if failures.is_empty():
		print("P02 queued order tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_shift_move_waits_for_active_route() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(unit["id"])]
	var first = Commands.MoveCommand.new(1, ids, Vector2(5, 3))
	var second = Commands.MoveCommand.new(1, ids, Vector2(9, 3))
	second.params["queue_order"] = true
	controller.enqueue_command(first, true, 1)
	controller.enqueue_command(second, true, 1)
	advance_tick(controller)
	assert_true(not world.is_battle_over(), "queue fixture remains active after the first tick")
	assert_true(bool(controller.get_command_result(second.sequence_id).get("accepted", false)), "Shift move is accepted as a deferred order")
	assert_equal(Vector2(unit.get("target", Vector2.ZERO)), Vector2(5, 3), "queued move does not plan a route before the active move finishes")
	assert_equal(OrderPipeline.queued(unit).size(), 1, "one deferred move remains after the first tick")
	var second_started := false
	for _tick in range(400):
		advance_tick(controller)
		if Vector2(unit.get("target", Vector2.ZERO)) == Vector2(9, 3):
			second_started = true
			break
	assert_true(second_started, "queued move starts after the first route completes")
	assert_equal(OrderPipeline.queued(unit).size(), 0, "started move leaves the pending deque")


func test_unavailable_stage_is_skipped() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(unit["id"])]
	var first = Commands.MoveCommand.new(1, ids, Vector2(5, 3))
	var exhausted = Commands.GatherCommand.new(1, ids, 99999)
	exhausted.params["queue_order"] = true
	var third = Commands.MoveCommand.new(1, ids, Vector2(8, 3))
	third.params["queue_order"] = true
	controller.enqueue_command(first, true, 1)
	controller.enqueue_command(exhausted, true, 1)
	controller.enqueue_command(third, true, 1)
	advance_tick(controller)
	var third_started := false
	for _tick in range(400):
		advance_tick(controller)
		if Vector2(unit.get("target", Vector2.ZERO)) == Vector2(8, 3):
			third_started = true
			break
	assert_true(third_started, "unavailable gather stage is skipped and the later move begins")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "queued_order_rejected" and String(event.get("payload", {}).get("reason", "")) == "resource_unavailable"), "unavailable target has an explicit queued-order rejection")


func test_depleted_resource_stage_is_skipped() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var resource: Dictionary = world.add_resource("tree", Vector2(10, 8), 10)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(unit["id"])]
	controller.enqueue_command(Commands.MoveCommand.new(1, ids, Vector2(5, 3)), true, 1)
	var gather = Commands.GatherCommand.new(1, ids, int(resource["id"]))
	gather.params["queue_order"] = true
	controller.enqueue_command(gather, true, 1)
	var next_move = Commands.MoveCommand.new(1, ids, Vector2(8, 3))
	next_move.params["queue_order"] = true
	controller.enqueue_command(next_move, true, 1)
	advance_tick(controller)
	resource["amount"] = 0
	var next_started := false
	for _tick in range(400):
		advance_tick(controller)
		if Vector2(unit.get("target", Vector2.ZERO)) == Vector2(8, 3):
			next_started = true
			break
	assert_true(next_started, "depleted resource does not trap the deferred queue")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "queued_order_rejected" and String(event.get("payload", {}).get("reason", "")) == "resource_unavailable"), "depleted resource stage reports its reason")


func test_dead_target_stage_is_skipped() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var enemy: Dictionary = world.add_unit(2, "villager", Vector2(10, 8), false)
	unit["combat_enabled"] = true
	unit["stance"] = "passive"
	enemy["stance"] = "passive"
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(unit["id"])]
	controller.enqueue_command(Commands.MoveCommand.new(1, ids, Vector2(5, 3)), true, 1)
	var attack = Commands.AttackCommand.new(1, ids, int(enemy["id"]))
	attack.params["queue_order"] = true
	controller.enqueue_command(attack, true, 1)
	var next_move = Commands.MoveCommand.new(1, ids, Vector2(8, 3))
	next_move.params["queue_order"] = true
	controller.enqueue_command(next_move, true, 1)
	advance_tick(controller)
	world.begin_entity_death(enemy)
	var next_started := false
	for _tick in range(400):
		advance_tick(controller)
		if Vector2(unit.get("target", Vector2.ZERO)) == Vector2(8, 3):
			next_started = true
			break
	assert_true(next_started, "dead attack target does not trap the deferred queue")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "queued_order_rejected" and String(event.get("payload", {}).get("reason", "")) == "invalid_target"), "dead target stage reports its reason")


func test_bounded_queue_rejects_overflow() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var ids: Array[int] = [int(unit["id"])]
	controller.enqueue_command(Commands.MoveCommand.new(1, ids, Vector2(15, 3)), true, 1)
	var overflow = null
	for index in range(OrderPipeline.MAX_QUEUED_ORDERS + 1):
		var deferred = Commands.MoveCommand.new(1, ids, Vector2(4 + index % 8, 5))
		deferred.params["queue_order"] = true
		controller.enqueue_command(deferred, true, 1)
		overflow = deferred
	advance_tick(controller)
	assert_equal(OrderPipeline.queued(unit).size(), OrderPipeline.MAX_QUEUED_ORDERS, "pending deque remains at the fixed capacity")
	assert_equal(String(controller.get_command_result(overflow.sequence_id).get("reason", "")), "order_queue_full", "overflow is rejected instead of silently dropping an old order")


func test_replay_and_canonical_state_preserve_queue() -> void:
	var world = open_world()
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(3, 3), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	controller.start_recording(41721)
	var ids: Array[int] = [int(unit["id"])]
	controller.enqueue_command(Commands.MoveCommand.new(1, ids, Vector2(15, 3)), true, 1)
	var deferred = Commands.MoveCommand.new(1, ids, Vector2(9, 3))
	deferred.params["queue_order"] = true
	controller.enqueue_command(deferred, true, 1)
	advance_tick(controller)
	var canonical: Dictionary = SimulationSnapshot.canonical(world, controller.tick_index, controller)
	var canonical_order: Dictionary = canonical["world"]["units"][0]["components"]["order"]
	assert_equal(canonical_order.get("queued", []).size(), 1, "canonical save state contains the deferred order")
	var recorded = controller.stop_recording()
	var replay_world = open_world()
	replay_world.add_unit(1, "villager", Vector2(3, 3), false)
	var replay_controller = GameController.new(replay_world)
	assert_true(replay_controller.load_replay(recorded.to_dictionary()), "recorded Shift sequence loads into replay controller")
	assert_true(replay_controller.replay_until_tick(controller.tick_index, 1, 2), "replay reaches the same deferred-order tick")
	var verifier = ReplaySystem.new()
	assert_equal(verifier.world_state_hash(replay_world, replay_controller.tick_index, replay_controller), verifier.world_state_hash(world, controller.tick_index, controller), "deferred order has the same canonical replay hash")
	var replay = ReplaySystem.new()
	replay.begin(41721)
	replay.record_command(deferred)
	var loaded = ReplaySystem.new()
	assert_true(loaded.load_json(replay.to_json()), "queued command replay JSON loads")
	var restored = loaded.command_from_record(loaded.command_records[0])
	assert_true(bool(restored.params.get("queue_order", false)), "replay preserves the Shift append policy")
	assert_equal(Vector2(restored.target), Vector2(9, 3), "replay preserves the later world destination")
	var replacement = Commands.MoveCommand.new(controller.tick_index + 1, ids, Vector2(4, 8))
	controller.enqueue_command(replacement, true, 1)
	advance_tick(controller)
	assert_equal(OrderPipeline.queued(unit).size(), 0, "ordinary move replaces the pending deque")


func open_world():
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec({"units": {"villager": {"hit_points": 25.0, "speed": 1.0, "resource_cost": [{"type_id": 4, "amount": 1, "enabled": false}]}}})
	# These isolated order fixtures have no competing army. Conquest would end
	# the match on tick one and stop the active unit-order pipeline entirely.
	world.configure_victory_rules([{"type": "score", "score_limit": 9999999}])
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	return world


func advance_tick(controller) -> void:
	controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
