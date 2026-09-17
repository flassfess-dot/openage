extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

const ALL_SHIP_SOURCES := [13, 14, 15, 16, 17, 18, 19, 20, 21, 250, 277]
const COMBAT_SHIP_SOURCES := [19, 20, 21, 250, 277]

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_full_roster_navigation(catalog)
	verify_full_combat_roster(catalog)
	if failures.is_empty():
		print("I12-019F full-roster naval navigation/combat stress passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_full_roster_navigation(catalog) -> void:
	var world = water_world(catalog, Vector2i(48, 30))
	var sentinel := add_source_ship(world, 2, 17, Vector2(46.5, 28.5))
	sentinel["stance"] = "passive"
	var ships: Array[Dictionary] = []
	var initial_x: Dictionary = {}
	for index in range(ALL_SHIP_SOURCES.size()):
		var source_id: int = ALL_SHIP_SOURCES[index]
		var ship: Dictionary = add_source_ship(world, 1, source_id, Vector2(2.5, 2.5 + index * 2.25))
		ship["stance"] = "passive"
		ship["attack_autonomous"] = false
		ships.append(ship)
		initial_x[int(ship["id"])] = float(ship["pos"].x)
		assert_true(world.assign_command_move([ship], Vector2(44.5, 2.5 + index * 2.25)), "source %d accepts a water-domain move" % source_id)

	var violations := 0
	for _step in range(1500):
		world.advance(0.05, 1, 2)
		violations += domain_violations(world)
	var progressed := 0
	for ship in ships:
		if float(ship.get("pos", Vector2.ZERO).x) - float(initial_x[int(ship["id"])]) > 30.0:
			progressed += 1
		else:
			print("I12-019F navigation diagnostic source=%d pos=%s destination=%s task=%s path=%d status=%s reason=%s radius=%.3f desired=%s actual=%s stuck=%s" % [int(ship.get("source_unit_id", -1)), str(ship.get("pos", Vector2.ZERO)), str(ship.get("destination", Vector2.ZERO)), String(ship.get("task", "")), ship.get("path", []).size(), String(ship.get("path_status", "")), String(ship.get("diagnostic_reason", "")), float(ship.get("footprint_radius", 0.0)), str(ship.get("desired_velocity", Vector2.ZERO)), str(ship.get("actual_velocity", Vector2.ZERO)), str(ship.get("stuck_ticks", -1))])
	assert_equal(progressed, ALL_SHIP_SOURCES.size(), "every economic, transport and combat ship crosses the long water route")
	assert_equal(violations, 0, "full naval roster never leaves its source-valid water surface")
	assert_true(minimum_pair_distance(ships) > 0.05, "local avoidance prevents full-roster position collapse")


func verify_full_combat_roster(catalog) -> void:
	var world = water_world(catalog, Vector2i(48, 34))
	var attackers: Array[Dictionary] = []
	var targets: Array[Dictionary] = []
	var initial_hp: Dictionary = {}
	for index in range(COMBAT_SHIP_SOURCES.size()):
		var source_id: int = COMBAT_SHIP_SOURCES[index]
		var y := 4.5 + index * 6.0
		var attacker := add_source_ship(world, 1, source_id, Vector2(5.5, y))
		var target := add_source_ship(world, 2, source_id, Vector2(31.5, y))
		target["stance"] = "passive"
		attackers.append(attacker)
		targets.append(target)
		initial_hp[int(target["id"])] = float(target["hp"])
		assert_true(world.assign_command_attack([attacker], int(target["id"])), "source %d accepts an explicit naval attack" % source_id)

	var fired_sources: Dictionary = {}
	var violations := 0
	for _step in range(2200):
		world.advance(0.05, 1, 2)
		violations += domain_violations(world)
		for projectile_value in world.get_resolved_projectiles():
			var projectile: Dictionary = projectile_value
			var attacker: Variant = find_by_id(attackers, int(projectile.get("source_id", -1)))
			if attacker != null:
				fired_sources[int(attacker.get("source_unit_id", -1))] = int(projectile.get("projectile_unit_id", -1))
		if fired_sources.size() == COMBAT_SHIP_SOURCES.size():
			break
	assert_equal(fired_sources.size(), COMBAT_SHIP_SOURCES.size(), "every Roman naval combat source releases a projectile under load")
	assert_equal(fired_sources.get(19), 9, "Scout Ship fires source projectile 9")
	assert_equal(fired_sources.get(20), 9, "War Galley fires source projectile 9")
	assert_equal(fired_sources.get(21), 204, "Trireme fires source projectile 204")
	assert_equal(fired_sources.get(250), 368, "Catapult Trireme fires source projectile 368")
	assert_equal(fired_sources.get(277), 368, "Juggernaught fires source projectile 368")
	var damaged := 0
	for target in targets:
		if float(target.get("hp", 0.0)) < float(initial_hp[int(target["id"])]):
			damaged += 1
	assert_equal(damaged, targets.size(), "every combat source damages its assigned naval target")
	assert_equal(violations, 0, "combat approach and projectile resolution preserve water-domain legality")


func water_world(catalog, size: Vector2i):
	var world = SimulationWorld.new(size)
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain_ids: Array[int] = []
	terrain_ids.resize(size.x * size.y)
	terrain_ids.fill(1)
	var vertex_levels: Array[int] = []
	vertex_levels.resize((size.x + 1) * (size.y + 1))
	vertex_levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain_ids, "vertex_levels": vertex_levels})
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world


func add_source_ship(world, team: int, source_id: int, position: Vector2) -> Dictionary:
	var alias := alias_for_source(source_id)
	var ship: Dictionary = world.add_unit(team, alias, position, false)
	var base_source_id := int(world.data_repository.identifiers(alias).get("source_unit_id", -1))
	if source_id != base_source_id:
		world.apply_unit_upgrade_to_entity(ship, source_id)
	assert_equal(ship.get("source_unit_id"), source_id, "source %d is active in the shared runtime archetype" % source_id)
	return ship


func alias_for_source(source_id: int) -> String:
	if source_id in [13, 14]:
		return "fishing_boat"
	if source_id in [15, 16]:
		return "trade_boat"
	if source_id in [17, 18]:
		return "transport"
	if source_id in [19, 20, 21]:
		return "scout_ship"
	return "catapult_trireme"


func domain_violations(world) -> int:
	var count := 0
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var cell := Vector2i(floori(float(unit.get("pos", Vector2.ZERO).x)), floori(float(unit.get("pos", Vector2.ZERO).y)))
		if not world.navigation_grid.surface_accessible(cell, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
			count += 1
	return count


func minimum_pair_distance(units: Array[Dictionary]) -> float:
	var result := INF
	for left in range(units.size()):
		for right in range(left + 1, units.size()):
			result = minf(result, Vector2(units[left]["pos"]).distance_to(Vector2(units[right]["pos"])))
	return result


func find_by_id(units: Array[Dictionary], entity_id: int) -> Variant:
	for unit in units:
		if int(unit.get("id", -1)) == entity_id:
			return unit
	return null


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
