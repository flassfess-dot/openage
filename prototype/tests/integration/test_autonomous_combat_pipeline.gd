extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const CommandFeedbackRouter := preload("res://scripts/command_feedback_router.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_aggressive_units_use_common_command_pipeline()
	test_stance_command_precedes_awareness()
	test_attack_move_chains_targets_and_keeps_destination()
	test_enemy_building_is_a_first_class_combat_target()
	test_manual_move_ignores_visible_enemy_building()
	test_lost_visibility_and_leash_end_autonomous_contact()
	if failures.is_empty():
		print("I6-003 autonomous combat integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_aggressive_units_use_common_command_pipeline() -> void:
	var world = open_world()
	var attacker: Dictionary = fighter(world, 1, Vector2(4.0, 4.0), "aggressive")
	var enemy: Dictionary = fighter(world, 2, Vector2(7.0, 4.0), "passive")
	world.update_fog_of_war()
	var controller := GameController.new(world)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(attacker["task"], "attack", "aggressive unit acquires without an entity click")
	assert_equal(attacker["target_id"], enemy["id"], "perception choice reaches authoritative attack task")
	var command_events := controller.events_after().filter(func(event): return String(event["type"]) == "command_accepted")
	assert_true(not command_events.is_empty(), "autonomous intent emits the normal command result")
	assert_equal(command_events[0]["payload"]["issuer_id"], 1, "autonomous command is issued by the owning team")
	var router := CommandFeedbackRouter.new()
	assert_equal(router.consume(controller.events_after(), 1), [], "derived command does not fake pointer feedback")


func test_stance_command_precedes_awareness() -> void:
	var world = open_world()
	var attacker: Dictionary = fighter(world, 1, Vector2(4.0, 4.0), "aggressive")
	fighter(world, 2, Vector2(6.0, 4.0), "passive")
	world.update_fog_of_war()
	var controller := GameController.new(world)
	var stance_command = Commands.StanceCommand.new(1, [int(attacker["id"])], "passive")
	controller.enqueue_command(stance_command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(attacker["stance"], "passive", "stance is applied through the command pipeline")
	assert_equal(attacker["task"], "idle", "same-tick awareness sees the new passive stance")
	assert_true(bool(controller.get_command_result(stance_command.sequence_id).get("accepted", false)), "stance command receives an authoritative result")


func test_attack_move_chains_targets_and_keeps_destination() -> void:
	var world = open_world()
	var attacker: Dictionary = fighter(world, 1, Vector2(3.0, 6.0), "aggressive")
	var first: Dictionary = fighter(world, 2, Vector2(5.5, 6.0), "passive")
	var second: Dictionary = fighter(world, 2, Vector2(7.0, 6.0), "passive")
	world.update_fog_of_war()
	var controller := GameController.new(world)
	var destination := Vector2(13.0, 6.0)
	var attack_move = Commands.AttackMoveCommand.new(1, [int(attacker["id"])], destination)
	controller.enqueue_command(attack_move, true, 1)
	controller.advance_frame(0.05, 1, 2)
	assert_equal(attacker["target_id"], first["id"], "attack-move acquires the first target")
	assert_equal(attacker["combat_resume"]["task"], "attack_move", "attack-move destination is retained while engaged")

	first["hp"] = 0.0
	controller.advance_frame(0.05, 1, 2)
	assert_equal(attacker["target_id"], second["id"], "dead target is deterministically chained to the next one")
	assert_equal(attacker["combat_resume"]["destination"], destination, "target chaining does not discard the march destination")

	second["hp"] = 0.0
	controller.advance_frame(0.05, 1, 2)
	assert_equal(attacker["task"], "attack_move", "unit resumes attack-move after no targets remain")
	assert_equal(attacker["destination"], destination, "resumed order keeps its original endpoint")


func test_enemy_building_is_a_first_class_combat_target() -> void:
	var world = open_world()
	var attacker: Dictionary = fighter(world, 1, Vector2(6.0, 6.0), "passive")
	attacker["attack_damage"] = 10.0
	attacker["attack_period"] = 0.1
	var building: Dictionary = world.add_building(90, "town_center", Vector2(7.0, 6.0), 2)
	building["hp"] = 5.0
	building["max_hp"] = 5.0
	world.update_fog_of_war()
	var controller := GameController.new(world)
	var attack = Commands.AttackCommand.new(1, [int(attacker["id"])], int(building["id"]))
	controller.enqueue_command(attack, true, 1)
	for _tick in range(40):
		controller.advance_frame(0.05, 1, 2)
		if float(building.get("hp", 0.0)) <= 0.0:
			break
	assert_true(bool(controller.get_command_result(attack.sequence_id).get("accepted", false)), "building attack uses the normal command result")
	assert_equal(float(building["hp"]), 0.0, "destroyed building leaves combat and victory presence immediately")
	assert_true(String(building.get("death_phase", "")) in ["dying", "ruin"], "destroyed building leaves a temporary visual wreck")
	var deaths := controller.events_after().filter(func(event): return String(event["type"]) == "death" and String(event["payload"].get("entity_category", "")) == "building")
	assert_equal(deaths.size(), 1, "building destruction emits one typed death event")


func test_manual_move_ignores_visible_enemy_building() -> void:
	var world = open_world()
	var soldier: Dictionary = fighter(world, 1, Vector2(4.0, 4.0), "aggressive")
	var enemy_building: Dictionary = world.add_building(90, "house", Vector2(6.0, 4.0), 2)
	world.update_fog_of_war()
	var controller := GameController.new(world)
	var destination := Vector2(4.0, 12.0)
	var manual_move = Commands.MoveCommand.new(1, [int(soldier["id"])], destination)
	controller.enqueue_command(manual_move, true, 1)
	for _tick in range(10):
		controller.advance_frame(0.05, 1, 2)
	assert_true(bool(controller.get_command_result(manual_move.sequence_id).get("accepted", false)), "manual move is accepted before autonomous scan")
	assert_equal(String(soldier["task"]), "move", "manual move remains active after repeated enemy-building scans")
	assert_equal(int(soldier.get("target_id", -1)), -1, "visible enemy building never replaces the player target")
	assert_equal(Vector2(soldier["destination"]), destination, "manual destination survives awareness")
	assert_true(float(enemy_building["hp"]) > 0.0, "soldier does not attack the building during manual movement")


func test_lost_visibility_and_leash_end_autonomous_contact() -> void:
	var hidden_world = open_world()
	var seeker: Dictionary = fighter(hidden_world, 1, Vector2(3.0, 3.0), "aggressive")
	var hidden_enemy: Dictionary = fighter(hidden_world, 2, Vector2(5.0, 3.0), "passive")
	hidden_world.update_fog_of_war()
	var hidden_controller := GameController.new(hidden_world)
	hidden_controller.advance_frame(0.05, 1, 2)
	hidden_enemy["pos"] = Vector2(18.0, 18.0)
	hidden_world.update_fog_of_war()
	hidden_controller.advance_frame(0.05, 1, 2)
	assert_equal(seeker["task"], "idle", "autonomous attacker stops after losing target visibility")
	assert_equal(seeker["diagnostic_reason"], "combat_complete:target_lost", "lost visibility has a stable terminal reason")

	var leash_world = open_world()
	var guarded: Dictionary = fighter(leash_world, 1, Vector2(3.0, 8.0), "aggressive")
	guarded["chase_range"] = 4.0
	var runner: Dictionary = fighter(leash_world, 2, Vector2(5.0, 8.0), "passive")
	leash_world.update_fog_of_war()
	var leash_controller := GameController.new(leash_world)
	leash_controller.advance_frame(0.05, 1, 2)
	runner["pos"] = Vector2(9.0, 8.0)
	leash_world.update_fog_of_war()
	leash_controller.advance_frame(0.05, 1, 2)
	assert_equal(guarded["task"], "idle", "attacker does not reacquire beyond its original leash")
	assert_equal(guarded["diagnostic_reason"], "combat_complete:leash_exceeded", "leash exit has a stable terminal reason")


func fighter(world, team: int, position: Vector2, stance: String) -> Dictionary:
	var unit: Dictionary = world.add_unit(team, "clubman", position, false)
	unit["combat_enabled"] = true
	unit["stance"] = stance
	unit["acquisition_range"] = 6.0
	unit["chase_range"] = 12.0
	unit["components"]["vision"]["range"] = 8.0
	unit["components"]["vision"]["enabled"] = true
	return unit


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
