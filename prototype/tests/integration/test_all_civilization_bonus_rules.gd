extends SceneTree

const CombatRules := preload("res://scripts/combat_rules.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	verify_every_attribute_command(catalog)
	verify_rule_resource_precision(catalog)
	verify_palmyran_runtime_bonus(catalog)
	verify_babylonian_faith_bonus(catalog)
	if failures.is_empty():
		print("E4-003 all-civilization bonus rule tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_every_attribute_command(catalog) -> void:
	for civilization_id in range(1, 17):
		var world = configured_world(catalog, civilization_id)
		var civilization: Dictionary = civilization_record(catalog.object_catalog_data, civilization_id)
		var bundle: Dictionary = effect_bundle(catalog.object_catalog_data, int(civilization.get("tech_tree_id", -1)))
		for command_value in bundle.get("commands", []):
			var command: Dictionary = command_value
			if int(command.get("type_id", -1)) not in [0, 4, 5]:
				continue
			var source := target_source(catalog.object_catalog_data, civilization_id, command)
			assert_true(not source.is_empty(), "civilization %d effect has a concrete source target: %s" % [civilization_id, command])
			if source.is_empty():
				continue
			var attribute_id := int(command.get("attr_c", -1))
			if attribute_id == 100:
				verify_cost_effect(world, source, command, civilization_id)
				continue
			var entity := synthetic_entity(source)
			var before := attribute_value(entity, attribute_id, command)
			world.apply_attribute_effect(entity, command)
			var actual := attribute_value(entity, attribute_id, command)
			var expected := expected_attribute_value(before, command, source, attribute_id)
			assert_near(actual, expected, 0.0001, "civilization %d attribute %d applies DAT operator to source %d" % [civilization_id, attribute_id, int(source.get("unit_id", -1))])


func verify_cost_effect(world, source: Dictionary, command: Dictionary, civilization_id: int) -> void:
	var base_cost := {0: 100}
	var result: Dictionary = world.apply_object_cost_modifiers(base_cost, int(source.get("unit_id", -1)), 1)
	var expected := 100.0
	for candidate_value in world.technology_system.persistent_entity_effects(1):
		var candidate: Dictionary = candidate_value
		if int(candidate.get("attr_c", -1)) != 100 or not command_matches_source(candidate, source):
			continue
		expected = apply_operator(expected, int(candidate.get("type_id", -1)), float(candidate.get("attr_d", 0.0)))
	assert_equal(int(result.get(0, -1)), maxi(0, roundi(expected)), "civilization %d source %d production cost uses every matching DAT modifier" % [civilization_id, int(source.get("unit_id", -1))])
	assert_true(command_matches_source(command, source), "cost probe targets the command source")


func verify_rule_resource_precision(catalog) -> void:
	var babylonian = configured_world(catalog, 3)
	assert_near(babylonian.technology_system.rule_resource_value(1, 35), 2.75, 0.0001, "Babylonian faith regeneration keeps fractional DAT precision")
	var minoan = configured_world(catalog, 5)
	assert_near(minoan.technology_system.rule_resource_value(1, 36), 310.0, 0.0001, "Minoan farm capacity adds sixty to the source baseline")
	var minoan_farm: Dictionary = minoan.add_building(501, "farm", Vector2(8.0, 8.0), 1)
	assert_equal(int(minoan_farm.get("max_amount", -1)), 310, "Minoan Farm consumes the precise rule resource")
	var sumerian = configured_world(catalog, 8)
	assert_near(sumerian.technology_system.rule_resource_value(1, 36), 500.0, 0.0001, "Sumerian farm capacity doubles the source baseline")
	var sumerian_farm: Dictionary = sumerian.add_building(801, "farm", Vector2(8.0, 8.0), 1)
	assert_equal(int(sumerian_farm.get("max_amount", -1)), 500, "Sumerian Farm consumes the source civilization bonus")
	var palmyran = configured_world(catalog, 15)
	assert_near(palmyran.technology_system.rule_resource_value(1, 46), 0.0, 0.0001, "Palmyran tribute inefficiency is the source zero value")
	var roman = configured_world(catalog, 13)
	assert_near(roman.technology_system.rule_resource_value(1, 46), 0.25, 0.0001, "ordinary tribute inefficiency keeps the source baseline")


func verify_palmyran_runtime_bonus(catalog) -> void:
	var world = configured_world(catalog, 15)
	assert_near(world.technology_system.tribute_tax(1), 0.0, 0.0001, "Palmyran tribute transaction reads zero source tax")
	assert_near(world.technology_system.trade_profit_multiplier(1), 2.0, 0.0001, "Palmyran trade policy supplies double profit")
	var villager: Dictionary = world.add_unit(1, "villager", Vector2(6.0, 6.0), false)
	assert_near(float(villager.get("components", {}).get("combat", {}).get("base_armor", 0.0)), 1.0, 0.0001, "Palmyran villagers receive one base armor")
	var incoming := [{"type_id": 4, "amount": 3}]
	assert_near(CombatRules.damage_from_attacks(incoming, villager), 2.0, 0.0001, "base armor protects against an attack class absent from explicit armor entries")
	assert_equal(int(world.unit_resource_cost("villager", 1).get(0, -1)), 75, "Palmyran villagers use their source 75-food cost")
	var camel: Dictionary = world.add_unit(1, "camel_rider", Vector2(9.0, 6.0), false)
	var camel_source: Dictionary = world.object_record_by_id(338, 1)
	assert_near(float(camel.get("speed", 0.0)), float(camel_source.get("speed", 0.0)) * 1.25, 0.0001, "Palmyran Camel Rider receives its source speed multiplier")


func verify_babylonian_faith_bonus(catalog) -> void:
	var world = configured_world(catalog, 3)
	var priest: Dictionary = world.add_unit(1, "priest", Vector2(6.0, 6.0), false)
	assert_near(world.conversion_system.recharge_rate_for(priest), 2.75, 0.0001, "Babylonian Priest uses the civilization faith regeneration resource")
	priest["components"]["conversion"]["faith"] = 0.0
	world.conversion_system.advance_faith(priest, 4.0)
	assert_near(float(priest["components"]["conversion"]["faith"]), 11.0, 0.0001, "Babylonian faith regeneration changes runtime recovery")


func configured_world(catalog, civilization_id: int):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization_id)
	return world


func civilization_record(catalog: Dictionary, civilization_id: int) -> Dictionary:
	for value in catalog.get("civilizations", []):
		var civilization: Dictionary = value
		if int(civilization.get("civilization_id", -1)) == civilization_id:
			return civilization
	return {}


func effect_bundle(catalog: Dictionary, bundle_id: int) -> Dictionary:
	return catalog.get("effect_bundles", {}).get(String.num_int64(bundle_id), {})


func target_source(catalog: Dictionary, civilization_id: int, command: Dictionary) -> Dictionary:
	var target_id := int(command.get("attr_a", -1))
	if target_id >= 0:
		return catalog.get("objects", {}).get("%d:%d" % [civilization_id, target_id], {})
	var target_class := int(command.get("attr_b", -1))
	var candidates: Array[Dictionary] = []
	for source_value in catalog.get("objects", {}).values():
		var source: Dictionary = source_value
		if int(source.get("civilization_id", -1)) == civilization_id and int(source.get("unit_class", -2)) == target_class:
			candidates.append(source)
	candidates.sort_custom(func(left, right): return int(left.get("unit_id", -1)) < int(right.get("unit_id", -1)))
	return candidates[0] if not candidates.is_empty() else {}


func synthetic_entity(source: Dictionary) -> Dictionary:
	var combat: Dictionary = source.get("combat", {})
	var resources: Dictionary = source.get("resources", {})
	return {
		"team": 1,
		"source_unit_id": int(source.get("unit_id", -1)),
		"unit_lineage": [int(source.get("unit_id", -1))],
		"technology_locked": false,
		"max_hp": float(source.get("health", 0.0)),
		"hp": float(source.get("health", 0.0)),
		"speed": float(source.get("speed", 0.0)),
		"attack_period": float(combat.get("attack_period", 0.0)),
		"attack_range": float(combat.get("range_max", 0.0)),
		"attack_damage": CombatRules.primary_attack_damage(combat.get("attacks", [])),
		"carry_capacity": float(resources.get("capacity", 0.0)),
		"population_cost": 0,
		"components": {
			"health": {"current": float(source.get("health", 0.0)), "maximum": float(source.get("health", 0.0))},
			"vision": {"range": float(source.get("line_of_sight", 0.0))},
			"movement": {"speed": float(source.get("speed", 0.0))},
			"combat": {
				"attacks": combat.get("attacks", []).duplicate(true),
				"armors": combat.get("armors", []).duplicate(true),
				"base_armor": float(combat.get("base_armor", 0.0)),
				"attack_period": float(combat.get("attack_period", 0.0)),
				"range_max": float(combat.get("range_max", 0.0)),
				"accuracy": int(combat.get("accuracy", 0)),
			},
			"worker": {"work_rate": float(source.get("work_rate", 0.0))},
			"conversion": {"enabled": false},
			"healing": {"enabled": false},
			"resource_carrier": {"capacity": float(resources.get("capacity", 0.0))},
			"production": {},
			"technology": {},
		},
	}


func attribute_value(entity: Dictionary, attribute_id: int, command: Dictionary) -> float:
	var components: Dictionary = entity.get("components", {})
	match attribute_id:
		0: return float(entity.get("max_hp", 0.0))
		1: return float(components.get("vision", {}).get("range", 0.0))
		5: return float(entity.get("speed", 0.0))
		8: return class_amount(components.get("combat", {}).get("armors", []), packed_class_id(command))
		9: return class_amount(components.get("combat", {}).get("attacks", []), packed_class_id(command))
		10: return float(entity.get("attack_period", 0.0))
		11: return float(components.get("combat", {}).get("accuracy", 0.0))
		12: return float(entity.get("attack_range", 0.0))
		13: return float(components.get("worker", {}).get("work_rate", 0.0))
		14: return float(entity.get("carry_capacity", 0.0))
		15: return float(components.get("combat", {}).get("base_armor", 0.0))
		16: return float(entity.get("projectile_id", -1))
		17: return float(entity.get("graphic_angle_count", 0))
	return NAN


func expected_attribute_value(before: float, command: Dictionary, source: Dictionary, attribute_id: int) -> float:
	if attribute_id in [8, 9]:
		var entries: Array = source.get("combat", {}).get("armors" if attribute_id == 8 else "attacks", [])
		var class_id := packed_class_id(command)
		var has_class := entries.any(func(entry): return int(entry.get("type_id", -1)) == class_id)
		if not has_class:
			return packed_amount(command)
	return apply_operator(before, int(command.get("type_id", -1)), float(command.get("attr_d", 0.0)) if attribute_id not in [8, 9] else packed_amount(command))


func command_matches_source(command: Dictionary, source: Dictionary) -> bool:
	var target_id := int(command.get("attr_a", -1))
	if target_id >= 0:
		return target_id == int(source.get("unit_id", -1))
	return int(command.get("attr_b", -1)) == int(source.get("unit_class", -2))


func apply_operator(current: float, effect_type: int, value: float) -> float:
	match effect_type:
		0: return value
		4: return current + value
		5: return current * value
	return current


func packed_class_id(command: Dictionary) -> int:
	return (roundi(float(command.get("attr_d", 0.0))) >> 8) & 0xff


func packed_amount(command: Dictionary) -> float:
	var amount := roundi(float(command.get("attr_d", 0.0))) & 0xff
	return float(amount - 256 if amount >= 128 else amount)


func class_amount(entries: Array, class_id: int) -> float:
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if int(entry.get("type_id", -1)) == class_id:
			return float(entry.get("amount", 0.0))
	return 0.0


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, context: String) -> void:
	if not is_equal_approx(actual, expected) and absf(actual - expected) > tolerance:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
