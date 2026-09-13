extends SceneTree

const AiEconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_source_contracts_and_age_replacements(catalog)
	verify_government_center_pipeline(catalog)
	if failures.is_empty():
		print("I12-015 core building age and Government Center pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_source_contracts_and_age_replacements(catalog) -> void:
	var world = configured_world(catalog)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)

	assert_building_contract(world, "house", 70, 75.0, 20, 817, 86, 491, {1: 26})
	assert_building_contract(world, "barracks", 12, 350.0, 30, 13, 82, 492, {1: 106})
	assert_building_contract(world, "storage_pit", 103, 350.0, 30, 515, 82, 492, {1: 102})
	assert_building_contract(world, "town_center", 109, 600.0, 60, 598, 82, 492, {1: 170})

	var town_center: Dictionary = world.add_building(1100, "town_center", Vector2(6.0, 6.0), 1)
	var house: Dictionary = world.add_building(1101, "house", Vector2(14.0, 6.0), 1)
	var barracks: Dictionary = world.add_building(1102, "barracks", Vector2(6.0, 14.0), 1)
	var storage: Dictionary = world.add_building(1103, "storage_pit", Vector2(14.0, 14.0), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(25.0, 25.0), false)
	var berries: Dictionary = world.add_resource("berries", Vector2(27.0, 25.0), 80)
	world.assign_command_gather([worker], int(berries["id"]))
	var worker_resource_id := int(worker.get("resource_id", -1))
	var housing_before: int = world.economy_system.get_population_housing(1)
	var town_center_id := int(town_center["id"])
	var house_id := int(house["id"])
	var barracks_id := int(barracks["id"])
	var storage_id := int(storage["id"])
	var rally_point := Vector2(22.0, 9.0)
	assert_true(world.set_rally_point(town_center_id, rally_point), "Town Center accepts a rally point before age replacement")
	var queued_villager: Variant = world.enqueue_unit_production(town_center_id, 1, "villager")
	assert_true(queued_villager != null, "Town Center accepts a normal production order before age replacement")
	var queued_order_id := int(queued_villager.get("id", -1)) if queued_villager != null else -1
	house["hp"] = 37.5
	house.get("components", {}).get("health", {})["current"] = 37.5

	world.grant_technology(1, 101)
	assert_equal(house.get("source_unit_id"), 154, "Tool Age replaces existing House 70 with source 154")
	assert_equal(house.get("id"), house_id, "House replacement preserves entity ID")
	assert_float(float(house.get("hp", 0.0)), 37.5, "House replacement preserves health percentage")
	assert_equal(house.get("population_support"), 4, "House replacement preserves population support component")
	assert_equal(world.economy_system.get_population_housing(1), housing_before, "House replacement does not duplicate housing")
	var house_frame: Dictionary = catalog.building_frame_info(house)
	assert_equal(house_frame.get("graphic_id"), 869, "Tool Age House resolves Roman source graphic 869")
	assert_true(house_frame.get("composite_parts", []).any(func(part): return int(part.get("graphic_id", -1)) == 868 and String(part.get("asset_name", "")) == "graphic_868_p1"), "Tool Age House renders the available Roman composite base")
	var enemy_house: Dictionary = world.add_building(1105, "house", Vector2(32.0, 6.0), 2)
	world.grant_technology(2, 101)
	assert_true(catalog.building_frame_info(enemy_house).get("composite_parts", []).any(func(part): return String(part.get("asset_name", "")) == "graphic_868_p2"), "Tool Age House resolves player-two palette")

	world.grant_technology(1, 102)
	assert_equal(town_center.get("source_unit_id"), 71, "Bronze Age replaces existing Town Center 109 with source 71")
	assert_equal(barracks.get("source_unit_id"), 132, "Bronze Age replaces existing Barracks 12 with source 132")
	assert_equal(storage.get("source_unit_id"), 105, "Bronze Age replaces existing Storage Pit 103 with source 105")
	assert_equal(town_center.get("id"), town_center_id, "Town Center replacement preserves entity ID")
	assert_equal(barracks.get("id"), barracks_id, "Barracks replacement preserves entity ID")
	assert_equal(storage.get("id"), storage_id, "Storage Pit replacement preserves entity ID")
	assert_equal(town_center.get("rally_point"), rally_point, "Town Center replacement preserves rally point")
	assert_true(town_center.get("production_queue", []).any(func(order): return int(order.get("id", -1)) == queued_order_id), "Town Center replacement preserves active production queue")
	assert_equal(worker.get("task"), "gather", "age replacements preserve unrelated worker orders")
	assert_equal(worker.get("resource_id"), worker_resource_id, "age replacements preserve worker targets")
	assert_true(world.dropoff_accepts_resource(storage, 1), "upgraded Storage Pit retains wood drop-site policy")
	assert_true(world.dropoff_accepts_resource(storage, 2), "upgraded Storage Pit retains stone drop-site policy")
	assert_true(world.dropoff_accepts_resource(storage, 3), "upgraded Storage Pit retains gold drop-site policy")
	assert_equal(catalog.building_frame_info(town_center).get("asset_name"), "graphic_885_p1", "Bronze Age Town Center resolves Roman graphic")
	assert_equal(catalog.building_frame_info(barracks).get("asset_name"), "graphic_857_p1", "Bronze Age Barracks resolves Roman graphic")
	assert_equal(catalog.building_frame_info(storage).get("asset_name"), "graphic_879_p1", "Bronze Age Storage Pit resolves Roman graphic")

	var future_house: Dictionary = world.add_building(1106, "house", Vector2(32.0, 14.0), 1)
	var future_barracks: Dictionary = world.add_building(1107, "barracks", Vector2(6.0, 32.0), 1)
	var future_storage: Dictionary = world.add_building(1108, "storage_pit", Vector2(14.0, 32.0), 1)
	var future_town_center: Dictionary = world.add_building(1109, "town_center", Vector2(32.0, 32.0), 1)
	assert_equal(future_house.get("source_unit_id"), 154, "future House inherits Tool Age source replacement")
	assert_equal(future_barracks.get("source_unit_id"), 132, "future Barracks inherits Bronze Age source replacement")
	assert_equal(future_storage.get("source_unit_id"), 105, "future Storage Pit inherits Bronze Age source replacement")
	assert_equal(future_town_center.get("source_unit_id"), 71, "future Town Center inherits Bronze Age source replacement")
	var canonical: Dictionary = SimulationSnapshot.canonical(world, 12)
	assert_equal(canonical_source_id(canonical, town_center_id), 71, "canonical snapshot records upgraded Town Center identity")
	assert_equal(canonical_source_id(canonical, house_id), 154, "canonical snapshot records upgraded House identity")
	assert_equal(canonical_source_id(canonical, barracks_id), 132, "canonical snapshot records upgraded Barracks identity")
	assert_equal(canonical_source_id(canonical, storage_id), 105, "canonical snapshot records upgraded Storage Pit identity")


