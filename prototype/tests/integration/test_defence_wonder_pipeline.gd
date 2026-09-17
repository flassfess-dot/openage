extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_source_contracts(catalog)
	verify_wall_and_tower_pipeline(catalog)
	verify_wonder_pipeline(catalog)
	verify_static_combat_determinism(catalog)
	if failures.is_empty():
		print("I12-016 defence and Wonder pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_source_contracts(catalog) -> void:
	var world = configured_world(catalog)
	assert_source_contract(world, 72, 200.0, 7, 825, -1, 786, 77, 3.0)
	assert_source_contract(world, 117, 300.0, 7, 894, -1, 785, 77, 3.0)
	assert_source_contract(world, 155, 400.0, 7, 889, -1, 698, 77, 3.0)
	assert_source_contract(world, 79, 100.0, 80, 826, 899, 491, 79, 8.0)
	assert_source_contract(world, 199, 150.0, 80, 821, 820, 491, 79, 9.0)
	assert_source_contract(world, 276, 500.0, 8000, 900, -1, 492, 707, 4.0)
	var tower: Dictionary = world.object_record_by_id(79, 1)
	assert_float(float(tower.get("combat", {}).get("attack_period", 0.0)), 1.5, "Watch Tower source attack period")
	assert_float(float(tower.get("combat", {}).get("range_max", 0.0)), 5.0, "Watch Tower source range")
	assert_equal(tower.get("combat", {}).get("projectile_id"), 9, "Watch Tower uses source arrow 9")
	var tower_attacks: Array = tower.get("combat", {}).get("attacks", [])
	assert_equal(tower_attacks.size(), 1, "Watch Tower has one source attack class")
	if not tower_attacks.is_empty():
		assert_equal(int(tower_attacks[0].get("type_id", -1)), 3, "Watch Tower source attack class")
		assert_equal(int(tower_attacks[0].get("amount", -1)), 3, "Watch Tower source attack amount")
	assert_equal(world.building_cost("wall", 1), {2: 5}, "Roman Small Wall costs the source five stone")
	assert_equal(world.building_cost("tower", 1), {2: 75}, "Roman civilization effect halves Tower stone cost")
	assert_equal(world.building_cost("wonder", 1), {3: 1000, 2: 1000, 1: 1000}, "Wonder keeps its source three-resource cost")
	assert_equal(catalog.runtime_catalog_data.get("archetypes", {}).get("wall", {}).get("runtime", {}).get("required_technology_id"), 11, "Wall runtime uses source unlock technology 11")
	assert_equal(catalog.runtime_catalog_data.get("archetypes", {}).get("tower", {}).get("runtime", {}).get("required_technology_id"), 16, "Tower runtime uses source unlock technology 16")
	assert_equal(catalog.runtime_catalog_data.get("archetypes", {}).get("wonder", {}).get("runtime", {}).get("required_technology_id"), 116, "Wonder runtime uses automatic Iron Age technology 116")


func verify_wall_and_tower_pipeline(catalog) -> void:
	var world = configured_world(catalog)
	provision(world, 1)
	world.add_building(1600, "town_center", Vector2(6.0, 6.0), 1)
	world.add_building(1601, "town_center", Vector2(54.0, 54.0), 2)
	var granary: Dictionary = world.add_building(1602, "granary", Vector2(10.0, 8.0), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(18.5, 20.5), false)
	var distant_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(50.0, 50.0), false)
	distant_enemy["stance"] = "passive"
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var wall_position := Vector2(20.5, 20.5)

	assert_true(not world.is_object_available(1, 72), "Small Wall begins unavailable")
	assert_true(not world.is_object_available(1, 79), "Watch Tower begins unavailable")
	var locked_wall = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "wall", wall_position)
	controller.enqueue_command(locked_wall, true, 1)
	controller.process_commands()
	assert_equal(controller.get_command_result(locked_wall.sequence_id).get("reason"), "building_unavailable", "normal BuildCommand rejects locked Wall")

	world.grant_technology(1, 101)
	var legal_research: Array = world.get_research_options(int(granary["id"]), 1).map(func(option): return int(option.get("technology_id", -1)))
	assert_true(legal_research.has(11) and legal_research.has(16), "legal presentation exposes Wall and Tower research after Tool Age")
	assert_true(not legal_research.has(13) and not legal_research.has(14) and not legal_research.has(12), "legal presentation hides unavailable defence upgrades")
	research_with_command(world, controller, granary, 11, 10.0)
	assert_true(world.is_object_available(1, 72), "Small Wall is enabled by source technology 11")

	var stone_before: int = world.get_resource_amount(1, 2)
	var build_wall = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "wall", wall_position)
	controller.enqueue_command(build_wall, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(build_wall.sequence_id).get("accepted", false)), "normal BuildCommand places Small Wall")
	var wall: Dictionary = find_building_kind(world, "wall")
	assert_true(not wall.is_empty(), "Wall foundation exists after accepted command")
	if wall.is_empty():
		return
	assert_equal(world.get_resource_amount(1, 2), stone_before - 5, "Wall command reserves source stone cost")
	assert_equal(wall.get("state"), "foundation", "Wall begins as ordinary foundation")
	assert_equal(catalog.building_frame_info(wall).get("graphic_id"), 77, "Wall foundation uses source construction graphic")
	advance_until(controller, func(): return String(wall.get("state", "")) == "complete", 500)
	assert_equal(wall.get("state"), "complete", "Small Wall completes through ordinary worker construction")
	assert_true(catalog.building_frame_info(wall).get("composite_parts", []).any(func(part): return String(part.get("asset_name", "")) == "graphic_702_p1"), "Small Wall resolves imported Roman composite layer")

	world.grant_technology(1, 102)
	wall["hp"] = 100.0
	wall.get("components", {}).get("health", {})["current"] = 100.0
	research_with_command(world, controller, granary, 13, 60.0)
	assert_equal(wall.get("source_unit_id"), 117, "Medium Wall upgrades the existing segment through TechnologySystem")
	assert_float(float(wall.get("max_hp", 0.0)), 300.0, "Medium Wall receives source maximum health")
	assert_float(float(wall.get("hp", 0.0)), 150.0, "Wall upgrade preserves current health percentage")
	assert_equal(catalog.building_frame_info(wall).get("asset_name"), "graphic_894_p1", "Medium Wall resolves source Roman graphic")
	world.grant_technology(1, 103)
	research_with_command(world, controller, granary, 14, 75.0)
	assert_equal(wall.get("source_unit_id"), 155, "Fortification upgrades the existing segment through TechnologySystem")
	assert_float(float(wall.get("max_hp", 0.0)), 400.0, "Fortified Wall receives source maximum health")
	assert_equal(catalog.building_frame_info(wall).get("asset_name"), "graphic_889_p1", "Fortified Wall resolves source Roman graphic")

	var adjacent: Dictionary = world.add_building(1603, "wall", wall_position + Vector2.RIGHT, 1)
	assert_true((int(wall.get("connection_mask", 0)) & 2) != 0, "Wall connection mask records an eastern same-owner neighbor")
	assert_true((int(adjacent.get("connection_mask", 0)) & 8) != 0, "adjacent Wall records the reciprocal western connection")
	assert_true(world.transfer_entity_ownership(adjacent, 2), "Wall ownership can change through the generic ownership path")
	assert_equal(int(wall.get("connection_mask", 0)) & 2, 0, "enemy-owned Wall no longer connects")
	assert_true(world.transfer_entity_ownership(adjacent, 1), "Wall can be transferred back through the same ownership path")
	assert_true((int(wall.get("connection_mask", 0)) & 2) != 0, "connection is restored for the same owner")
	adjacent["hp"] = 0.0
	world.begin_building_destruction(adjacent)
	assert_equal(int(wall.get("connection_mask", 0)) & 2, 0, "destroyed Wall immediately leaves connectivity")

	research_with_command(world, controller, granary, 16, 10.0)
	assert_true(world.is_object_available(1, 79), "Watch Tower is enabled by source technology 16")
	var tower_position := Vector2(30.0, 20.0)
	worker["pos"] = Vector2(27.0, 20.0)
	world.update_fog_of_war()
	stone_before = world.get_resource_amount(1, 2)
	var build_tower = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "tower", tower_position)
	controller.enqueue_command(build_tower, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(build_tower.sequence_id).get("accepted", false)), "normal BuildCommand places Watch Tower")
	var tower: Dictionary = find_building_kind(world, "tower")
	assert_true(not tower.is_empty(), "Tower foundation exists after accepted command")
	if tower.is_empty():
		return
	assert_equal(world.get_resource_amount(1, 2), stone_before - 75, "Tower command applies Roman source cost modifier")
	assert_equal(tower.get("source_unit_id"), 79, "new Tower begins with Watch Tower source identity")
	assert_equal(tower.get("state"), "foundation", "Tower begins as ordinary foundation")
	world.complete_foundation(tower)
	assert_true(bool(tower.get("combat_enabled", false)) and String(tower.get("stance", "")) == "stand_ground", "completed Tower is a generic stand-ground combatant")
	tower["hp"] = 50.0
	tower.get("components", {}).get("health", {})["current"] = 50.0
	research_with_command(world, controller, granary, 12, 30.0)
	assert_equal(tower.get("source_unit_id"), 199, "Sentry Tower upgrades the existing Tower through TechnologySystem")
	assert_float(float(tower.get("max_hp", 0.0)), 150.0, "Sentry Tower receives source maximum health")
	assert_float(float(tower.get("hp", 0.0)), 75.0, "Tower upgrade preserves current health percentage")
	assert_float(float(tower.get("attack_range", 0.0)), 6.0, "Sentry Tower receives source range")
	assert_float(float(tower.get("attack_damage", 0.0)), 4.0, "Sentry Tower receives source attack")
	var future_tower: Dictionary = world.add_building(1604, "tower", Vector2(38.0, 20.0), 1)
	assert_equal(future_tower.get("source_unit_id"), 199, "future Tower inherits researched source upgrade")
	assert_true(catalog.building_frame_info(future_tower).get("composite_parts", []).any(func(part): return String(part.get("asset_name", "")) == "graphic_496_p1"), "Sentry Tower resolves imported Roman composite layer")

	var target: Dictionary = world.add_unit(2, "clubman", tower_position + Vector2(4.0, 0.0), false)
	target["stance"] = "passive"
	var initial_hp := float(target.get("hp", 0.0))
	advance_until(controller, func(): return float(target.get("hp", 0.0)) < initial_hp, 120)
	assert_true(float(target.get("hp", 0.0)) < initial_hp, "Tower autonomously damages a visible enemy through projectile combat")
	assert_equal(tower.get("pos"), tower_position, "Tower remains static while acquiring and attacking")
	assert_equal(tower.get("facing"), world.facing_for_vector(Vector2(target.get("pos", Vector2.ZERO)) - tower_position), "Tower faces its target through common facing semantics")
	assert_true(world.get_resolved_projectiles().any(func(projectile): return int(projectile.get("source_id", -1)) == int(tower["id"]) and int(projectile.get("projectile_unit_id", -1)) == 9), "Tower releases source arrow 9 on its animation event")
	assert_true(controller.events_after().any(func(event): return String(event.get("type", "")) == "target_acquired" and event.get("payload", {}).get("unit_ids", []).has(int(tower["id"]))), "Tower autonomous acquisition passes through serializable AttackCommand")
	tower["anim_state"] = AnimationController.ATTACK_WINDUP
	tower["anim"] = 0.2
	assert_true(catalog.building_frame_info(tower).get("composite_parts", []).any(func(part): return String(part.get("asset_name", "")) == "graphic_496_p1"), "Tower attack presentation uses the source attack composite")
	var friendly: Dictionary = world.add_unit(1, "clubman", tower_position + Vector2(3.0, 0.0), false)
	var friendly_command = Commands.AttackCommand.new(controller.tick_index, [int(tower["id"])], int(friendly["id"]))
	controller.enqueue_command(friendly_command, true, 1)
	controller.process_commands()
	assert_equal(controller.get_command_result(friendly_command.sequence_id).get("reason"), "friendly_target", "Tower obeys common alliance and friendly-fire command checks")


