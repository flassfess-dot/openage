extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var roman = configured_world(catalog, 13)
	var carthaginian = configured_world(catalog, 14)
	var palmyran = configured_world(catalog, 15)
	var macedonian = configured_world(catalog, 16)
	var ordinary_sword: Dictionary = carthaginian.add_unit(1, "swordsman", Vector2(5, 5), false)
	var roman_sword: Dictionary = roman.add_unit(1, "swordsman", Vector2(5, 5), false)
	assert_near(float(roman_sword.get("attack_period", 0.0)), 1.0, "Roman sword infantry receives source attack cadence")
	assert_true(float(roman_sword.get("attack_period", 0.0)) <= float(ordinary_sword.get("attack_period", 0.0)), "Roman sword cadence is not slower")
	var carthaginian_elephant: Dictionary = carthaginian.add_unit(1, "war_elephant", Vector2(8, 5), false)
	var ordinary_elephant: Dictionary = roman.add_unit(1, "war_elephant", Vector2(8, 5), false)
	assert_true(float(carthaginian_elephant.get("max_hp", 0.0)) > float(ordinary_elephant.get("max_hp", 0.0)), "Carthaginian elephant HP modifier is live")
	var camel: Dictionary = palmyran.add_unit(1, "camel_rider", Vector2(10, 5), false)
	var ordinary_camel: Dictionary = roman.add_unit(1, "camel_rider", Vector2(10, 5), false)
	assert_true(float(camel.get("speed", 0.0)) > float(ordinary_camel.get("speed", 0.0)), "Palmyran Camel Rider movement bonus is live")
	assert_equal(int(palmyran.unit_resource_cost("villager", 1).get(0, -1)), 75, "Palmyran villager cost modifier is live")
	assert_near(palmyran.technology_system.tribute_tax(1), 0.0, "Palmyran tribute rule is live")
	assert_near(palmyran.technology_system.trade_profit_multiplier(1), 2.0, "Palmyran trade rule is live")
	var ordinary_siege: Dictionary = roman.unit_resource_cost("stone_thrower", 1)
	var macedonian_siege: Dictionary = macedonian.unit_resource_cost("stone_thrower", 1)
	assert_true(int(macedonian_siege.get(1, 0)) < int(ordinary_siege.get(1, 0)), "Macedonian siege wood discount is live")
	for world in [roman, carthaginian, palmyran, macedonian]:
		assert_true(not world.technology_system.persistent_entity_effects(1).is_empty(), "RoR civilization source bundle supplies runtime effects")
	finish()


func configured_world(catalog, civilization_id: int):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization_id)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, context: String) -> void:
	if absf(actual - expected) > 0.0001:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P05 RoR civilization runtime matrix passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