func verify_government_center_pipeline(catalog) -> void:
	var world = configured_world(catalog)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)
	world.add_building(1200, "town_center", Vector2(5.0, 5.0), 1)
	world.add_building(1201, "granary", Vector2(5.0, 13.0), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(23.0, 19.0), false)
	var distant_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(44.0, 44.0), false)
	distant_enemy["stance"] = "passive"
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var government_position := Vector2(20.0, 20.0)

	var runtime: Dictionary = catalog.runtime_catalog_data.get("archetypes", {}).get("government_center", {}).get("runtime", {})
	assert_equal(runtime.get("required_technology_id"), 93, "Government Center uses original Bronze Age plus Market connector 93")
	assert_true(not world.is_object_available(1, 82), "Government Center begins unavailable")
	var locked_command = Commands.BuildCommand.new(0, [int(worker["id"])], "government_center", government_position)
	controller.enqueue_command(locked_command, true, 1)
	controller.process_commands()
	assert_equal(controller.get_command_result(locked_command.sequence_id).get("reason"), "building_unavailable", "normal BuildCommand rejects Government Center before its connector")

	world.grant_technology(1, 101)
	assert_true(world.get_researched_technologies(1).has(94), "Tool Age and Granary resolve Market connector 94")
	var market: Dictionary = world.add_building(1202, "market", Vector2(13.0, 5.0), 1)
	assert_true(world.get_researched_technologies(1).has(26), "completed Market supplies Government Center prerequisite 26")
	world.grant_technology(1, 102)
	assert_true(world.get_researched_technologies(1).has(93), "Bronze Age and Market resolve Government Center connector 93")
	assert_true(world.is_object_available(1, 82), "Government Center becomes available through original object-enable effect")
	var source: Dictionary = world.object_record_by_id(82, 1)
	assert_equal(source.get("health"), 350.0, "Government Center uses original 350 hit points")
	assert_equal(source.get("production", {}).get("creation_time"), 60, "Government Center uses original 60 second construction time")
	assert_equal(source.get("graphics", {}).get("idle"), 861, "Government Center uses Roman expansion graphic 861")
	assert_equal(source.get("production", {}).get("research_id"), 33, "Government Center keeps original completion technology 33")
	assert_equal(world.building_cost("government_center", 1), {1: 149}, "Roman building discount applies to Government Center 175 wood cost")

	var wood_before: int = world.get_resource_amount(1, 1)
	var build_command = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "government_center", government_position)
	controller.enqueue_command(build_command, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(build_command.sequence_id).get("accepted", false)), "normal BuildCommand places Government Center")
	var candidates: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "government_center")
	assert_equal(candidates.size(), 1, "one Government Center foundation is created")
	if candidates.is_empty():
		return
	var government: Dictionary = candidates[0]
	assert_equal(world.get_resource_amount(1, 1), wood_before - 149, "Government Center reserves discounted Roman wood cost")
	assert_equal(government.get("state"), "foundation", "Government Center begins as ordinary foundation")
	assert_equal(catalog.building_frame_info(government).get("graphic_id"), 82, "Government Center construction uses original 3x3 construction graphic")
	advance_until(controller, func(): return String(government.get("state", "")) == "complete", 2600)
	assert_equal(government.get("state"), "complete", "Government Center completes through ordinary worker construction (progress=%.3f worker_task=%s pos=%s slot=%s destination=%s path_status=%s reason=%s)" % [float(government.get("construction_progress", 0.0)), String(worker.get("task", "")), str(worker.get("pos", Vector2.ZERO)), str(worker.get("building_approach_slot", null)), str(worker.get("destination", null)), String(worker.get("path_status", "")), String(worker.get("diagnostic_reason", ""))])
	if String(government.get("state", "")) != "complete":
		return
	assert_true(world.get_researched_technologies(1).has(33), "completed Government Center applies original completion technology")
	assert_equal(catalog.building_frame_info(government).get("asset_name"), "graphic_861_p1", "Government Center resolves player-one Roman palette")
	var enemy_government: Dictionary = world.add_building(1203, "government_center", Vector2(38.0, 38.0), 2)
	assert_equal(catalog.building_frame_info(enemy_government).get("asset_name"), "graphic_861_p2", "Government Center resolves player-two Roman palette")

	var research_ids: Array = world.get_research_options(int(government["id"]), 1).map(func(option): return int(option.get("technology_id", -1)))
	for technology_id in [34, 112, 114, 121]:
		assert_true(research_ids.has(technology_id), "Government Center exposes allowed Bronze Age technology %d" % technology_id)
	assert_true(not research_ids.has(37), "Roman disabled technology 37 is absent from Government Center palette")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, controller.tick_index, 1)
	var ai_commands: Array = AiEconomicPlanner.plan(presentation, controller.tick_index + 1, 1)
	assert_true(ai_commands.any(func(command): return command.command_type() == "research" and command.unit_ids.has(int(government["id"]))), "AI discovers Government Center research only through legal presentation options")

	var cavalry: Dictionary = world.add_unit(1, "cavalry", Vector2(28.0, 20.0), false)
	cavalry["hp"] = 75.0
	cavalry.get("components", {}).get("health", {})["current"] = 75.0
	var food_before: int = world.get_resource_amount(1, 0)
	var gold_before: int = world.get_resource_amount(1, 3)
	var nobility: Variant = world.enqueue_research(int(government["id"]), 1, 34)
	assert_true(nobility != null, "Nobility enters the normal Government Center research queue")
	if nobility != null:
		assert_equal(world.get_resource_amount(1, 0), food_before - 175, "Nobility reserves original food cost")
		assert_equal(world.get_resource_amount(1, 3), gold_before - 120, "Nobility reserves original gold cost")
		world.update_production(70.0)
	assert_true(world.get_researched_technologies(1).has(34), "Nobility completes after original research time")
	assert_float(float(cavalry.get("max_hp", 0.0)), 172.5, "Nobility class effect updates existing Cavalry maximum health")
	assert_float(float(cavalry.get("hp", 0.0)), 86.25, "Nobility preserves existing Cavalry health percentage")
	var future_cavalry: Dictionary = world.add_unit(1, "cavalry", Vector2(30.0, 20.0), false)
	assert_float(float(future_cavalry.get("max_hp", 0.0)), 172.5, "future Cavalry inherits persistent Nobility class effect")
	var architecture: Variant = world.enqueue_research(int(government["id"]), 1, 37)
	assert_true(architecture == null, "Roman technology tree rejects disabled Government Center technology 37")
	assert_equal(world.last_research_failure, "technology_disabled", "disabled Government Center research reports source technology-tree reason")
	var canonical: Dictionary = SimulationSnapshot.canonical(world, controller.tick_index, controller)
	assert_equal(canonical_source_id(canonical, int(government["id"])), 82, "canonical snapshot retains Government Center source identity")
	assert_true(canonical.get("world", {}).get("technology_team_states", {}).get(1, {}).get("researched", {}).has(34), "canonical snapshot retains Government Center research state")


