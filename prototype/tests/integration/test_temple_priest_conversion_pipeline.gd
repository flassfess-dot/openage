extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_temple_priest_vertical(catalog)
	if failures.is_empty():
		print("I12-011 Temple, Priest and conversion vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_temple_priest_vertical(catalog) -> void:
	var world = configured_world(catalog)
	assert_true(not world.is_object_available(1, 104), "Temple starts behind the Bronze Age and Market connector")
	world.grant_technology(1, 102)
	world.grant_technology(1, 26)
	assert_true(world.get_researched_technologies(1).has(98), "Bronze Age and Market completion resolve Temple connector 98")
	assert_true(world.is_object_available(1, 104), "Temple becomes available through its source object-enable effect")

	var temple: Dictionary = world.add_building(960, "temple", Vector2(16.0, 16.0), 1)
	assert_equal(temple.get("source_unit_id"), 104, "Temple source identity")
	assert_equal(temple.get("max_hp"), 350.0, "Temple original health")
	assert_equal(catalog.building_frame_info(temple).get("graphic_id"), 881, "Roman Temple original graphic")
	assert_true(catalog.building_frame_info(temple).get("texture") != null, "Roman Temple graphic is loadable")
	assert_true(world.get_researched_technologies(1).has(17), "completed Temple applies original Priest unlock technology")
	assert_true(world.is_object_available(1, 125), "Priest becomes available after Temple completion")
	var option_kinds: Array = world.get_unit_production_options(int(temple["id"]), 1).map(func(option): return String(option.get("kind", "")))
	assert_true(option_kinds.has("priest"), "Temple production palette exposes Priest")

	var gold_before: int = world.get_resource_amount(1, 3)
	var order: Variant = world.enqueue_unit_production(int(temple["id"]), 1, "priest")
	assert_true(order != null, "Priest enters the normal Temple production queue")
	if order == null:
		return
	assert_equal(world.get_resource_amount(1, 3), gold_before - 125, "Priest reserves original gold cost")
	world.update_production(50.0)
	var produced: Array = world.get_units().filter(func(unit): return int(unit.get("production_order_id", -1)) == int(order.get("id", -2)))
	assert_equal(produced.size(), 1, "Priest completes after original 50 second creation time")
	if produced.is_empty():
		return
	var priest: Dictionary = produced[0]
	assert_priest_source_contract(catalog, priest)
	verify_unit_conversion(world, priest)
	verify_faith_and_priest_technologies(world, priest)
	verify_monotheism_and_resistance(world, priest)
	verify_replay_round_trip(priest)


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	for team in [1, 2]:
		world.set_population_cap(team, 50)
		world.set_population_housing(team, 50)
		for resource_type in range(4):
			world.set_resource_amount(team, resource_type, 10000)
	return world


func assert_priest_source_contract(catalog, priest: Dictionary) -> void:
	assert_equal(priest.get("source_unit_id"), 125, "Priest source identity")
	assert_equal(priest.get("max_hp"), 25.0, "Priest original health")
	assert_near(float(priest.get("speed", 0.0)), 0.8, 0.0001, "Priest original movement speed")
	assert_equal(float(priest.get("components", {}).get("vision", {}).get("range", 0.0)), 12.0, "Priest original line of sight")
	assert_equal(float(priest.get("attack_range", 0.0)), 10.0, "Priest original conversion range")
	assert_true(not bool(priest.get("combat_enabled", true)), "Priest is not routed through autonomous weapon combat")
	var conversion: Dictionary = priest.get("components", {}).get("conversion", {})
	assert_true(bool(conversion.get("enabled", false)), "source command 104 enables conversion component")
	assert_equal(float(conversion.get("faith", 0.0)), 100.0, "Priest starts with full faith")
	assert_equal(int(conversion.get("min_chants", 0)), 3, "source conversion work_value2 requires at least three chants")
	assert_near(float(conversion.get("chant_interval", 0.0)), 1.5, 0.0001, "source attack period drives chant interval")
	assert_near(float(conversion.get("base_success_chance", 0.0)), 0.30, 0.0001, "RoR base success chance")
	for state in ["idle", "move", "convert", "death", "corpse"]:
		assert_equal(catalog.unit_frame_info(priest, state).get("asset_name"), "priest_%s" % state, "Priest %s presentation" % state)
	var healing: Dictionary = priest.get("components", {}).get("healing", {})
	assert_true(bool(healing.get("enabled", false)), "source command 105 enables healing component")
	assert_near(float(healing.get("base_rate", 0.0)), 3.0, 0.0001, "source healing work_value1 drives the base rate")
	assert_near(float(healing.get("range", 0.0)), 4.0, 0.0001, "RoR Priest healing range")
	assert_equal(catalog.unit_frame_info(priest, "heal").get("asset_name"), "priest_convert", "heal composite reuses the source Priest action layer")
	var presentation: Dictionary = catalog.runtime_catalog_data.get("archetypes", {}).get("priest", {}).get("runtime", {}).get("presentation_states", {})
	assert_equal(int(presentation.get("convert", {}).get("graphic_id", -1)), 36, "conversion uses source command 104 graphic")
	assert_equal(int(presentation.get("heal", {}).get("graphic_id", -1)), 816, "healing uses source command 105 composite graphic")


func verify_unit_conversion(world, priest: Dictionary) -> void:
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(priest["pos"]) + Vector2(2.0, 0.0), false)
	var original_hp := float(enemy.get("max_hp", 0.0))
	var original_source := int(enemy.get("source_unit_id", -1))
	var team_one_population: int = world.get_population(1)
	var team_two_population: int = world.get_population(2)
	priest["components"]["conversion"]["base_success_chance"] = 1.0
	var controller = GameController.new(world)
	var command = Commands.ConvertCommand.new(0, [int(priest["id"])], int(enemy["id"]))
	controller.enqueue_command(command, false, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(int(command.sequence_id)).get("accepted", false)), "authoritative ConvertCommand is accepted")
	assert_equal(String(priest.get("task", "")), "convert", "Priest enters separate conversion task")
	world.update_units(1.5, 1, 2)
	world.update_units(1.5, 1, 2)
	assert_equal(int(enemy.get("team", 0)), 2, "target cannot convert before the third chant")
	world.update_units(1.5, 1, 2)
	assert_equal(int(enemy.get("team", 0)), 1, "third guaranteed test chant transfers ownership")
	assert_equal(int(enemy.get("source_unit_id", -1)), original_source, "conversion preserves source identity")
	assert_equal(float(enemy.get("max_hp", 0.0)), original_hp, "conversion preserves captured statistics")
	assert_true(bool(enemy.get("technology_locked", false)), "converted unit records frozen technology state")
	assert_equal(int(enemy.get("components", {}).get("ownership", {}).get("civilization_id", -1)), 13, "conversion preserves original civilization identity")
	world.grant_technology(1, 63)
	assert_equal(int(enemy.get("source_unit_id", -1)), original_source, "converted unit ignores later upgrades of its new owner")
	assert_equal(world.get_population(1), team_one_population + int(enemy.get("population_cost", 0)), "conversion transfers population to new owner")
	assert_equal(world.get_population(2), team_two_population - int(enemy.get("population_cost", 0)), "conversion removes population from old owner")
	assert_equal(float(priest["components"]["conversion"].get("faith", -1.0)), 0.0, "successful conversion consumes all faith")
	assert_equal(String(priest.get("task", "")), "idle", "Priest returns to idle after conversion")


