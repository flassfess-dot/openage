extends SceneTree

const CombatAwarenessSystem := preload("res://scripts/combat_awareness_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_stance_rules()
	test_neutral_autonomous_targeting()
	test_multirate_awareness_deadlines()
	if failures.is_empty():
		print("I6-002 combat awareness stance tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_stance_rules() -> void:
	var world = open_world()
	var observer: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var near_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(5.0, 4.0), false)
	configure_awareness(observer, "passive", 6.0)
	configure_awareness(near_enemy, "passive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	assert_equal(awareness.collect_commands(world, 1).size(), 0, "passive stance never acquires")

	observer["stance"] = "defensive"
	assert_equal(awareness.collect_commands(world, 2).size(), 0, "defensive stance waits for retaliation")
	observer["retaliation_target_id"] = int(near_enemy["id"])
	var retaliation := awareness.collect_commands(world, 3)
	assert_equal(retaliation.size(), 1, "defensive stance reacts to recorded attacker")
	assert_equal(retaliation[0].target_unit_id, int(near_enemy["id"]), "retaliation preserves attacker identity")

	observer["retaliation_target_id"] = -1
	observer["stance"] = "stand_ground"
	observer["attack_range"] = 0.1
	near_enemy["pos"] = Vector2(6.5, 4.0)
	world.update_fog_of_war()
	assert_equal(awareness.collect_commands(world, 4).size(), 0, "stand-ground refuses targets outside weapon contact")
	near_enemy["pos"] = Vector2(4.6, 4.0)
	world.update_fog_of_war()
	assert_equal(awareness.collect_commands(world, 5).size(), 1, "stand-ground attacks without allowing a chase")

	observer["stance"] = "defensive"
	observer["retaliation_target_id"] = -1
	var ally: Dictionary = world.add_unit(1, "clubman", Vector2(4.2, 4.4), false)
	configure_awareness(ally, "passive", 6.0)
	ally["retaliation_target_id"] = int(near_enemy["id"])
	world.update_fog_of_war()
	assert_equal(awareness.collect_commands(world, 6).size(), 1, "defensive stance assists a nearby attacked ally")


func configure_awareness(unit: Dictionary, stance: String, sight: float) -> void:
	unit["combat_enabled"] = true
	unit["stance"] = stance
	unit["acquisition_range"] = sight
	unit["chase_range"] = sight * 2.0
	unit["components"]["vision"]["range"] = sight
	unit["components"]["vision"]["enabled"] = true


func test_neutral_autonomous_targeting() -> void:
	var world = open_world()
	world.configure_players([
		{"team": 1, "controller": "human", "civilization_id": 13},
		{"team": 2, "controller": "ai", "civilization_id": 1},
	])
	var observer: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var worker: Dictionary = world.add_unit(2, "villager", Vector2(4.8, 4.0), false)
	var soldier: Dictionary = world.add_unit(2, "clubman", Vector2(5.2, 4.0), false)
	observer["behavior_tags"] = ["military", "combatant"]
	worker["behavior_tags"] = ["worker", "combatant"]
	soldier["behavior_tags"] = ["military", "combatant"]
	configure_awareness(observer, "aggressive", 6.0)
	configure_awareness(worker, "passive", 6.0)
	configure_awareness(soldier, "passive", 6.0)
	assert_true(world.set_diplomacy_relation(1, 2, "neutral"), "directed neutral relation is accepted")
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	var commands := awareness.collect_commands(world, 1)
	assert_equal(commands.size(), 1, "neutral military remains an autonomous local threat")
	assert_equal(commands[0].target_entity_id, int(soldier["id"]), "neutral worker is skipped in favour of military")
	soldier["hp"] = 0.0
	assert_equal(awareness.collect_commands(world, 2).size(), 0, "neutral worker is never acquired autonomously")
	assert_equal(world.team_relation(2, 1), "enemy", "neutral stance does not mutate the reverse player relation")


func test_multirate_awareness_deadlines() -> void:
	var world = open_world()
	var observer: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(5.0, 4.0), false)
	configure_awareness(observer, "aggressive", 6.0)
	configure_awareness(enemy, "passive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	# Cell (1, 1) has aggressive phase 1 modulo 4. Starting immediately
	# after that phase must still discover a local threat by the next window.
	assert_equal(awareness.collect_commands(world, 2).size(), 0, "ordinary scan may be distributed off its phase")
	assert_equal(awareness.collect_commands(world, 3).size(), 0, "ordinary scan remains distributed on the second off-phase")
	assert_equal(awareness.collect_commands(world, 4).size(), 0, "ordinary scan remains distributed on the third off-phase")
	var deadline_commands := awareness.collect_commands(world, 5)
	assert_equal(deadline_commands.size(), 1, "aggressive acquisition occurs within the four-tick deadline")
	assert_equal(deadline_commands[0].target_entity_id, int(enemy["id"]), "deadline scan preserves exact target identity")

	# Attack-move is an explicit combat intent and therefore bypasses the
	# background cadence even when the spatial phase is not due.
	observer["task"] = "attack_move"
	assert_equal(awareness.collect_commands(world, 2).size(), 1, "attack-move scans immediately off-phase")


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
