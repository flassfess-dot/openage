extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_egyptian_chariot_archer_and_camel(catalog)
	verify_hittite_upgrade_variants(catalog)
	verify_assyrian_cataphract_variant(catalog)
	if failures.is_empty():
		print("E4-002 common roster extension tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_egyptian_chariot_archer_and_camel(catalog) -> void:
	var world = prepared_world(catalog, 1)
	var range: Dictionary = world.add_building(1001, "archery_range", Vector2(8.0, 8.0), 1)
	var stable: Dictionary = world.add_building(1002, "stable", Vector2(13.0, 8.0), 1)
	assert_true(world.is_object_available(1, 41), "Egyptian tech tree enables Chariot Archer")
	assert_true(world.is_object_available(1, 338), "Egyptian tech tree enables Camel Rider")
	var chariot_archer := produce(world, range, "chariot_archer", 41)
	var camel := produce(world, stable, "camel_rider", 338)
	assert_presentation(catalog, chariot_archer, "chariot_archer")
	assert_presentation(catalog, camel, "camel_rider")
	var enemy_chariot := chariot_archer.duplicate(true)
	enemy_chariot["team"] = 2
	assert_equal(catalog.unit_frame_info(enemy_chariot, "attack").get("asset_name"), "enemy_chariot_archer_attack", "enemy Chariot Archer uses player-two palette")
	var enemy_camel := camel.duplicate(true)
	enemy_camel["team"] = 2
	assert_equal(catalog.unit_frame_info(enemy_camel, "move").get("asset_name"), "enemy_camel_rider_move", "enemy Camel Rider uses player-two palette")


func verify_hittite_upgrade_variants(catalog) -> void:
	var world = prepared_world(catalog, 6)
	var range: Dictionary = world.add_building(1101, "archery_range", Vector2(8.0, 8.0), 1)
	var stable: Dictionary = world.add_building(1102, "stable", Vector2(13.0, 8.0), 1)
	assert_equal(world.technology_system.resolved_unit_id(1, 39), 281, "Hittite Heavy Horse Archer upgrade is active")
	assert_equal(world.technology_system.resolved_unit_id(1, 46), 345, "Hittite Armored Elephant upgrade is active")
	var horse_archer := produce(world, range, "horse_archer", 281)
	var elephant := produce(world, stable, "war_elephant", 345)
	assert_presentation(catalog, horse_archer, "horse_archer")
	assert_presentation(catalog, elephant, "armored_elephant")


func verify_assyrian_cataphract_variant(catalog) -> void:
	var world = prepared_world(catalog, 4)
	var stable: Dictionary = world.add_building(1201, "stable", Vector2(10.0, 10.0), 1)
	assert_equal(world.technology_system.resolved_unit_id(1, 37), 283, "Assyrian Cataphract upgrade is active")
	var cataphract := produce(world, stable, "cavalry", 283)
	assert_presentation(catalog, cataphract, "cataphract")


func prepared_world(catalog, civilization_id: int):
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, civilization_id)
	world.set_population_cap(1, 100)
	world.set_population_housing(1, 100)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 100000)
	world.set_starting_age(1, 103, true)
	return world


func produce(world, building: Dictionary, kind: String, expected_source_id: int) -> Dictionary:
	var order: Variant = world.enqueue_unit_production(int(building["id"]), 1, kind)
	assert_true(order != null, "%s enters its source production building" % kind)
	if order == null:
		return {}
	world.update_production(200.0)
	var produced: Array = world.get_units().filter(func(unit): return int(unit.get("production_order_id", -1)) == int(order.get("id", -2)))
	assert_equal(produced.size(), 1, "%s completes production" % kind)
	var unit: Dictionary = produced[0] if not produced.is_empty() else {}
	assert_equal(int(unit.get("source_unit_id", -1)), expected_source_id, "%s resolves its civilization technology lineage" % kind)
	return unit


func assert_presentation(catalog, unit: Dictionary, asset_prefix: String) -> void:
	if unit.is_empty():
		return
	for state in ["idle", "move", "attack", "death", "corpse"]:
		var frame: Dictionary = catalog.unit_frame_info(unit, state)
		assert_equal(String(frame.get("asset_name", "")), "%s_%s" % [asset_prefix, state], "%s %s source asset" % [asset_prefix, state])
		assert_true(frame.get("texture") != null, "%s %s texture is loadable" % [asset_prefix, state])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