func assert_building_contract(world, alias: String, source_id: int, health: float, creation_time: int, idle_graphic: int, construction_graphic: int, death_graphic: int, expected_cost: Dictionary) -> void:
	var source: Dictionary = world.object_record_by_id(source_id, 1)
	assert_equal(source.get("unit_id"), source_id, "%s source identity" % alias)
	assert_equal(source.get("health"), health, "%s source health" % alias)
	assert_equal(source.get("production", {}).get("creation_time"), creation_time, "%s source construction time" % alias)
	assert_equal(source.get("graphics", {}).get("idle"), idle_graphic, "%s source idle graphic" % alias)
	assert_equal(source.get("graphics", {}).get("construction"), construction_graphic, "%s source construction graphic" % alias)
	assert_equal(source.get("graphics", {}).get("death"), death_graphic, "%s source death graphic" % alias)
	assert_equal(world.building_cost(alias, 1), expected_cost, "%s Roman discounted source cost" % alias)


func canonical_source_id(snapshot: Dictionary, entity_id: int) -> int:
	for building_value in snapshot.get("world", {}).get("buildings", []):
		var building: Dictionary = building_value
		if int(building.get("id", -1)) == entity_id:
			return int(building.get("source_unit_id", -1))
	return -1


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(48, 48))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_team_civilization(1, 13)
	world.set_team_civilization(2, 13)
	return world


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