func verify_faith_and_priest_technologies(world, priest: Dictionary) -> void:
	var conversion: Dictionary = priest["components"]["conversion"]
	world.conversion_system.advance_faith(priest, 25.0)
	assert_near(float(conversion.get("faith", 0.0)), 50.0, 0.0001, "base faith recharges at two points per second")
	world.grant_technology(1, 20)
	world.conversion_system.advance_faith(priest, 10.0)
	assert_near(float(conversion.get("faith", 0.0)), 85.0, 0.0001, "Fanaticism applies the source resource-35 increase")
	assert_near(float(conversion.get("recharge_rate", 0.0)), 3.5, 0.0001, "Fanaticism source rate is visible in component state")
	world.grant_technology(1, 22)
	assert_near(float(conversion.get("chance_multiplier", 0.0)), 1.3, 0.0001, "Astrology applies original conversion multiplier")
	world.grant_technology(1, 18)
	assert_equal(float(priest.get("attack_range", 0.0)), 13.0, "Afterlife adds three conversion range")
	assert_equal(float(priest.get("components", {}).get("vision", {}).get("range", 0.0)), 15.0, "Afterlife adds three line of sight")
	world.grant_technology(1, 21)
	assert_equal(float(priest.get("max_hp", 0.0)), 50.0, "Mysticism doubles Priest health")
	world.grant_technology(1, 24)
	assert_near(float(priest.get("speed", 0.0)), 1.12, 0.0001, "Polytheism increases Priest speed by forty percent")


