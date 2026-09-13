extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_dock_roster_and_upgrades(catalog)
	verify_board_unload_and_information_boundary(catalog)
	verify_capacity_and_landing_rejections(catalog)
	verify_conversion_and_destruction_policy(catalog)
	if failures.is_empty():
		print("I12-019B naval trade and transport pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_dock_roster_and_upgrades(catalog) -> void:
	var world = configured_world(catalog)
	prepare_economy(world)
	var dock: Dictionary = world.add_building(1400, "dock", Vector2(5.5, 12.5), 1)
	var trade_option: Dictionary = production_option(world, dock, "trade_boat")
	assert_equal(trade_option.get("source_unit_id"), 15, "Stone Age Dock exposes source Trade Boat 15")
	assert_equal(trade_option.get("icon_id"), 19, "Trade Boat uses original icon 19")
	assert_equal(trade_option.get("button_id"), 2, "Trade Boat uses original button 2")
	var wood_before: int = world.get_resource_amount(1, 1)
	var trade_order: Variant = world.enqueue_unit_production(int(dock["id"]), 1, "trade_boat")
	assert_true(trade_order != null, "Trade Boat enters normal Dock production")
	assert_equal(world.get_resource_amount(1, 1), wood_before - 100, "Trade Boat reserves original 100 wood")
	world.update_production(50.0)
	var trade: Variant = first_unit_of_kind(world, "trade_boat")
	assert_true(trade != null, "Trade Boat completes after original 50 seconds")
	if trade != null:
		assert_equal(trade.get("source_unit_id"), 15, "completed Trade Boat preserves source identity")
		assert_equal(trade.get("max_hp"), 200.0, "Trade Boat uses original 200 hit points")
		assert_equal(trade.get("movement_domain"), "water", "Trade Boat uses water navigation")
		assert_equal(catalog.unit_frame_info(trade, "idle").get("asset_name"), "trade_boat_idle", "Trade Boat resolves original hull art")

	assert_true(not bool(world.get_unit_production_availability(int(dock["id"]), 1, "transport").get("accepted", false)), "Transport is unavailable before the Tool Age connector")
	world.grant_technology(1, 101)
	var transport_option: Dictionary = production_option(world, dock, "transport")
	assert_equal(transport_option.get("source_unit_id"), 17, "Tool Age connector unlocks source Transport 17")
	assert_equal(transport_option.get("icon_id"), 21, "Transport uses original icon 21")
	assert_equal(transport_option.get("button_id"), 3, "Transport uses original button 3")
	wood_before = world.get_resource_amount(1, 1)
	var transport_order: Variant = world.enqueue_unit_production(int(dock["id"]), 1, "transport")
	assert_true(transport_order != null, "Transport enters normal Dock production")
	assert_equal(world.get_resource_amount(1, 1), wood_before - 150, "Transport reserves original 150 wood")
	world.update_production(75.0)
	var transport: Variant = first_unit_of_kind(world, "transport")
	assert_true(transport != null, "Transport completes after original 75 seconds")
	if transport != null:
		assert_equal(transport.get("source_unit_id"), 17, "completed Transport preserves source identity")
		assert_equal(transport.get("max_hp"), 150.0, "Transport uses original 150 hit points")
		assert_equal(transport.get("components", {}).get("cargo", {}).get("capacity"), 4, "Transport uses original four-unit capacity")
		assert_equal(catalog.unit_frame_info(transport, "idle").get("asset_name"), "transport_hull", "Transport resolves imported source hull art")

	world.grant_technology(1, 102)
	var merchant_research: Variant = world.enqueue_research(int(dock["id"]), 1, 6)
	assert_true(merchant_research != null, "Merchant Ship upgrade enters normal Dock research")
	if merchant_research != null:
		world.update_production(60.0)
	if trade != null:
		assert_equal(trade.get("source_unit_id"), 16, "existing Trade Boat upgrades to Merchant Ship source 16")
		assert_equal(trade.get("max_hp"), 250.0, "Merchant Ship uses original 250 hit points")
		assert_equal(catalog.unit_frame_info(trade, "idle").get("asset_name"), "merchant_ship_idle", "Merchant Ship resolves upgraded source art")

	world.grant_technology(1, 103)
	var heavy_research: Variant = world.enqueue_research(int(dock["id"]), 1, 8)
	assert_true(heavy_research != null, "Heavy Transport upgrade enters normal Dock research")
	if heavy_research != null:
		world.update_production(75.0)
	if transport != null:
		assert_equal(transport.get("source_unit_id"), 18, "existing Transport upgrades to Heavy Transport source 18")
		assert_equal(transport.get("max_hp"), 200.0, "Heavy Transport uses original 200 hit points")
		assert_equal(transport.get("components", {}).get("cargo", {}).get("capacity"), 8, "Heavy Transport uses original eight-unit capacity")
		assert_equal(catalog.unit_frame_info(transport, "idle").get("asset_name"), "heavy_transport_hull", "Heavy Transport resolves upgraded source hull art")


func verify_board_unload_and_information_boundary(catalog) -> void:
	var world = configured_world(catalog)
	prepare_economy(world)
	var transport: Dictionary = world.add_unit(1, "transport", Vector2(6.5, 10.5), false)
	var first: Dictionary = world.add_unit(1, "villager", Vector2(7.8, 10.2), false)
	var second: Dictionary = world.add_unit(1, "clubman", Vector2(7.9, 10.8), false)
	var enemy_observer: Dictionary = world.add_unit(2, "clubman", Vector2(8.5, 10.5), false)
	enemy_observer["stance"] = "passive"
	var population_before: int = world.get_population(1)
	var controller = GameController.new(world)
	var board = Commands.BoardCommand.new(0, [int(second["id"]), int(first["id"])], int(transport["id"]))
	controller.enqueue_command(board, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(board.sequence_id).get("accepted", false)), "BoardCommand crosses the common command boundary")
	assert_equal(world.find_unit(int(first["id"])), null, "embarked Villager leaves active spatial simulation")
	assert_equal(world.find_unit(int(second["id"])), null, "embarked military unit leaves active spatial simulation")
	assert_equal(world.get_embarked_units().map(func(unit): return int(unit["id"])), [int(first["id"]), int(second["id"])], "cargo keeps stable ordered entity IDs")
	assert_equal(transport["components"]["cargo"]["passenger_ids"], [int(first["id"]), int(second["id"])], "Transport owns deterministic passenger manifest")
	assert_equal(world.get_population(1), population_before, "boarding does not change population accounting")
	var canonical: Dictionary = SimulationSnapshot.canonical(world, 0, controller)
	assert_equal(canonical["world"]["embarked_units"].size(), 2, "canonical simulation state includes embarked units")
	world.update_fog_of_war()
	var own_transport := presentation_entity(SimulationSnapshot.presentation(world, 0, 1), int(transport["id"]))
	var enemy_transport := presentation_entity(SimulationSnapshot.presentation(world, 0, 2), int(transport["id"]))
	assert_equal(own_transport.get("components", {}).get("cargo", {}).get("count"), 2, "owner presentation exposes cargo count")
	assert_true(enemy_transport.get("components", {}).get("cargo", {}).get("passenger_ids", null) == null, "enemy presentation does not leak passenger identities")
	assert_true(enemy_transport.get("components", {}).get("cargo", {}).get("count", null) == null, "enemy presentation does not leak cargo count")

	var unload_one = Commands.UnloadCommand.new(0, [int(transport["id"])], Vector2(8.5, 10.5), [int(first["id"])])
	controller.enqueue_command(unload_one, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(unload_one.sequence_id).get("accepted", false)), "partial UnloadCommand crosses the common command boundary")
	assert_true(world.find_unit(int(first["id"])) != null, "selected passenger returns to active simulation")
	assert_equal(world.find_unit(int(first["id"])).get("team"), 1, "unloaded passenger preserves ownership")
	assert_equal(transport["components"]["cargo"]["passenger_ids"], [int(second["id"])], "partial unload preserves remaining manifest")
	assert_equal(world.find_unit(int(first["id"])).get("movement_domain"), "land", "unloaded passenger lands on its own movement domain")
	var unload_rest = Commands.UnloadCommand.new(0, [int(transport["id"])], Vector2(8.5, 11.5))
	controller.enqueue_command(unload_rest, true, 1)
	controller.process_commands()
	assert_true(world.find_unit(int(second["id"])) != null, "unload-all restores remaining passenger")
	assert_equal(transport["components"]["cargo"]["passenger_ids"], [], "unload-all clears manifest")


