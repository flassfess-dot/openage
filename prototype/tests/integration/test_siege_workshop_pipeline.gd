extends SceneTree

const CombatRules := preload("res://scripts/combat_rules.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_workshop_and_upgrade_lines(catalog)
	verify_projectile_and_blast_contract(catalog)
	if failures.is_empty():
		print("I12-012 Siege Workshop vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_workshop_and_upgrade_lines(catalog) -> void:
	var world = configured_world(catalog)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 20000)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)

	assert_true(not world.is_object_available(1, 49), "Siege Workshop starts behind its Bronze Age and Archery Range connector")
	world.grant_technology(1, 55)
	world.grant_technology(1, 102)
	assert_true(world.get_researched_technologies(1).has(96), "Bronze Age and Archery Range completion resolve Workshop connector 96")
	assert_true(world.is_object_available(1, 49), "Siege Workshop becomes available through the source object-enable effect")

	var workshop: Dictionary = world.add_building(980, "siege_workshop", Vector2(16.0, 16.0), 1)
	assert_equal(workshop.get("source_unit_id"), 49, "Workshop keeps source identity")
	assert_equal(workshop.get("max_hp"), 350.0, "Workshop uses original health")
	assert_equal(catalog.building_frame_info(workshop).get("graphic_id"), 875, "Workshop resolves original Roman expansion graphic")
	assert_true(catalog.building_frame_info(workshop).get("texture") != null, "Workshop base graphic is loadable")
	assert_true(world.get_researched_technologies(1).has(53), "completed Workshop applies Stone Thrower unlock technology 53")
	assert_true(world.is_object_available(1, 35), "Stone Thrower becomes available after Workshop completion")

	var stone_thrower: Dictionary = produce(world, workshop, "stone_thrower", 60.0, {1: 180, 3: 80}, "Stone Thrower")
	assert_siege_variant(catalog, stone_thrower, 35, "stone_thrower", 75.0, 50.0, 2.0, 10.0, 0.5, 34, "Stone Thrower")
	assert_true(not world.is_object_available(1, 11), "Ballista remains unavailable before Iron Age")

	world.grant_technology(1, 103)
	assert_true(world.get_researched_technologies(1).has(58), "Iron Age resolves zero-time Ballista availability technology 58")
	assert_true(world.is_object_available(1, 11), "Ballista becomes available through technology 58")
	complete_research(world, workshop, 54, 100.0, {0: 300, 1: 250}, "Catapult")
	assert_siege_variant(catalog, stone_thrower, 36, "catapult", 75.0, 60.0, 2.0, 12.0, 1.5, 34, "Catapult")

	world.grant_technology(1, 111)
	complete_research(world, workshop, 36, 150.0, {0: 1800, 1: 900}, "Heavy Catapult")
	assert_siege_variant(catalog, stone_thrower, 280, "catapult", 150.0, 60.0, 2.0, 13.0, 1.5, 34, "Heavy Catapult")
	var future_stone: Dictionary = world.add_unit(1, "stone_thrower", Vector2(10.0, 10.0), false)
	assert_equal(future_stone.get("source_unit_id"), 280, "future Stone Throwers inherit Heavy Catapult upgrade")

	var ballista: Dictionary = produce(world, workshop, "ballista", 50.0, {1: 100, 3: 80}, "Ballista")
	assert_siege_variant(catalog, ballista, 11, "ballista", 55.0, 40.0, 3.0, 9.0, 0.0, 204, "Ballista")
	world.grant_technology(1, 110)
	complete_research(world, workshop, 27, 150.0, {0: 1500, 1: 1000}, "Helepolis")
	assert_siege_variant(catalog, ballista, 279, "ballista", 55.0, 40.0, 3.0, 10.0, 0.0, 204, "Helepolis")
	assert_float(float(ballista.get("attack_period", 0.0)), 1.5, "Helepolis uses original reload period")
	var future_ballista: Dictionary = world.add_unit(1, "ballista", Vector2(11.0, 10.0), false)
	assert_equal(future_ballista.get("source_unit_id"), 279, "future Ballistas inherit Helepolis upgrade")


