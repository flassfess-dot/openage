extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_dock_combat_roster_and_upgrades(catalog)
	verify_source_projectile_combat(catalog)
	verify_catapult_trireme_blast(catalog)
	if failures.is_empty():
		print("I12-019C naval combat vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_dock_combat_roster_and_upgrades(catalog) -> void:
	var world = configured_world(catalog)
	prepare_economy(world)
	var dock: Dictionary = world.add_building(1500, "dock", Vector2(5.5, 12.5), 1)
	assert_true(not bool(world.get_unit_production_availability(int(dock["id"]), 1, "scout_ship").get("accepted", false)), "Scout Ship is locked before original Tool Age connector")
	world.grant_technology(1, 101)
	var option: Dictionary = production_option(world, dock, "scout_ship")
	assert_equal(option.get("source_unit_id"), 19, "Tool Age Dock exposes source Scout Ship 19")
	assert_equal(option.get("icon_id"), 22, "Scout Ship uses original icon 22")
	assert_equal(option.get("button_id"), 4, "Scout Ship uses original button 4")
	var wood_before: int = world.get_resource_amount(1, 1)
	var order: Variant = world.enqueue_unit_production(int(dock["id"]), 1, "scout_ship")
	assert_true(order != null, "Scout Ship enters normal Dock production")
	assert_equal(world.get_resource_amount(1, 1), wood_before - 135, "Scout Ship reserves original 135 wood")
	world.update_production(60.0)
	var ship: Variant = first_unit_of_kind(world, "scout_ship")
	assert_true(ship != null, "Scout Ship completes after original 60 seconds")
	if ship == null:
		return
	assert_ship_stats(ship, 19, 120.0, 5.0, 1.5, 9, "Scout Ship")
	var scout_art: Dictionary = catalog.unit_frame_info(ship, "attack")
	assert_equal(scout_art.get("asset_name"), "scout_ship_hull", "Scout Ship resolves imported source hull")
	assert_equal(scout_art.get("composite_parts", []).map(func(part): return String(part.get("asset_name", ""))), ["transport_sail"], "Scout Ship composes source sail")

	world.grant_technology(1, 102)
	var bronze_food: int = world.get_resource_amount(1, 0)
	wood_before = world.get_resource_amount(1, 1)
	var war_galley_research: Variant = world.enqueue_research(int(dock["id"]), 1, 5)
	assert_true(war_galley_research != null, "War Galley upgrade enters normal Dock research")
	assert_equal(world.get_resource_amount(1, 0), bronze_food - 150, "War Galley upgrade reserves original 150 food")
	assert_equal(world.get_resource_amount(1, 1), wood_before - 75, "War Galley upgrade reserves original 75 wood")
	if war_galley_research != null:
		world.update_production(75.0)
	assert_ship_stats(ship, 20, 160.0, 6.0, 1.7000000476837158, 9, "War Galley")
	assert_equal(catalog.unit_frame_info(ship, "idle").get("asset_name"), "war_galley_hull", "War Galley resolves source hull variant")

	world.grant_technology(1, 103)
	var trireme_research: Variant = world.enqueue_research(int(dock["id"]), 1, 7)
	assert_true(trireme_research != null, "Trireme upgrade enters normal Dock research")
	if trireme_research != null:
		world.update_production(100.0)
	assert_ship_stats(ship, 21, 200.0, 7.0, 1.7999999523162842, 204, "Trireme")
	var trireme_art: Dictionary = catalog.unit_frame_info(ship, "attack")
	assert_equal(trireme_art.get("asset_name"), "trireme_hull", "Trireme resolves source hull variant")
	assert_equal(trireme_art.get("composite_parts", []).map(func(part): return String(part.get("asset_name", ""))), ["trireme_oars", "heavy_transport_sail"], "Trireme composes source oars and sail")

	assert_true(not bool(world.get_unit_production_availability(int(dock["id"]), 1, "catapult_trireme").get("accepted", false)), "Catapult Trireme remains locked until original technology 9")
	var catapult_unlock: Variant = world.enqueue_research(int(dock["id"]), 1, 9)
	assert_true(catapult_unlock != null, "Catapult Trireme unlock enters normal Dock research")
	if catapult_unlock != null:
		world.update_production(100.0)
	var catapult_option: Dictionary = production_option(world, dock, "catapult_trireme")
	assert_equal(catapult_option.get("source_unit_id"), 250, "technology 9 exposes source Catapult Trireme 250")
	assert_equal(catapult_option.get("icon_id"), 30, "Catapult Trireme uses original icon 30")
	assert_equal(catapult_option.get("button_id"), 5, "Catapult Trireme uses original button 5")
	wood_before = world.get_resource_amount(1, 1)
	var gold_before: int = world.get_resource_amount(1, 3)
	var catapult_order: Variant = world.enqueue_unit_production(int(dock["id"]), 1, "catapult_trireme")
	assert_true(catapult_order != null, "Catapult Trireme enters normal Dock production")
	assert_equal(world.get_resource_amount(1, 1), wood_before - 135, "Catapult Trireme reserves original 135 wood")
	assert_equal(world.get_resource_amount(1, 3), gold_before - 75, "Catapult Trireme reserves original 75 gold")
	if catapult_order != null:
		world.update_production(90.0)
	var catapult: Variant = first_unit_of_kind(world, "catapult_trireme")
	assert_true(catapult != null, "Catapult Trireme completes after original 90 seconds")
	if catapult != null:
		assert_ship_stats(catapult, 250, 120.0, 9.0, 5.0, 368, "Catapult Trireme")
		assert_float(float(catapult.get("components", {}).get("combat", {}).get("blast_range", 0.0)), 1.0, "Catapult Trireme original blast radius")
		assert_true(bool(catapult.get("components", {}).get("combat", {}).get("friendly_fire", false)), "Catapult Trireme uses explicit source-style friendly fire policy")
		assert_equal(catalog.unit_frame_info(catapult, "attack").get("composite_parts", []).map(func(part): return String(part.get("asset_name", ""))), ["catapult_trireme_weapon", "heavy_transport_sail"], "Catapult Trireme composes weapon and sail")

	world.grant_technology(1, 35)
	var juggernaught_research: Variant = world.enqueue_research(int(dock["id"]), 1, 25)
	assert_true(juggernaught_research != null, "Rise of Rome Juggernaught upgrade 25 enters Dock research")
	if juggernaught_research != null:
		world.update_production(180.0)
	if catapult != null:
		assert_ship_stats(catapult, 277, 200.0, 12.0, 5.0, 368, "Juggernaught")
		assert_float(float(catapult.get("components", {}).get("combat", {}).get("blast_range", 0.0)), 1.5, "Juggernaught original blast radius")
	var future_juggernaught: Dictionary = world.add_unit(1, "catapult_trireme", Vector2(8.0, 12.0), false)
	assert_ship_stats(future_juggernaught, 277, 200.0, 12.0, 5.0, 368, "Future Juggernaught")
	assert_true(not bool(world.get_research_availability(int(dock["id"]), 1, 118).get("accepted", false)), "Roman Fire Galley connector 118 remains unavailable")
	assert_true(not world.is_object_available(1, 360), "Roman Fire Galley source 360 remains disabled")


func verify_source_projectile_combat(catalog) -> void:
	var world = configured_world(catalog)
	var attacker: Dictionary = world.add_unit(1, "scout_ship", Vector2(2.0, 8.0), false)
	var target: Dictionary = world.add_unit(2, "scout_ship", Vector2(5.5, 8.0), false)
	target["stance"] = "passive"
	var health_before := float(target["hp"])
	world.assign_command_attack([attacker], int(target["id"]))
	for unused in range(300):
		world.advance(0.05, 1, 2)
		if not world.get_resolved_projectiles().is_empty():
			break
	assert_true(not world.get_resolved_projectiles().is_empty(), "ship attack releases projectile on source animation event")
	if world.get_resolved_projectiles().is_empty():
		return
	var projectile: Dictionary = world.get_resolved_projectiles()[-1]
	assert_equal(projectile.get("projectile_unit_id"), 9, "Scout Ship fires original projectile 9")
	assert_float(health_before - float(target["hp"]), 5.0, "Scout Ship class-3 attack deals its original five damage when the target has no class-3 armor")
	assert_equal(projectile.get("source_id"), int(attacker["id"]), "resolved projectile keeps authoritative ship source")


func verify_catapult_trireme_blast(catalog) -> void:
	var world = configured_world(catalog)
	var attacker: Dictionary = world.add_unit(1, "catapult_trireme", Vector2(2.0, 18.0), false)
	var target: Dictionary = world.add_unit(2, "scout_ship", Vector2(5.0, 18.0), false)
	var adjacent: Dictionary = world.add_unit(2, "scout_ship", Vector2(5.0, 18.6), false)
	var friendly: Dictionary = world.add_unit(1, "scout_ship", Vector2(5.0, 17.4), false)
	var target_hp := float(target["hp"])
	var adjacent_hp := float(adjacent["hp"])
	var friendly_hp := float(friendly["hp"])
	var projectile: Dictionary = world.spawn_projectile(attacker, target)
	assert_equal(projectile.get("projectile_unit_id"), 368, "Catapult Trireme fires original projectile 368")
	assert_float(float(projectile.get("speed", 0.0)), 2.700000047683716, "projectile 368 uses original speed")
	assert_float(float(projectile.get("blast_range", 0.0)), 1.0, "projectile inherits source blast radius")
	assert_true(bool(projectile.get("friendly_fire", false)), "projectile carries explicit friendly-fire policy")
	assert_equal(projectile.get("impact_effect_graphic_id"), 270, "projectile carries original impact graphic 270")
	assert_equal(catalog.projectile_animation_frames(368).size(), 3, "projectile 368 loads the three-frame rock flight")
	assert_equal(catalog.projectile_frame_info(projectile).get("asset_name"), "siege_rock", "projectile 368 uses the corrected rock art")
	for unused in range(200):
		world.update_projectiles(0.05, 1)
		if not bool(projectile.get("active", true)):
			break
	assert_float(target_hp - float(target["hp"]), 35.0, "Catapult Trireme class-6 attack deals original 35 damage to direct naval target")
	assert_float(adjacent_hp - float(adjacent["hp"]), 35.0, "source blast deals the same 35 damage without invented falloff")
	assert_float(friendly_hp - float(friendly["hp"]), 35.0, "source-style catapult blast deals 35 damage to a nearby friendly ship")
	assert_equal(projectile.get("hit_target_ids", []).size(), 3, "naval blast records deterministic affected set")


func assert_ship_stats(ship: Dictionary, source_id: int, hp: float, attack_range: float, period: float, projectile_id: int, context: String) -> void:
	assert_equal(ship.get("source_unit_id"), source_id, "%s source identity" % context)
	assert_float(float(ship.get("max_hp", 0.0)), hp, "%s hit points" % context)
	assert_float(float(ship.get("attack_range", 0.0)), attack_range, "%s range" % context)
	assert_float(float(ship.get("attack_period", 0.0)), period, "%s attack period" % context)
	assert_equal(ship.get("projectile_id"), projectile_id, "%s projectile" % context)
	assert_equal(ship.get("movement_domain"), "water", "%s water navigation domain" % context)


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(28, 28))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain_ids: Array[int] = []
	for y in range(28):
		for x in range(28):
			terrain_ids.append(1 if x <= 6 else 2 if x == 7 else 0)
	var vertex_levels: Array[int] = []
	vertex_levels.resize(29 * 29)
	vertex_levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain_ids, "vertex_levels": vertex_levels})
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	var sentinel: Dictionary = world.add_unit(2, "clubman", Vector2(24.5, 24.5), false)
	sentinel["stance"] = "passive"
	return world


func prepare_economy(world) -> void:
	world.set_population_cap(1, 100)
	world.set_population_housing(1, 100)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 20000)


func production_option(world, dock: Dictionary, kind: String) -> Dictionary:
	for option_value in world.get_unit_production_options(int(dock["id"]), 1):
		var option: Dictionary = option_value
		if String(option.get("kind", "")) == kind:
			return option
	return {}


func first_unit_of_kind(world, kind: String) -> Variant:
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if String(unit.get("kind", "")) == kind:
			return unit
	return null


func assert_float(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
