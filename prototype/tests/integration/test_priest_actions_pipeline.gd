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
	verify_source_contract(catalog)
	verify_healing_and_medicine(catalog)
	verify_martyrdom(catalog)
	verify_replay_round_trip()
	if failures.is_empty():
		print("I12-017 Priest healing, Medicine and Martyrdom pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


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


func verify_source_contract(catalog) -> void:
	var priest_source: Dictionary = catalog.object_catalog_data.get("objects", {}).get("1:125", {})
	var commands_by_type: Dictionary = {}
	for command_value in priest_source.get("commands", []):
		var command: Dictionary = command_value
		commands_by_type[int(command.get("type", -1))] = command
	assert_near(float(commands_by_type.get(104, {}).get("work_value1", 0.0)), 0.3, 0.0001, "RoR conversion chance comes from command 104 work_value1")
	assert_equal(int(commands_by_type.get(104, {}).get("work_value2", 0)), 3, "RoR minimum chants come from command 104 work_value2")
	assert_near(float(commands_by_type.get(105, {}).get("work_value1", 0.0)), 3.0, 0.0001, "RoR healing rate comes from command 105 work_value1")
	var medicine: Dictionary = catalog.object_catalog_data.get("technologies", {}).get("119", {})
	var martyrdom: Dictionary = catalog.object_catalog_data.get("technologies", {}).get("120", {})
	assert_equal(int(medicine.get("research_location_id", -1)), 104, "Medicine belongs to Temple")
	assert_equal(int(medicine.get("research_time", -1)), 50, "Medicine original research time")
	assert_equal(int(martyrdom.get("research_location_id", -1)), 104, "Martyrdom belongs to Temple")
	assert_equal(int(martyrdom.get("research_time", -1)), 100, "Martyrdom original research time")


func verify_healing_and_medicine(catalog) -> void:
	var world = configured_world(catalog)
	var temple: Dictionary = world.add_building(970, "temple", Vector2(16.0, 16.0), 1)
	world.grant_technology(1, 103)
	assert_true(bool(world.get_research_availability(int(temple["id"]), 1, 119).get("accepted", false)), "Roman Temple exposes Medicine after Iron Age")
	assert_true(bool(world.get_research_availability(int(temple["id"]), 1, 120).get("accepted", false)), "Roman Temple exposes Martyrdom after Iron Age")

	var priest: Dictionary = world.add_unit(1, "priest", Vector2(8.0, 8.0), false)
	var wounded: Dictionary = world.add_unit(1, "clubman", Vector2(10.0, 8.0), false)
	wounded["hp"] = 10.0
	wounded["components"]["health"]["current"] = 10.0
	var controller = GameController.new(world)
	var heal = Commands.HealCommand.new(0, [int(priest["id"])], int(wounded["id"]))
	controller.enqueue_command(heal, false, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(int(heal.sequence_id)).get("accepted", false)), "HealCommand is accepted for a wounded friendly unit")
	assert_equal(String(priest.get("task", "")), "heal", "Priest enters a separate healing task")
	world.update_units(1.0, 1, 2)
	assert_near(float(wounded.get("hp", 0.0)), 13.0, 0.0001, "base Priest restores three hit points per second")
	assert_equal(String(priest.get("anim_state", "")), "Heal", "healing uses an explicit animation state")

	world.halt_unit(priest, "test_reset")
	world.grant_technology(1, 22)
	assert_near(float(priest["components"]["healing"].get("rate_multiplier", 0.0)), 1.3, 0.0001, "Astrology multiplies healing through the shared work-rate effect")
	var medicine_gold := world.get_resource_amount(1, 3)
	var research = Commands.ResearchCommand.new(0, [int(temple["id"])], "119")
	controller.enqueue_command(research, false, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(int(research.sequence_id)).get("accepted", false)), "Medicine enters the normal ResearchCommand pipeline")
	world.update_production(50.0)
	assert_equal(world.get_resource_amount(1, 3), medicine_gold - 150, "Medicine charges the original 150 gold")
	assert_equal(world.get_resource_amount(1, 56), 3, "Medicine applies the duplicated source set-to-three healing bonus deterministically")
	assert_near(world.healing_system.rate_for(priest), 7.8, 0.0001, "Medicine and Astrology compose without alias-specific branches")

	wounded["hp"] = 1.0
	wounded["components"]["health"]["current"] = 1.0
	var enhanced_heal = Commands.HealCommand.new(0, [int(priest["id"])], int(wounded["id"]))
	controller.enqueue_command(enhanced_heal, false, 1)
	controller.process_commands()
	world.update_units(1.0, 1, 2)
	assert_near(float(wounded.get("hp", 0.0)), 8.8, 0.0001, "researched healing rate is applied deterministically")


