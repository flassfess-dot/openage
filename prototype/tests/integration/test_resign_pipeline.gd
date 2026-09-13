extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.configure_players([
		{"team": 1, "controller": "human", "civilization_id": 13},
		{"team": 2, "controller": "ai", "civilization_id": 13},
	])
	world.reset_game(false)
	var human: Dictionary = world.add_unit(1, "clubman", Vector2(4, 4), false)
	world.add_unit(2, "clubman", Vector2(10, 10), false)
	var controller = GameController.new(world)
	var resign = Commands.ResignCommand.new(1)
	controller.enqueue_command(resign, true, 1)
	controller.advance_frame(0.05, 1, 2)

	assert_true(bool(controller.get_command_result(resign.sequence_id).get("accepted", false)), "resign passes normal command result boundary")
	assert_equal(world.player_registry.status(1), "resigned", "issuer keeps explicit resigned state")
	assert_equal(world.player_registry.status(2), "victorious", "remaining player wins conquest")
	assert_equal(world.get_victory_result().get("winner_team"), 2, "victory system resolves remaining active player")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "player_resigned" and int(event.get("payload", {}).get("team", 0)) == 1), "resign emits typed domain event")

	var illegal_move = Commands.MoveCommand.new(2, [int(human["id"])], Vector2(6, 6))
	controller.enqueue_command(illegal_move, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(controller.get_command_result(illegal_move.sequence_id).get("reason"), "player_not_active", "terminal player cannot issue later commands")

	if failures.is_empty():
		print("I11-007 resign and terminal command pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
