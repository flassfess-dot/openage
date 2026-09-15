extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_stable_cavalry_line(catalog)
	if failures.is_empty():
		print("I12-010 Stable cavalry vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_stable_cavalry_line(catalog) -> void:
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)

	assert_true(not world.is_object_available(1, 101), "Stable starts behind the original Tool Age and Barracks connector")
	world.add_building(950, "barracks", Vector2(7.0, 7.0), 1)
	assert_true(world.get_researched_technologies(1).has(62), "completed Barracks applies its original completion technology")
	world.grant_technology(1, 101)
	assert_true(world.get_researched_technologies(1).has(97), "Tool Age and Barracks automatically resolve Stable connector 97")
	assert_true(world.is_object_available(1, 101), "Stable becomes available through its source object-enable effect")

	var stable: Dictionary = world.add_building(951, "stable", Vector2(16.0, 16.0), 1)
	assert_equal(stable.get("source_unit_id"), 101, "Tool Age Stable keeps source identity")
	assert_equal(stable.get("max_hp"), 350.0, "Stable uses original health")
	assert_equal(catalog.building_frame_info(stable).get("graphic_id"), 514, "Tool Age Stable resolves original graphic")
	assert_true(catalog.building_frame_info(stable).get("texture") != null, "Tool Age Stable graphic is loadable")
	assert_true(world.get_researched_technologies(1).has(67), "completed Stable applies original Scout unlock technology")
	assert_true(world.is_object_available(1, 299), "Scout becomes available after Stable completion")

	var scout: Dictionary = produce(world, stable, "scout", 30.0, {0: 100}, "Scout")
	assert_unit_variant(catalog, scout, 299, "scout", 60.0, 3.0, "Scout")
	assert_equal(float(scout.get("speed", 0.0)), 2.0, "Scout uses original movement speed")
	assert_equal(float(world.object_record_by_id(299, 1).get("line_of_sight", 0.0)), 8.0, "Scout source record keeps original base line of sight")
	assert_equal(float(scout.get("components", {}).get("vision", {}).get("range", 0.0)), 10.0, "Tool Age source effect improves Scout vision by two")

	world.grant_technology(1, 102)
	assert_equal(stable.get("source_unit_id"), 86, "Bronze Age upgrades existing Stable to source 86")
	assert_equal(catalog.building_frame_info(stable).get("graphic_id"), 877, "Bronze Age Stable resolves Roman expansion graphic")
	assert_true(catalog.building_frame_info(stable).get("texture") != null, "Bronze Age Stable graphic is loadable")
	assert_true(world.get_researched_technologies(1).has(69), "Cavalry zero-time availability connector resolves automatically")
	assert_true(world.is_object_available(1, 37), "Cavalry is available in Bronze Age")
	assert_equal(float(scout.get("components", {}).get("vision", {}).get("range", 0.0)), 12.0, "Bronze Age source effect improves existing Scout vision again")
	var cavalry: Dictionary = produce(world, stable, "cavalry", 40.0, {0: 70, 3: 80}, "Cavalry")
	assert_unit_variant(catalog, cavalry, 37, "cavalry", 150.0, 8.0, "Cavalry")

	assert_true(not world.is_object_available(1, 40), "Chariot remains unavailable without Wheel")
	world.grant_technology(1, 28)
	assert_true(world.get_researched_technologies(1).has(68), "Wheel resolves the Chariot zero-time availability connector")
	assert_true(world.is_object_available(1, 40), "Chariot becomes available through technology 68")
	var option_kinds: Array = world.get_unit_production_options(int(stable["id"]), 1).map(func(option): return String(option.get("kind", "")))
	for kind in ["scout", "cavalry", "chariot"]:
		assert_true(option_kinds.has(kind), "Stable production palette exposes %s" % kind)
	var chariot: Dictionary = produce(world, stable, "chariot", 40.0, {0: 40, 1: 60}, "Chariot")
	assert_unit_variant(catalog, chariot, 40, "chariot", 100.0, 7.0, "Chariot")

	world.grant_technology(1, 103)
	world.grant_technology(1, 34)
	var wood_before := world.get_resource_amount(1, 1)
	var gold_before := world.get_resource_amount(1, 3)
	var research: Variant = world.enqueue_research(int(stable["id"]), 1, 126)
	assert_true(research != null, "Scythe Chariot enters the normal Stable research queue")
	if research != null:
		assert_equal(world.get_resource_amount(1, 1), wood_before - 1200, "Scythe Chariot reserves original wood cost")
		assert_equal(world.get_resource_amount(1, 3), gold_before - 800, "Scythe Chariot reserves original gold cost")
		world.update_production(150.0)
	assert_unit_variant(catalog, chariot, 339, "scythe_chariot", 138.0, 9.0, "Scythe Chariot")
	var future: Dictionary = world.add_unit(1, "chariot", Vector2(10.0, 10.0), false)
	assert_equal(future.get("source_unit_id"), 339, "future Chariots inherit Scythe Chariot upgrade")
	assert_near(float(future.get("max_hp", 0.0)), float(chariot.get("max_hp", 0.0)), 0.001, "existing and future Scythe Chariots keep the same Nobility health bonus")
	var enemy := {"kind": "chariot", "source_unit_id": 339, "team": 2, "facing": 0, "anim": 0.0}
	assert_equal(catalog.unit_frame_info(enemy, "attack").get("asset_name"), "enemy_scythe_chariot_attack", "enemy Scythe Chariot uses recolored source attack")


func produce(world, stable: Dictionary, kind: String, elapsed: float, expected_cost: Dictionary, context: String) -> Dictionary:
	var before: Dictionary = {}
	for resource_type in expected_cost:
		before[resource_type] = world.get_resource_amount(1, int(resource_type))
	var order: Variant = world.enqueue_unit_production(int(stable["id"]), 1, kind)
	assert_true(order != null, "%s enters the normal Stable production queue" % context)
	if order == null:
		return {}
	for resource_type in expected_cost:
		assert_equal(world.get_resource_amount(1, int(resource_type)), int(before[resource_type]) - int(expected_cost[resource_type]), "%s reserves original resource %s cost" % [context, resource_type])
	world.update_production(elapsed)
	var produced: Array = world.get_units().filter(func(unit): return int(unit.get("production_order_id", -1)) == int(order.get("id", -2)))
	assert_equal(produced.size(), 1, "%s completes after original creation time" % context)
	return produced[0] if not produced.is_empty() else {}


func assert_unit_variant(catalog, unit: Dictionary, source_id: int, asset_prefix: String, hp: float, damage: float, context: String) -> void:
	if unit.is_empty():
		return
	assert_equal(unit.get("source_unit_id"), source_id, "%s source identity" % context)
	assert_near(float(unit.get("max_hp", 0.0)), hp, 0.001, "%s effective health" % context)
	assert_equal(unit.get("attack_damage"), damage, "%s primary source attack" % context)
	for state in ["idle", "move", "attack", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(unit, state).get("asset_name"), "%s_%s" % [asset_prefix, state], "%s %s presentation" % [context, state])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, context: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [context, expected, tolerance, actual])