func verify_capacity_and_landing_rejections(catalog) -> void:
	var world = configured_world(catalog)
	prepare_economy(world)
	var transport: Dictionary = world.add_unit(1, "transport", Vector2(6.5, 16.5), false)
	var passengers: Array = []
	for index in range(5):
		passengers.append(world.add_unit(1, "villager", Vector2(7.8 + float(index % 2) * 0.1, 15.8 + float(index) * 0.3), false))
	var controller = GameController.new(world)
	var passenger_ids: Array[int] = []
	for passenger_value in passengers:
		passenger_ids.append(int(passenger_value["id"]))
	var too_many = Commands.BoardCommand.new(0, passenger_ids, int(transport["id"]))
	controller.enqueue_command(too_many, true, 1)
	controller.process_commands()
	assert_equal(controller.get_command_result(too_many.sequence_id).get("reason"), "transport_full", "capacity overflow has an explicit rejection")
	assert_equal(world.get_embarked_units().size(), 0, "capacity rejection is atomic")
	assert_equal(transport["components"]["cargo"]["passenger_ids"], [], "rejected boarding does not mutate manifest")

	var accepted = Commands.BoardCommand.new(0, [int(passengers[0]["id"])], int(transport["id"]))
	controller.enqueue_command(accepted, true, 1)
	controller.process_commands()
	var water_landing = Commands.UnloadCommand.new(0, [int(transport["id"])], Vector2(0.5, 16.5))
	controller.enqueue_command(water_landing, true, 1)
	controller.process_commands()
	assert_true(not bool(controller.get_command_result(water_landing.sequence_id).get("accepted", false)), "landing beyond Transport range is rejected")
	assert_equal(transport["components"]["cargo"]["passenger_ids"], [int(passengers[0]["id"])], "rejected unload keeps cargo aboard")