func verify_projectile_and_blast_contract(catalog) -> void:
	var objects: Dictionary = catalog.object_catalog_data.get("objects", {})
	assert_float(float(objects["13:34"]["speed"]), 2.700000047683716, "siege rock uses original speed")
	assert_float(float(objects["13:34"]["projectile"]["arc"]), 0.5, "siege rock uses original high arc")
	assert_float(float(objects["13:204"]["speed"]), 4.5, "ballista bolt uses original speed")
	assert_float(float(objects["13:204"]["projectile"]["arc"]), 0.10000000149011612, "ballista bolt uses original low arc")
	assert_equal(catalog.projectile_frame_info(projectile_stub(34)).get("asset_name"), "siege_rock", "stone projectile resolves through source-aware registry")
	assert_equal(catalog.projectile_frame_info(projectile_stub(204)).get("asset_name"), "ballista_bolt", "bolt projectile resolves through source-aware registry")

	var world = configured_world(catalog)
	var launcher: Dictionary = world.add_unit(1, "stone_thrower", Vector2(5.0, 6.0), false)
	var target: Dictionary = world.add_unit(2, "hoplite", Vector2(10.0, 6.0), false)
	var nearby_enemy: Dictionary = world.add_unit(2, "hoplite", Vector2(10.0, 6.6), false)
	var nearby_friend: Dictionary = world.add_unit(1, "hoplite", Vector2(10.0, 5.4), false)
	var distant_enemy: Dictionary = world.add_unit(2, "hoplite", Vector2(12.0, 6.0), false)
	var initial := {
		"target": float(target["hp"]),
		"enemy": float(nearby_enemy["hp"]),
		"friend": float(nearby_friend["hp"]),
		"distant": float(distant_enemy["hp"]),
	}
	assert_true(CombatRules.is_too_close(launcher, world.add_unit(2, "hoplite", Vector2(5.8, 6.0), false)), "source minimum range rejects a point-blank siege target")
	assert_true(CombatRules.is_in_range(launcher, target), "target inside source min/max band is attackable")
	var rock: Dictionary = world.spawn_projectile(launcher, target)
	assert_float(float(rock.get("blast_range", 0.0)), 0.5, "projectile snapshots launcher blast radius")
	assert_true(bool(rock.get("friendly_fire", false)), "Stone Thrower carries explicit friendly-fire policy")
	var canonical: Dictionary = SimulationSnapshot.canonical(world, 17)
	assert_float(float(canonical["world"]["projectiles"][0].get("blast_range", 0.0)), 0.5, "canonical state retains blast contract")
	assert_equal(canonical["world"]["projectiles"][0].get("blast_falloff"), "none", "canonical state retains falloff policy")
	resolve_projectile(world, rock)
	assert_true(float(target["hp"]) < float(initial["target"]), "blast damages direct target")
	assert_true(float(nearby_enemy["hp"]) < float(initial["enemy"]), "blast damages nearby enemy")
	assert_true(float(nearby_friend["hp"]) < float(initial["friend"]), "blast applies source-accurate friendly fire")
	assert_float(float(distant_enemy["hp"]), float(initial["distant"]), "blast does not damage entity outside radius")
	assert_equal(rock.get("hit_target_ids", []).size(), 3, "resolved projectile records all three affected entities")

	var bolt_world = configured_world(catalog)
	var ballista: Dictionary = bolt_world.add_unit(1, "ballista", Vector2(5.0, 9.0), false)
	var bolt_target: Dictionary = bolt_world.add_unit(2, "hoplite", Vector2(10.0, 9.0), false)
	var bolt_neighbor: Dictionary = bolt_world.add_unit(2, "hoplite", Vector2(10.0, 9.4), false)
	var bolt_target_hp := float(bolt_target["hp"])
	var bolt_neighbor_hp := float(bolt_neighbor["hp"])
	var bolt: Dictionary = bolt_world.spawn_projectile(ballista, bolt_target)
	resolve_projectile(bolt_world, bolt)
	assert_true(float(bolt_target["hp"]) < bolt_target_hp, "bolt damages direct target")
	assert_float(float(bolt_neighbor["hp"]), bolt_neighbor_hp, "zero-blast bolt does not leak damage to adjacent unit")
	assert_equal(bolt.get("hit_target_ids", []), [int(bolt_target["id"])], "bolt records only direct impact")

	var building_world = configured_world(catalog)
	var building_launcher: Dictionary = building_world.add_unit(1, "stone_thrower", Vector2(5.0, 16.0), false)
	var target_building: Dictionary = building_world.add_building(990, "town_center", Vector2(10.0, 16.0), 2)
	var building_hp := float(target_building["hp"])
	var building_rock: Dictionary = building_world.spawn_projectile(building_launcher, target_building)
	resolve_projectile(building_world, building_rock)
	assert_true(float(target_building["hp"]) < building_hp, "blast damage uses the common combat-entity path for buildings")
	assert_true(building_rock.get("hit_target_ids", []).has(int(target_building["id"])), "building impact is recorded deterministically")

	var release_world = configured_world(catalog)
	var firing_unit: Dictionary = release_world.add_unit(1, "stone_thrower", Vector2(5.0, 12.0), false)
	var firing_target: Dictionary = release_world.add_unit(2, "hoplite", Vector2(10.0, 12.0), false)
	release_world.assign_command_attack([firing_unit], int(firing_target["id"]))
	for unused in range(12):
		release_world.advance(0.05, 1, 2)
		if not release_world.get_projectiles().is_empty():
			break
	assert_equal(release_world.get_projectiles().size(), 1, "one projectile is released on the original animation frame")


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world


