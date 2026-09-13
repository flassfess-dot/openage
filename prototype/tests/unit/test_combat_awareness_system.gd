extends SceneTree

const CombatAwarenessSystem := preload("res://scripts/combat_awareness_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_stance_rules()
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


func open_world():
	var world = SimulationWorld.new(Vector2i(20, 20))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	return world


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