func verify_wonder_pipeline(catalog) -> void:
	var world = configured_world(catalog)
	provision(world, 1)
	world.add_building(1700, "town_center", Vector2(6.0, 6.0), 1)
	world.add_building(1701, "town_center", Vector2(54.0, 54.0), 2)
	# Keep the builder outside the Wonder's imported 5.2 x 5.2 footprint;
	# placement legality intentionally treats living units as hard blockers.
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(20.5, 24.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(50.0, 50.0), false)
	enemy["stance"] = "passive"
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var position := Vector2(24.0, 24.0)
	assert_true(not world.is_object_available(1, 276), "Wonder begins unavailable")
	world.grant_technology(1, 103)
	assert_true(world.get_researched_technologies(1).has(116), "Iron Age resolves automatic Wonder technology 116")
	assert_true(world.is_object_available(1, 276), "Wonder is enabled by source technology 116")
	world.configure_victory_rules([{"type": "wonder", "hold_seconds": 0.15}])
	var wood_before: int = world.get_resource_amount(1, 1)
	var stone_before: int = world.get_resource_amount(1, 2)
	var gold_before: int = world.get_resource_amount(1, 3)
	var command = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "wonder", position)
	controller.enqueue_command(command, true, 1)
	controller.process_commands()
	var command_result: Dictionary = controller.get_command_result(command.sequence_id)
	assert_true(bool(command_result.get("accepted", false)), "normal BuildCommand places Wonder (reason=%s)" % String(command_result.get("reason", "")))
	var wonder: Dictionary = find_building_kind(world, "wonder")
	assert_true(not wonder.is_empty(), "Wonder foundation exists after accepted command")
	if wonder.is_empty():
		return
	assert_equal(world.get_resource_amount(1, 1), wood_before - 1000, "Wonder reserves source wood cost")
	assert_equal(world.get_resource_amount(1, 2), stone_before - 1000, "Wonder reserves source stone cost")
	assert_equal(world.get_resource_amount(1, 3), gold_before - 1000, "Wonder reserves source gold cost")
	assert_equal(catalog.building_frame_info(wonder).get("graphic_id"), 707, "Wonder foundation uses source construction graphic")
	var objective := objective_for_building(world, int(wonder["id"]))
	assert_true(not objective.is_empty() and not bool(objective.get("completed", true)), "Wonder foundation registers an unfinished victory objective")
	world.check_battle_state(1, 2, 1.0)
	assert_true(not world.is_battle_over(), "unfinished Wonder never advances the victory timer")
	world.complete_foundation(wonder)
	objective = objective_for_building(world, int(wonder["id"]))
	assert_true(bool(objective.get("completed", false)) and bool(objective.get("active", false)), "completed Wonder activates its rule-driven objective")
	assert_equal(catalog.building_frame_info(wonder).get("asset_name"), "graphic_900_p1", "completed Wonder resolves source player-one graphic")
	assert_true(world.transfer_entity_ownership(wonder, 2), "Wonder follows generic ownership transfer")
	objective = objective_for_building(world, int(wonder["id"]))
	assert_equal(objective.get("team"), 2, "Wonder objective follows its new owner")
	assert_equal(catalog.building_frame_info(wonder).get("asset_name"), "graphic_900_p2", "captured Wonder resolves player-two palette")
	assert_true(world.transfer_entity_ownership(wonder, 1), "Wonder can return through the same ownership path")
	objective = objective_for_building(world, int(wonder["id"]))
	assert_equal(objective.get("team"), 1, "Wonder objective follows the restored owner")
	var canonical: Dictionary = SimulationSnapshot.canonical(world, controller.tick_index, controller)
	var canonical_objectives: Array = canonical.get("world", {}).get("victory", {}).get("objectives", []).filter(func(item): return int(item.get("source_entity_id", -1)) == int(wonder["id"]))
	assert_equal(canonical_objectives.size(), 1, "canonical state retains one Wonder objective binding")
	if not canonical_objectives.is_empty():
		assert_equal(canonical_objectives[0].get("id"), wonder.get("victory_objective_id"), "canonical state binds Wonder entity and victory objective")
	world.check_battle_state(1, 2, 0.10)
	assert_true(not world.is_battle_over(), "Wonder countdown obeys configured hold duration")
	world.check_battle_state(1, 2, 0.05)
	assert_equal(world.get_victory_result().get("winner_team"), 1, "completed Wonder wins only through configured VictorySystem rule")
	assert_equal(world.get_victory_result().get("reason"), "wonder", "Wonder victory records its rule reason")

	world.configure_victory_rules([{"type": "wonder", "hold_seconds": 0.0}])
	wonder["hp"] = 0.0
	world.begin_building_destruction(wonder)
	objective = objective_for_building(world, int(wonder["id"]))
	assert_true(not bool(objective.get("active", true)), "destroyed Wonder immediately deactivates its objective")
	world.check_battle_state(1, 2, 1.0)
	assert_true(not world.is_battle_over(), "destroyed Wonder cannot satisfy the victory rule")