func verify_martyrdom(catalog) -> void:
	var world = configured_world(catalog)
	var temple: Dictionary = world.add_building(971, "temple", Vector2(16.0, 16.0), 1)
	world.grant_technology(1, 103)
	var priest: Dictionary = world.add_unit(1, "priest", Vector2(8.0, 8.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(10.0, 8.0), false)
	var controller = GameController.new(world)

	var conversion = Commands.ConvertCommand.new(0, [int(priest["id"])], int(enemy["id"]))
	controller.enqueue_command(conversion, false, 1)
	controller.process_commands()
	world.update_units(0.05, 1, 2)
	var locked_martyrdom = Commands.MartyrdomCommand.new(0, [int(priest["id"])])
	controller.enqueue_command(locked_martyrdom, false, 1)
	controller.process_commands()
	assert_equal(String(controller.get_command_result(int(locked_martyrdom.sequence_id)).get("reason", "")), "martyrdom_not_researched", "Martyrdom is unavailable before technology 120")

	world.halt_unit(priest, "researching_martyrdom")
	var martyrdom_gold := world.get_resource_amount(1, 3)
	var research = Commands.ResearchCommand.new(0, [int(temple["id"])], "120")
	controller.enqueue_command(research, false, 1)
	controller.process_commands()
	world.update_production(100.0)
	assert_equal(world.get_resource_amount(1, 3), martyrdom_gold - 600, "Martyrdom charges the original 600 gold")
	assert_equal(world.get_resource_amount(1, 57), 1, "Martyrdom enables its source resource flag")

	conversion = Commands.ConvertCommand.new(0, [int(priest["id"])], int(enemy["id"]))
	controller.enqueue_command(conversion, false, 1)
	controller.process_commands()
	world.update_units(0.05, 1, 2)
	var martyrdom = Commands.MartyrdomCommand.new(0, [int(priest["id"])])
	controller.enqueue_command(martyrdom, false, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(int(martyrdom.sequence_id)).get("accepted", false)), "active conversion can resolve through MartyrdomCommand")
	assert_equal(int(enemy.get("team", 0)), 1, "Martyrdom instantly transfers the enemy unit")
	assert_equal(float(priest.get("hp", 1.0)), 0.0, "Martyrdom sacrifices the Priest")
	assert_equal(String(priest.get("death_phase", "alive")), "dying", "sacrificed Priest enters the normal death lifecycle")
	assert_true(bool(enemy.get("technology_locked", false)), "Martyrdom capture preserves normal frozen conversion ownership semantics")

	world.grant_technology(1, 19)
	var second_priest: Dictionary = world.add_unit(1, "priest", Vector2(6.0, 6.0), false)
	var enemy_priest: Dictionary = world.add_unit(2, "priest", Vector2(8.0, 6.0), false)
	conversion = Commands.ConvertCommand.new(0, [int(second_priest["id"])], int(enemy_priest["id"]))
	controller.enqueue_command(conversion, false, 1)
	controller.process_commands()
	world.update_units(0.05, 1, 2)
	martyrdom = Commands.MartyrdomCommand.new(0, [int(second_priest["id"])])
	controller.enqueue_command(martyrdom, false, 1)
	controller.process_commands()
	assert_equal(String(controller.get_command_result(int(martyrdom.sequence_id)).get("reason", "")), "martyrdom_priest_immune", "Martyrdom cannot convert an enemy Priest")
	assert_true(float(second_priest.get("hp", 0.0)) > 0.0, "rejected Martyrdom does not sacrifice the Priest")
	assert_equal(int(enemy_priest.get("team", 0)), 2, "enemy Priest remains with the original owner")


func verify_replay_round_trip() -> void:
	var recorder = ReplaySystem.new()
	recorder.begin(451)
	var heal = Commands.HealCommand.new(17, [125], 777)
	heal.assign_envelope(1, 9)
	var martyrdom = Commands.MartyrdomCommand.new(18, [125])
	martyrdom.assign_envelope(1, 10)
	recorder.record_command(heal)
	recorder.record_command(martyrdom)
	var loaded = ReplaySystem.new()
	assert_true(loaded.load_json(recorder.to_json()), "replay containing Priest action commands reloads")
	var commands: Array = loaded.commands_through_tick(18)
	assert_equal(commands.size(), 2, "replay restores both Priest action commands")
	if commands.size() == 2:
		assert_equal(String(commands[0].command_type()), "heal", "replay preserves HealCommand")
		assert_equal(int(commands[0].target_entity_id), 777, "replay preserves healing target")
		assert_equal(String(commands[1].command_type()), "martyrdom", "replay preserves MartyrdomCommand")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_near(actual: float, expected: float, tolerance: float, context: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [context, expected, tolerance, actual])
