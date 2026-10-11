extends SceneTree

const CombatAwarenessSystem := preload("res://scripts/combat_awareness_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_stance_rules()
	test_neutral_autonomous_targeting()
	test_multirate_awareness_deadlines()
	test_scout_only_retaliates()
	test_manual_orders_override_building_awareness()
	test_completed_building_uses_live_cached_roster()
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
	configure_awareness(world, observer, "passive", 6.0)
	configure_awareness(world, near_enemy, "passive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	assert_equal(awareness.collect_commands(world, 1).size(), 0, "passive stance never acquires")

	world.set_entity_field(observer, "stance", "defensive")
	assert_equal(awareness.collect_commands(world, 2).size(), 0, "defensive stance waits for retaliation")
	world.set_entity_field(observer, "retaliation_target_id", int(near_enemy["id"]))
	var retaliation := awareness.collect_commands(world, 3)
	assert_equal(retaliation.size(), 1, "defensive stance reacts to recorded attacker")
	if not retaliation.is_empty(): assert_equal(retaliation[0].target_unit_id, int(near_enemy["id"]), "retaliation preserves attacker identity")

	world.set_entity_field(observer, "retaliation_target_id", -1)
	world.set_entity_field(observer, "stance", "stand_ground")
	world.set_entity_field(observer, "attack_range", 0.1)
	world.set_entity_field(near_enemy, "pos", Vector2(6.5, 4.0))
	world.update_fog_of_war()
	assert_equal(awareness.collect_commands(world, 4).size(), 0, "stand-ground refuses targets outside weapon contact")
	world.set_entity_field(near_enemy, "pos", Vector2(4.6, 4.0))
	world.update_fog_of_war()
	assert_equal(awareness.collect_commands(world, 5).size(), 1, "stand-ground attacks without allowing a chase")

	world.set_entity_field(observer, "stance", "defensive")
	world.set_entity_field(observer, "retaliation_target_id", -1)
	var ally: Dictionary = world.add_unit(1, "clubman", Vector2(4.2, 4.4), false)
	configure_awareness(world, ally, "passive", 6.0)
	world.set_entity_field(ally, "retaliation_target_id", int(near_enemy["id"]))
	world.update_fog_of_war()
	assert_equal(awareness.collect_commands(world, 6).size(), 1, "defensive stance assists a nearby attacked ally")


func configure_awareness(world, unit: Dictionary, stance: String, sight: float) -> void:
	world.set_entity_field(unit, "combat_enabled", true)
	world.set_entity_field(unit, "stance", stance)
	world.set_entity_field(unit, "acquisition_range", sight)
	world.set_entity_field(unit, "chase_range", sight * 2.0)
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
	world.set_entity_field(observer, "behavior_tags", ["military", "combatant"])
	world.set_entity_field(worker, "behavior_tags", ["worker", "combatant"])
	world.set_entity_field(soldier, "behavior_tags", ["military", "combatant"])
	configure_awareness(world, observer, "aggressive", 6.0)
	configure_awareness(world, worker, "passive", 6.0)
	configure_awareness(world, soldier, "passive", 6.0)
	assert_true(world.set_diplomacy_relation(1, 2, "neutral"), "directed neutral relation is accepted")
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	var commands := awareness.collect_commands(world, 1)
	assert_equal(commands.size(), 1, "neutral military remains an autonomous local threat")
	if not commands.is_empty(): assert_equal(commands[0].target_entity_id, int(soldier["id"]), "neutral worker is skipped in favour of military")
	world.set_entity_field(soldier, "hp", 0.0)
	assert_equal(awareness.collect_commands(world, 2).size(), 0, "neutral worker is never acquired autonomously")
	assert_equal(world.team_relation(2, 1), "enemy", "neutral stance does not mutate the reverse player relation")


func test_multirate_awareness_deadlines() -> void:
	var world = open_world()
	var observer: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(5.0, 4.0), false)
	configure_awareness(world, observer, "aggressive", 6.0)
	configure_awareness(world, enemy, "passive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	# Cell (1, 1) has aggressive phase 1 modulo 4. Starting immediately
	# after that phase must still discover a local threat by the next window.
	assert_equal(awareness.collect_commands(world, 2).size(), 0, "ordinary scan may be distributed off its phase")
	assert_equal(awareness.collect_commands(world, 3).size(), 0, "ordinary scan remains distributed on the second off-phase")
	assert_equal(awareness.collect_commands(world, 4).size(), 0, "ordinary scan remains distributed on the third off-phase")
	var deadline_commands := awareness.collect_commands(world, 5)
	assert_equal(deadline_commands.size(), 1, "aggressive acquisition occurs within the four-tick deadline")
	if not deadline_commands.is_empty(): assert_equal(deadline_commands[0].target_entity_id, int(enemy["id"]), "deadline scan preserves exact target identity")

	# Attack-move is an explicit combat intent and therefore bypasses the
	# background cadence even when the spatial phase is not due.
	world.set_entity_field(observer, "task", "attack_move")
	assert_equal(awareness.collect_commands(world, 2).size(), 1, "attack-move scans immediately off-phase")


func test_scout_only_retaliates() -> void:
	var world = open_world()
	var scout: Dictionary = world.add_unit(1, "scout", Vector2(4.0, 4.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(5.0, 4.0), false)
	# This isolated world has no runtime catalog, so assign the behavior under test.
	world.set_entity_field(scout, "behavior_tags", ["scout", "combatant"])
	configure_awareness(world, scout, "aggressive", 6.0)
	configure_awareness(world, enemy, "passive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	assert_equal(awareness.collect_commands(world, 5).size(), 0, "Scout does not autonomously acquire a visible enemy")
	world.set_entity_field(scout, "retaliation_target_id", int(enemy["id"]))
	var responses := awareness.collect_commands(world, 6)
	assert_equal(responses.size(), 1, "Scout can retaliate against its attacker")
	if not responses.is_empty():
		assert_equal(int(responses[0].target_entity_id), int(enemy["id"]), "Scout retaliation retains its attacker")


func test_manual_orders_override_building_awareness() -> void:
	var world = open_world()
	var observer: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var enemy_building: Dictionary = world.add_building(800, "house", Vector2(5.0, 4.0), 2)
	configure_awareness(world, observer, "aggressive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	world.set_entity_field(observer, "task", "move")
	assert_equal(awareness.collect_commands(world, 5).size(), 0, "manual move is not replaced by visible enemy building")
	world.set_entity_field(observer, "task", "build")
	assert_equal(awareness.collect_commands(world, 5).size(), 0, "manual work is not replaced by visible enemy building")
	world.set_entity_field(observer, "task", "idle")
	var idle_commands := awareness.collect_commands(world, 5)
	assert_equal(idle_commands.size(), 1, "idle aggressive unit may acquire visible enemy building")
	if not idle_commands.is_empty():
		assert_equal(int(idle_commands[0].target_entity_id), int(enemy_building["id"]), "idle acquisition keeps building target")
	world.set_entity_field(observer, "task", "attack_move")
	assert_equal(awareness.collect_commands(world, 5).size(), 1, "explicit attack-move permits background target acquisition")


func test_completed_building_uses_live_cached_roster() -> void:
	var world = open_world()
	var tower: Dictionary = world.add_building(900, "tower", Vector2(4.0, 4.0), 1, false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(5.0, 4.0), false)
	configure_awareness(world, tower, "aggressive", 6.0)
	configure_awareness(world, enemy, "passive", 6.0)
	world.update_fog_of_war()
	var awareness := CombatAwarenessSystem.new()
	assert_equal(awareness.collect_commands(world, 1).size(), 0, "unfinished combat building remains inactive")
	world.set_entity_field(tower, "state", "complete")
	var completed_commands := awareness.collect_commands(world, 5)
	assert_equal(completed_commands.size(), 1, "completed building activates without waiting for a roster refresh")
	if not completed_commands.is_empty():
		assert_equal(int(completed_commands[0].target_entity_id), int(enemy["id"]), "completed building keeps the visible enemy target")


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