func verify_monotheism_and_resistance(world, upgraded_priest: Dictionary) -> void:
	# Keep the fixture inside the one-cell building conversion radius measured
	# from the authoritative occupied-cell boundary.
	var fresh_priest: Dictionary = world.add_unit(1, "priest", Vector2(8.3, 8.3), false)
	var enemy_priest: Dictionary = world.add_unit(2, "priest", Vector2(10.0, 8.0), false)
	assert_equal(world.conversion_system.validate_target(fresh_priest, enemy_priest), "monotheism_required", "enemy Priests require Monotheism")
	var enemy_house: Dictionary = world.add_building(961, "house", Vector2(9.5, 9.5), 2)
	assert_equal(world.conversion_system.validate_target(fresh_priest, enemy_house), "monotheism_required", "enemy buildings require Monotheism")
	var enemy_town_center: Dictionary = world.add_building(962, "town_center", Vector2(24.0, 24.0), 2)
	assert_equal(world.conversion_system.validate_target(fresh_priest, enemy_town_center), "conversion_immune", "Town Center is conversion immune")
	world.grant_technology(1, 19)
	assert_equal(world.conversion_system.validate_target(fresh_priest, enemy_priest), "", "Monotheism permits enemy Priest targets")
	assert_equal(world.conversion_system.validate_target(fresh_priest, enemy_house), "", "Monotheism permits enemy building targets")
	var team_one_housing: int = world.economy_system.get_population_housing(1)
	var team_two_housing: int = world.economy_system.get_population_housing(2)
	fresh_priest["components"]["conversion"]["base_success_chance"] = 1.0
	fresh_priest["components"]["conversion"]["min_chants"] = 1
	assert_equal(world.assign_command_convert([fresh_priest], int(enemy_house["id"])), "", "Monotheism building conversion order starts")
	world.update_units(1.5, 1, 2)
	assert_equal(int(enemy_house.get("team", 0)), 1, "building conversion transfers ownership")
	assert_equal(world.economy_system.get_population_housing(1), team_one_housing + int(enemy_house.get("population_support", 0)), "captured housing supports new owner")
	assert_equal(world.economy_system.get_population_housing(2), team_two_housing - int(enemy_house.get("population_support", 0)), "captured housing leaves old owner")
	var enemy_chariot: Dictionary = world.add_unit(2, "chariot", Vector2(14.0, 8.0), false)
	upgraded_priest["components"]["conversion"]["base_success_chance"] = 0.30
	assert_near(world.conversion_system.success_chance_for(upgraded_priest, enemy_chariot), 0.0975, 0.0001, "Chariot resistance multiplies Astrology chance by one quarter")


func verify_replay_round_trip(priest: Dictionary) -> void:
	var recorder = ReplaySystem.new()
	recorder.begin(451)
	var command = Commands.ConvertCommand.new(17, [int(priest.get("id", -1))], 777)
	command.assign_envelope(1, 9)
	recorder.record_command(command)
	var loaded = ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "replay containing ConvertCommand reloads")
	var commands: Array = loaded.commands_through_tick(17)
	assert_equal(commands.size(), 1, "replay restores one conversion command")
	if not commands.is_empty():
		assert_equal(String(commands[0].command_type()), "convert", "replay preserves conversion command type")
		assert_equal(int(commands[0].target_entity_id), 777, "replay preserves conversion target")
		assert_equal(int(commands[0].sequence_id), 9, "replay preserves conversion command envelope")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, context: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [context, expected, tolerance, actual])