func verify_conversion_and_destruction_policy(catalog) -> void:
	var conversion_world = configured_world(catalog)
	prepare_economy(conversion_world)
	var transport: Dictionary = conversion_world.add_unit(1, "transport", Vector2(6.5, 20.5), false)
	var passenger: Dictionary = conversion_world.add_unit(1, "villager", Vector2(7.8, 20.5), false)
	assert_equal(conversion_world.board_units([passenger], transport), "", "conversion fixture boards passenger")
	assert_true(conversion_world.transfer_entity_ownership(transport, 2, 999), "enemy conversion transfers Transport")
	assert_equal(conversion_world.get_embarked_units()[0].get("team"), 1, "RoR policy keeps embarked unit under original owner")
	var enemy_controller = GameController.new(conversion_world)
	var enemy_unload = Commands.UnloadCommand.new(0, [int(transport["id"])], Vector2(8.5, 20.5))
	enemy_controller.enqueue_command(enemy_unload, true, 2)
	enemy_controller.process_commands()
	assert_true(bool(enemy_controller.get_command_result(enemy_unload.sequence_id).get("accepted", false)), "new Transport owner may unload captured cargo")
	assert_equal(conversion_world.find_unit(int(passenger["id"])).get("team"), 1, "unloaded captured cargo returns under original owner control")

	var death_world = configured_world(catalog)
	prepare_economy(death_world)
	var doomed: Dictionary = death_world.add_unit(1, "transport", Vector2(6.5, 22.5), false)
	var first: Dictionary = death_world.add_unit(1, "villager", Vector2(7.8, 22.2), false)
	var second: Dictionary = death_world.add_unit(1, "clubman", Vector2(7.8, 22.8), false)
	assert_equal(death_world.board_units([first, second], doomed), "", "destruction fixture boards passengers")
	var population_before: int = death_world.get_population(1)
	doomed["hp"] = 0.0
	death_world.begin_death(doomed)
	assert_equal(death_world.get_embarked_units().size(), 0, "destroyed Transport removes all embarked entities")
	assert_equal(doomed["components"]["cargo"]["passenger_ids"], [], "destroyed Transport clears manifest")
	assert_true(bool(first.get("removed", false)) and bool(second.get("removed", false)), "destroyed Transport destroys its cargo as in RoR")
	assert_equal(death_world.get_population(1), population_before - 3, "Transport and two passengers release population exactly once")


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
	world.set_population_cap(2, 100)
	world.set_population_housing(2, 100)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)
		world.set_resource_amount(2, resource_type, 10000)


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


func presentation_entity(snapshot: Dictionary, entity_id: int) -> Dictionary:
	for unit_value in snapshot.get("units", []):
		var unit: Dictionary = unit_value
		if int(unit.get("id", -1)) == entity_id:
			return unit
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