func verify_static_combat_determinism(catalog) -> void:
	var first := deterministic_tower_hash(catalog)
	var second := deterministic_tower_hash(catalog)
	assert_equal(first, second, "static Tower combat produces identical canonical replay hashes")


func deterministic_tower_hash(catalog) -> String:
	var world = configured_world(catalog)
	world.set_simulation_seed(12016)
	world.grant_technology(1, 101)
	world.grant_technology(1, 102)
	world.grant_technology(1, 16)
	world.grant_technology(1, 12)
	world.add_building(1800, "tower", Vector2(12.0, 12.0), 1)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(16.0, 12.0), false)
	enemy["stance"] = "passive"
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	for unused in range(80):
		controller.advance_frame(0.05, 1, 2)
	var replay = ReplaySystem.new()
	return replay.world_state_hash(world, controller.tick_index, controller)


func research_with_command(world, controller, building: Dictionary, technology_id: int, duration: float) -> void:
	var command = Commands.ResearchCommand.new(controller.tick_index, [int(building["id"])], String.num_int64(technology_id))
	controller.enqueue_command(command, true, int(building.get("team", 0)))
	controller.process_commands()
	assert_true(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "ResearchCommand accepts technology %d" % technology_id)
	world.update_production(duration + 0.01)
	assert_true(world.get_researched_technologies(int(building.get("team", 0))).has(technology_id), "technology %d completes through normal production queue" % technology_id)


