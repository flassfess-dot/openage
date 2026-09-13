extends SceneTree

const CombatRules := preload("res://scripts/combat_rules.gd")
const FormationCombat := preload("res://scripts/formation_combat.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_attack_classes_and_minimum_damage()
	test_size_aware_contact_range()
	test_original_one_on_one_and_reload()
	test_multiple_attackers_have_contacts()
	test_death_occurs_on_damage_frame()

	if failures.is_empty():
		print("S-003 melee combat tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_attack_classes_and_minimum_damage() -> void:
	var attacks := [{"type_id": 4, "amount": 3}, {"type_id": 9, "amount": 8}]
	var armors := [{"type_id": 4, "amount": 7}, {"type_id": 9, "amount": 3}]
	assert_float(CombatRules.total_damage(attacks, armors), 5.0, "class contributions are summed before the one-point minimum")
	assert_float(CombatRules.primary_attack_damage([{"type_id": 9, "amount": 0}, {"type_id": 4, "amount": 8}]), 8.0, "compatibility damage selects base melee class after bonus classes")
	assert_float(CombatRules.primary_attack_damage([{"type_id": 12, "amount": 2}], 3.0), 2.0, "source attack classes are not raised to a compatibility fallback")
	assert_float(CombatRules.primary_attack_damage([], 3.0), 3.0, "compatibility fallback is used only when source attacks are absent")
	assert_float(CombatRules.damage_for_attack({"type_id": 4, "amount": 3}, [{"type_id": 4, "amount": -2}]), 5.0, "negative original armor increases damage")
	assert_float(CombatRules.damage_for_attack({"type_id": 11, "amount": 20}, []), 20.0, "an undefined armor class has the original zero armor value")
	assert_float(CombatRules.total_damage([{"type_id": 4, "amount": 0}], []), 1.0, "minimum unit damage is applied once after all classes")
	var town_center := building_target([{"type_id": 6, "amount": -140}])
	assert_float(CombatRules.damage_from_attacks([{"type_id": 6, "amount": 35}, {"type_id": 4, "amount": 0}], town_center), 35.0, "Catapult Trireme siege class and negative building armor use the RoR one-fifth rule")
	assert_float(CombatRules.damage_from_attacks([{"type_id": 3, "amount": 5}], building_target([])), 1.0, "ordinary ship damage against an unarmored building is divided by five")
	assert_float(CombatRules.damage_from_attacks([{"type_id": 4, "amount": 0}], building_target([])), 0.1, "buildings use the original one-tenth minimum damage")


func test_size_aware_contact_range() -> void:
	var attacker := {"pos": Vector2.ZERO, "footprint_radius": 0.3, "attack_range": 0.0}
	var large_target := {"pos": Vector2(1.88, 0.0), "footprint_radius": 1.5}
	assert_true(CombatRules.is_in_range(attacker, large_target), "touching large footprint is in melee range")
	large_target["pos"] = Vector2(1.9, 0.0)
	assert_true(not CombatRules.is_in_range(attacker, large_target), "gap beyond contact margin is out of melee range")


func building_target(armors: Array) -> Dictionary:
	return {
		"movement_domain": "static",
		"occupied_cells": [Vector2i.ZERO],
		"components": {"combat": {"armors": armors}},
	}


func test_original_one_on_one_and_reload() -> void:
	var setup := original_world()
	var world = setup["world"]
	var attacker: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 5.0), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(5.65, 5.0), false)
	world.assign_command_attack([attacker], int(target["id"]))
	var initial_health := float(target["hp"])
	world.advance(0.05, 1, 2)
	assert_float(initial_health - float(target["hp"]), 3.0, "original clubman melee class deals three through zero armor")
	var distress: Array = world.get_attack_distress_signals(2)
	assert_equal(distress.size(), 1, "melee damage records one bounded distress signal for the victim team")
	assert_equal(int(distress[0].get("attacker_id", -1)), int(attacker["id"]), "melee distress identifies the authoritative attacker")
	var after_hit := float(target["hp"])
	for unused in range(10):
		world.advance(0.05, 1, 2)
	assert_float(float(target["hp"]), after_hit, "attack period prevents early repeated hit")


func test_multiple_attackers_have_contacts() -> void:
	var setup := original_world()
	var world = setup["world"]
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 5.0), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(5.0, 5.6), false)
	var target: Dictionary = world.add_unit(2, "clubman", Vector2(5.6, 5.3), false)
	world.assign_command_attack([first, second], int(target["id"]))
	assert_true(first["combat_destination"] != second["combat_destination"], "multiple attackers reserve different contact slots")
	world.advance(0.05, 1, 2)
	assert_float(float(target["max_hp"]) - float(target["hp"]), 6.0, "two attackers apply independent class damage")


func test_death_occurs_on_damage_frame() -> void:
	var world = SimulationWorld.new(Vector2i(12, 12))
	world.set_gamespec({"units": {"test_melee": {
		"hit_points": 3.0,
		"speed": 1.0,
		"attack_period": 1.0,
		"range": 0.0,
		"projectile_id": -1,
		"attacks": [{"amount": 4.0}],
		"animations": {"attack": {"frame_rate": 0.1, "damage_frame": 2}},
	}}})
	var attacker: Dictionary = world.add_unit(1, "test_melee", Vector2(6.0, 6.0), false)
	var target: Dictionary = world.add_unit(2, "test_melee", Vector2(6.6, 6.0), false)
	world.assign_command_attack([attacker], int(target["id"]))
	for unused in range(4):
		world.advance(0.05, 1, 2)
	assert_true(float(target["hp"]) > 0.0, "target lives before damage frame")
	world.advance(0.05, 1, 2)
	assert_true(float(target["hp"]) <= 0.0, "target dies exactly on damage frame")
	assert_true(not bool(target["components"]["health"]["alive"]), "Health component records death immediately")
	assert_true(String(target["death_phase"]) == "dying", "death lifecycle starts on the damage frame")


func original_world() -> Dictionary:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	return {"world": world}


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
