extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const ContextResolver := preload("res://scripts/context_resolver.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const TradeProfitPolicy := preload("res://scripts/trade_profit_policy.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_source_driven_trade_cycle(catalog)
	verify_shared_pool_waiting(catalog)
	verify_profit_policy_boundary()
	if failures.is_empty():
		print("I12-019D naval trade pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_source_driven_trade_cycle(catalog) -> void:
	var fixture := trade_fixture(catalog, 22.5)
	var world = fixture["world"]
	var trader: Dictionary = fixture["trader"]
	var target: Dictionary = fixture["target"]
	var close_home: Dictionary = fixture["close_home"]
	var controller = GameController.new(world)
	var trade: Dictionary = trader.get("components", {}).get("trade", {})
	assert_true(bool(trade.get("enabled", false)), "source command 111 enables Trade Boat trade component")
	assert_equal(trade.get("target_building_source_id"), 45, "trade target comes from source Dock object 45")
	assert_equal(trade.get("source_input_resource_id"), 9, "source TRADE_GOODS resource ID remains evidence")
	assert_equal(trade.get("transaction_amount"), 20, "source capacity produces the original 20-resource transaction")
	assert_equal(ContextResolver.resolve([trader], target, Vector2.ZERO, 1), {"type": "trade", "target_id": int(target["id"])}, "foreign explored Dock resolves through contextual trade command")

	var choose = Commands.SetTradeResourceCommand.new(0, [int(trader["id"])], 2)
	controller.enqueue_command(choose, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(choose.sequence_id).get("accepted", false)), "trade resource selection crosses common command boundary")
	assert_equal(trade.get("selected_input_resource_type_id"), 2, "Trade Boat stores selected stone input")

	world.set_trade_resource([trader], 1)
	world.trade_system.set_trade_goods(2, 20.0)
	world.set_resource_amount(1, 1, 100)
	world.set_resource_amount(1, 3, 0)
	var target_resources_before := resource_vector(world, 2)
	var expected_gold := TradeProfitPolicy.profit_between(close_home["pos"], target["pos"], world.map_size)
	var route = Commands.TradeCommand.new(0, [int(trader["id"])], int(target["id"]))
	controller.enqueue_command(route, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(route.sequence_id).get("accepted", false)), "TradeCommand crosses the common command boundary")
	assert_equal(trade.get("home_dock_id"), int(close_home["id"]), "route deterministically chooses own Dock nearest to foreign target")
	advance_until(world, func(): return int(trade.get("trip_count", 0)) >= 1, 2200)
	assert_equal(trade.get("trip_count"), 1, "Trade Boat completes target and return legs")
	assert_equal(world.get_resource_amount(1, 1), 80, "one voyage spends exactly 20 selected resources")
	assert_equal(world.get_resource_amount(1, 3), expected_gold, "returning Trade Boat deposits distance-policy gold")
	assert_equal(resource_vector(world, 2), target_resources_before, "trade never mutates target player's ordinary stockpile")
	assert_equal(trade.get("cargo_gold"), 0, "gold cargo clears exactly at home Dock")
	assert_equal(trade.get("stage"), "to_target", "successful route repeats like RoR")
	var canonical: Dictionary = SimulationSnapshot.canonical(world, 0, controller)
	assert_true(canonical.get("world", {}).get("trade", {}).has("pools"), "canonical state includes deterministic shared trade-goods pools")
	var own_view := presentation_entity(SimulationSnapshot.presentation(world, 0, 1), int(trader["id"]))
	var enemy_view := presentation_entity(SimulationSnapshot.presentation(world, 0, 2), int(trader["id"]))
	var dock_view := presentation_entity(SimulationSnapshot.presentation(world, 0, 1), int(close_home["id"]))
	assert_equal(dock_view.get("target_domains"), ["land", "water"], "Dock presentation exposes source-derived mixed combat reachability to legal-knowledge AI")
	assert_true(own_view.get("components", {}).get("trade", {}).has("target_dock_id"), "owner presentation exposes route state")
	if not enemy_view.is_empty():
		assert_true(not enemy_view.get("components", {}).get("trade", {}).has("cargo_gold"), "enemy presentation does not leak trade cargo")


