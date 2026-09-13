extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_command_results_and_events()
	test_future_command_has_no_early_result()
	if failures.is_empty():
		print("I1-002 command result integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_command_results_and_events() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var player: Dictionary = world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(14.0, 14.0), false)
	var controller = GameController.new(world)
	var move = Commands.MoveCommand.new(1, [player["id"]], Vector2(8.0, 8.0))
	var invalid_attack = Commands.AttackCommand.new(1, [player["id"]], -1)
	var foreign_move = Commands.MoveCommand.new(1, [enemy["id"]], Vector2(4.0, 4.0))
	controller.enqueue_command(move, true, 1)
	controller.enqueue_command(invalid_attack, true, 1)
	controller.enqueue_command(foreign_move, true, 1)
	controller.advance_frame(0.05, 1, 2)

	var move_result := controller.get_command_result(move.sequence_id)
	var attack_result := controller.get_command_result(invalid_attack.sequence_id)
	var foreign_result := controller.get_command_result(foreign_move.sequence_id)
	assert_true(bool(move_result.get("accepted", false)), "valid command is accepted")
	assert_equal(attack_result.get("reason"), "invalid_target", "invalid target has stable rejection code")
	assert_equal(foreign_result.get("reason"), "no_eligible_units", "issuer cannot command foreign unit")
	assert_equal(move_result.get("issuer_id"), 1, "result preserves issuer")
	assert_equal(move_result.get("applied_tick"), 1, "result preserves applied tick")

	var events: Array = controller.events_after()
	assert_equal(events.size(), 4, "due commands emit results and accepted task transition")
	assert_equal(events[0]["type"], "command_accepted", "accepted event is first")
	assert_equal(events[1]["type"], "task_changed", "accepted command emits task transition")
	assert_equal(events[1]["payload"]["previous_task"], "idle", "task transition keeps previous state")
	assert_equal(events[1]["payload"]["current_task"], "move", "task transition keeps current state")
	assert_equal(events[2]["type"], "command_rejected", "rejected event follows deterministic command order")
	assert_equal(events[3]["payload"]["sequence_id"], foreign_move.sequence_id, "event references command envelope")
	assert_equal(controller.events_after(int(events[0]["sequence_id"])).size(), 3, "event cursor returns only unseen events")


func test_future_command_has_no_early_result() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "villager", Vector2(2.0, 2.0), false)
	world.add_unit(2, "clubman", Vector2(14.0, 14.0), false)
	var controller = GameController.new(world)
	var command = Commands.MoveCommand.new(2, [unit["id"]], Vector2(7.0, 7.0))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_true(controller.get_command_result(command.sequence_id).is_empty(), "future command has no speculative result")
	assert_equal(controller.events_after().size(), 0, "future command emits no early event")
	controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "future command is accepted on scheduled tick")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