func objective_for_building(world, building_id: int) -> Dictionary:
	for objective_value in world.victory_objectives:
		var objective: Dictionary = objective_value
		if int(objective.get("source_entity_id", -1)) == building_id:
			return objective
	return {}


func find_building_kind(world, kind: String) -> Dictionary:
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if String(building.get("kind", "")) == kind:
			return building
	return {}


func assert_source_contract(world, source_id: int, health: float, creation_time: int, idle_graphic: int, attack_graphic: int, death_graphic: int, construction_graphic: int, line_of_sight: float) -> void:
	var source: Dictionary = world.object_record_by_id(source_id, 1)
	assert_equal(source.get("unit_id"), source_id, "source identity %d" % source_id)
	assert_float(float(source.get("health", 0.0)), health, "source health %d" % source_id)
	assert_equal(source.get("production", {}).get("creation_time"), creation_time, "source creation time %d" % source_id)
	assert_equal(source.get("graphics", {}).get("idle"), idle_graphic, "source idle graphic %d" % source_id)
	assert_equal(source.get("graphics", {}).get("attack"), attack_graphic, "source attack graphic %d" % source_id)
	assert_equal(source.get("graphics", {}).get("death"), death_graphic, "source death graphic %d" % source_id)
	assert_equal(source.get("graphics", {}).get("construction"), construction_graphic, "source construction graphic %d" % source_id)
	assert_float(float(source.get("line_of_sight", 0.0)), line_of_sight, "source line of sight %d" % source_id)


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(64, 64))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world


func provision(world, team: int) -> void:
	for resource_type in range(4):
		world.set_resource_amount(team, resource_type, 10000)
	world.set_population_cap(team, 50)
	world.set_population_housing(team, 50)


func advance_until(controller, condition: Callable, maximum_ticks: int) -> void:
	for unused in range(maximum_ticks):
		controller.advance_frame(0.05, 1, 2)
		if condition.call():
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