func verify_shared_pool_waiting(catalog) -> void:
	var fixture := trade_fixture(catalog, 13.5)
	var world = fixture["world"]
	var trader: Dictionary = fixture["trader"]
	var target: Dictionary = fixture["target"]
	var trade: Dictionary = trader["components"]["trade"]
	world.set_resource_amount(1, 1, 100)
	world.trade_system.set_trade_goods(2, 0.0, 100.0, 1.0)
	assert_equal(world.assign_command_trade([trader], target), "", "valid route starts with an empty target trade-goods pool")
	advance_until(world, func(): return String(trade.get("stage", "")) == "waiting_goods", 250)
	assert_equal(trade.get("stage"), "waiting_goods", "trader waits at foreign Dock while shared goods are unavailable (pos=%s approach=%s destination=%s path=%s reason=%s goods=%s)" % [trader.get("pos"), trade.get("approach_position"), trader.get("destination"), trader.get("path_status"), trader.get("diagnostic_reason"), world.get_trade_goods(2)])
	assert_equal(world.get_resource_amount(1, 1), 100, "waiting does not spend selected resource early")
	advance_until(world, func(): return int(trade.get("cargo_gold", 0)) > 0, 500)
	assert_true(int(trade.get("cargo_gold", 0)) > 0, "shared target-player goods recover and release the waiting trader")
	assert_equal(world.get_resource_amount(1, 1), 80, "resource is spent only when a full 20-good batch loads")


func verify_profit_policy_boundary() -> void:
	var metadata := TradeProfitPolicy.metadata()
	assert_equal(metadata.get("calibration_status"), "measurement_pending", "unverified legacy distance curve is not falsely claimed as parity")
	var near := TradeProfitPolicy.profit_between(Vector2(1, 1), Vector2(2, 1), Vector2i(28, 28))
	var far := TradeProfitPolicy.profit_between(Vector2(1, 1), Vector2(25, 25), Vector2i(28, 28))
	assert_true(far > near, "isolated provisional profit policy is monotonic with route distance")
	assert_true(near >= 7 and far <= 75, "profit policy stays within observed RoR bounds")


func trade_fixture(catalog, target_y: float) -> Dictionary:
	var world = configured_world(catalog)
	var far_home: Dictionary = world.add_building(1500, "dock", Vector2(5.5, 4.5), 1)
	var close_home: Dictionary = world.add_building(1501, "dock", Vector2(5.5, 9.5), 1)
	var target: Dictionary = world.add_building(1502, "dock", Vector2(5.5, target_y), 2)
	var trader: Dictionary = world.add_unit(1, "trade_boat", Vector2(5.5, target_y + 2.5), false)
	trader["pos"] = Vector2(5.5, 18.5 if target_y < 16.0 else 6.5)
	world.sync_all_components()
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	return {"world": world, "far_home": far_home, "close_home": close_home, "target": target, "trader": trader}


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
	for team in [1, 2]:
		world.set_population_cap(team, 100)
		world.set_population_housing(team, 100)
		for resource_type in range(4):
			world.set_resource_amount(team, resource_type, 1000)
	return world


func advance_until(world, condition: Callable, maximum_ticks: int) -> void:
	for unused in range(maximum_ticks):
		world.advance(0.05, 1, 2)
		if condition.call():
			return


func resource_vector(world, team: int) -> Array[int]:
	return [world.get_resource_amount(team, 0), world.get_resource_amount(team, 1), world.get_resource_amount(team, 2), world.get_resource_amount(team, 3)]


func presentation_entity(snapshot: Dictionary, entity_id: int) -> Dictionary:
	for collection_name in ["units", "buildings", "resources"]:
		for entity_value in snapshot.get(collection_name, []):
			var entity: Dictionary = entity_value
			if int(entity.get("id", -1)) == entity_id:
				return entity
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
