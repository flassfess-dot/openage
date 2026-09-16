extends SceneTree

const AiStrategicPlanner := preload("res://scripts/ai_strategic_planner.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.configure_players([
		{"team": 1, "controller": "human", "civilization_id": 13},
		{"team": 2, "controller": "ai", "civilization_id": 1},
		{"team": 3, "controller": "ai", "civilization_id": 4},
	])
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(3.0, 3.0), false)
	var neutral_worker: Dictionary = world.add_unit(2, "villager", Vector2(16.0, 16.0), false)
	attacker["combat_enabled"] = true
	attacker["behavior_tags"] = ["military", "combatant"]
	neutral_worker["behavior_tags"] = ["worker", "combatant"]
	attacker["components"]["vision"]["range"] = 24.0
	world.update_fog_of_war()
	var controller = GameController.new(world)

	var neutral = Commands.DiplomacyCommand.new(1, 2, "neutral")
	controller.enqueue_command(neutral, true, 1)
	controller.advance_frame(controller.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(neutral.sequence_id).get("accepted", false)), "neutral relation enters the authoritative command pipeline")
	assert_equal(world.team_relation(1, 2), "neutral", "issuer owns the changed relation")
	assert_equal(world.team_relation(2, 1), "enemy", "reverse relation remains unchanged")
	assert_true(not world.visibility_system.fog.are_allied(1, 2), "neutral relation does not share sight")

	var snapshot := SimulationSnapshot.presentation(world, controller.tick_index, 1)
	assert_equal(snapshot.get("player_state", {}).get("relations", {}).get(2), "neutral", "presentation exposes the observer relation matrix")
	var ai_goal := AiStrategicPlanner.choose_goal(snapshot, 1, 0)
	assert_true(String(ai_goal.get("type", "")) != "attack", "strategic AI does not declare an attack on a neutral player")

	var explicit_attack = Commands.AttackCommand.new(2, [int(attacker["id"])], int(neutral_worker["id"]))
	controller.enqueue_command(explicit_attack, true, 1)
	controller.advance_frame(controller.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(explicit_attack.sequence_id).get("accepted", false)), "explicit player attack remains legal against a neutral target")

	var ally = Commands.DiplomacyCommand.new(3, 2, "ally")
	controller.enqueue_command(ally, true, 1)
	controller.advance_frame(controller.FIXED_STEP_SECONDS, 1, 2)
	assert_true(bool(controller.get_command_result(ally.sequence_id).get("accepted", false)), "ally relation is accepted")
	assert_true(world.visibility_system.fog.are_allied(1, 2), "directed ally relation shares target-team sight with the issuer")
	assert_true(not world.visibility_system.fog.are_allied(2, 1), "sight sharing remains directed")
	var friendly_attack = Commands.AttackCommand.new(4, [int(attacker["id"])], int(neutral_worker["id"]))
	controller.enqueue_command(friendly_attack, true, 1)
	controller.advance_frame(controller.FIXED_STEP_SECONDS, 1, 2)
	assert_equal(controller.get_command_result(friendly_attack.sequence_id).get("reason"), "friendly_target", "allied targets are protected authoritatively")

	var invalid = Commands.DiplomacyCommand.new(5, 99, "peace")
	controller.enqueue_command(invalid, true, 1)
	controller.advance_frame(controller.FIXED_STEP_SECONDS, 1, 2)
	assert_true(not bool(controller.get_command_result(invalid.sequence_id).get("accepted", true)), "invalid diplomacy command is rejected")

	if failures.is_empty():
		print("E5-001 directed diplomacy pipeline tests passed")
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
