extends SceneTree

const CombatRules := preload("res://scripts/combat_rules.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var camel: Dictionary = world.add_unit(1, "camel_rider", Vector2(4, 4), false)
	var slinger: Dictionary = world.add_unit(1, "slinger", Vector2(4, 6), false)
	var scythe: Dictionary = world.add_unit(1, "chariot", Vector2(4, 8), false)
	world.apply_unit_upgrade_to_entity(scythe, 339, false)
	var fire_galley: Dictionary = world.add_unit(1, "fire_galley", Vector2(4, 10), false)
	var scout_ship: Dictionary = world.add_unit(1, "scout_ship", Vector2(4, 12), false)
	var cavalry: Dictionary = world.add_unit(2, "cavalry", Vector2(8, 4), false)
	var clubman: Dictionary = world.add_unit(2, "clubman", Vector2(8, 6), false)
	var archer: Dictionary = world.add_unit(2, "archer", Vector2(8, 8), false)
	var priest: Dictionary = world.add_unit(2, "priest", Vector2(8, 10), false)
	var war_galley: Dictionary = world.add_unit(2, "scout_ship", Vector2(8, 12), false)
	world.apply_unit_upgrade_to_entity(war_galley, 20, false)
	assert_true(int(war_galley.get("source_unit_id", -1)) == 20, "War Galley damage fixture uses the upgraded source unit")
	assert_true(CombatRules.entity_damage(camel, cavalry) > CombatRules.entity_damage(camel, clubman), "Camel Rider class damage is stronger against cavalry")
	assert_true(CombatRules.entity_damage(slinger, archer) > CombatRules.entity_damage(slinger, clubman), "Slinger class damage is stronger against archers")
	assert_true(CombatRules.entity_damage(scythe, priest) > CombatRules.entity_damage(scythe, clubman), "Scythe Chariot class damage reaches the priest weakness")
	assert_true(CombatRules.entity_damage(fire_galley, war_galley) > CombatRules.entity_damage(scout_ship, war_galley), "Fire Galley source attack has greater runtime damage than a Scout Ship")
	if failures.is_empty():
		print("P03 RoR special damage matrix tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