func produce(world, workshop: Dictionary, kind: String, elapsed: float, expected_cost: Dictionary, context: String) -> Dictionary:
	var before: Dictionary = {}
	for resource_type in expected_cost:
		before[resource_type] = world.get_resource_amount(1, int(resource_type))
	var order: Variant = world.enqueue_unit_production(int(workshop["id"]), 1, kind)
	assert_true(order != null, "%s enters normal Workshop production queue" % context)
	if order == null:
		return {}
	for resource_type in expected_cost:
		assert_equal(world.get_resource_amount(1, int(resource_type)), int(before[resource_type]) - int(expected_cost[resource_type]), "%s reserves original resource %s cost" % [context, resource_type])
	world.update_production(elapsed)
	var produced: Array = world.get_units().filter(func(unit): return int(unit.get("production_order_id", -1)) == int(order.get("id", -2)))
	assert_equal(produced.size(), 1, "%s completes after original creation time" % context)
	return produced[0] if not produced.is_empty() else {}


func complete_research(world, workshop: Dictionary, technology_id: int, elapsed: float, expected_cost: Dictionary, context: String) -> void:
	var before: Dictionary = {}
	for resource_type in expected_cost:
		before[resource_type] = world.get_resource_amount(1, int(resource_type))
	var order: Variant = world.enqueue_research(int(workshop["id"]), 1, technology_id)
	assert_true(order != null, "%s enters normal Workshop research queue" % context)
	if order == null:
		return
	for resource_type in expected_cost:
		assert_equal(world.get_resource_amount(1, int(resource_type)), int(before[resource_type]) - int(expected_cost[resource_type]), "%s reserves original resource %s cost" % [context, resource_type])
	world.update_production(elapsed)


func assert_siege_variant(catalog, unit: Dictionary, source_id: int, asset_prefix: String, hp: float, damage: float, minimum_range: float, maximum_range: float, blast_range: float, projectile_id: int, context: String) -> void:
	if unit.is_empty():
		return
	var combat: Dictionary = unit.get("components", {}).get("combat", {})
	assert_equal(unit.get("source_unit_id"), source_id, "%s source identity" % context)
	assert_float(float(unit.get("max_hp", 0.0)), hp, "%s source health" % context)
	assert_float(float(unit.get("attack_damage", 0.0)), damage, "%s primary source attack" % context)
	assert_float(float(combat.get("range_min", 0.0)), minimum_range, "%s minimum range" % context)
	assert_float(float(combat.get("range_max", 0.0)), maximum_range, "%s maximum range" % context)
	assert_float(float(combat.get("blast_range", 0.0)), blast_range, "%s blast range" % context)
	assert_equal(int(combat.get("projectile_id", -1)), projectile_id, "%s projectile source" % context)
	for state in ["idle", "move", "attack", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(unit, state).get("asset_name"), "%s_%s" % [asset_prefix, state], "%s %s presentation" % [context, state])


func projectile_stub(source_id: int) -> Dictionary:
	return {
		"projectile_unit_id": source_id,
		"origin": Vector2.ZERO,
		"target_position": Vector2.RIGHT,
		"pos": Vector2.ZERO,
		"previous_pos": Vector2.ZERO,
		"elapsed": 0.0,
	}


func resolve_projectile(world, projectile: Dictionary) -> void:
	for unused in range(240):
		world.update_projectiles(0.05, 1)
		if not bool(projectile.get("active", true)):
			return


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
