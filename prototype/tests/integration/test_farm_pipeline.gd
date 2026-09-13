extends SceneTree

const AiEconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const ContextResolver := preload("res://scripts/context_resolver.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_market_unlock_and_source_contract(catalog)
	verify_farm_build_gather_reseed(catalog)
	verify_ownership_and_loss(catalog)
	if failures.is_empty():
		print("I12-014 Farm and Market vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_market_unlock_and_source_contract(catalog) -> void:
	var world = configured_world(catalog)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)

	var farm_definition: Dictionary = catalog.runtime_catalog_data.get("archetypes", {}).get("farm", {})
	var farm_runtime: Dictionary = farm_definition.get("runtime", {})
	assert_equal(farm_definition.get("identifiers", {}).get("source_unit_id"), 50, "Farm runtime identity uses source object 50")
	assert_equal(farm_runtime.get("required_technology_id"), 26, "Farm is gated by original Market completion connector")
	assert_equal(farm_runtime.get("resource_amount_id"), 36, "Farm capacity uses original civilization resource 36")
	assert_equal(farm_runtime.get("max_gatherers"), 1, "Farm declares one working position")
	assert_equal(world.building_cost("farm", 1), {1: 64}, "Roman Farm applies original 15 percent building discount to 75 wood")
	var farm_source: Dictionary = world.object_record_by_id(50, 1)
	assert_equal(farm_source.get("health"), 50.0, "Farm uses original 50 hit points")
	assert_equal(farm_source.get("production", {}).get("creation_time"), 30, "Farm uses original 30 second construction time")
	assert_equal(farm_source.get("graphics", {}).get("idle"), 273, "Farm uses original base graphic")
	assert_equal(farm_source.get("links", {}).get("dead_unit_id"), 244, "Farm retains original depleted object relationship")

	assert_true(not world.is_object_available(1, 84), "Market starts behind Tool Age and Granary connector")
	assert_true(not world.is_object_available(1, 50), "Farm starts behind Market completion")
	world.add_building(940, "granary", Vector2(6.0, 6.0), 1)
	world.grant_technology(1, 101)
	assert_true(world.get_researched_technologies(1).has(94), "Tool Age and Granary resolve Market connector 94")
	assert_true(world.is_object_available(1, 84), "Market becomes available through source enable effect")
	assert_equal(world.building_cost("market", 1), {1: 128}, "Roman Market applies original discount to 150 wood")

	var market: Dictionary = world.add_building(941, "market", Vector2(12.0, 6.0), 1)
	assert_equal(market.get("source_unit_id"), 84, "Market keeps source identity")
	assert_equal(market.get("max_hp"), 350.0, "Market uses original health")
	assert_equal(market.get("construction_required"), 40.0, "Market uses original construction time")
	var market_frame: Dictionary = catalog.building_frame_info(market)
	assert_equal(market_frame.get("graphic_id"), 475, "Market resolves original Roman graphic")
	assert_equal(market_frame.get("asset_name"), "graphic_475_p1", "Market resolves player-one palette")
	assert_true(market_frame.get("texture") != null, "Market graphic is loadable")
	assert_true(market_frame.get("composite_parts", []).any(func(part): return int(part.get("graphic_id", -1)) == 476), "Market imports its valid composite layer")
	assert_true(world.get_researched_technologies(1).has(26), "completed Market applies original Farm connector 26")
	assert_true(world.is_object_available(1, 50), "Farm becomes available after Market completion")
	var research_ids: Array = world.get_research_options(int(market["id"]), 1).map(func(option): return int(option.get("technology_id", -1)))
	assert_true(research_ids.has(81), "Market exposes Domestication through the normal research palette")

	var enemy_market: Dictionary = world.add_building(942, "market", Vector2(24.0, 6.0), 2)
	assert_equal(catalog.building_frame_info(enemy_market).get("asset_name"), "graphic_475_p2", "Market resolves player-two palette")
	world.grant_technology(2, 102)
	assert_equal(enemy_market.get("source_unit_id"), 116, "Bronze Age upgrades existing Market to Roman source variant 116")
	assert_equal(catalog.building_frame_info(enemy_market).get("asset_name"), "graphic_871_p2", "upgraded Market resolves player-two Roman palette")


func verify_farm_build_gather_reseed(catalog) -> void:
	var world = configured_world(catalog)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)
	world.add_building(950, "town_center", Vector2(5.0, 20.0), 1)
	world.add_building(951, "granary", Vector2(5.0, 10.0), 1)
	var distant_enemy: Dictionary = world.add_unit(2, "clubman", Vector2(33.0, 33.0), false)
	distant_enemy["stance"] = "passive"
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(13.0, 16.0), false)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	var farm_position := Vector2(17.0, 16.0)

	var locked_command = Commands.BuildCommand.new(0, [int(worker["id"])], "farm", farm_position)
	controller.enqueue_command(locked_command, true, 1)
	controller.process_commands()
	assert_equal(controller.get_command_result(locked_command.sequence_id).get("reason"), "building_unavailable", "normal build command rejects Farm before Market")

	world.grant_technology(1, 101)
	var market: Dictionary = world.add_building(952, "market", Vector2(5.0, 5.0), 1)
	assert_true(world.is_object_available(1, 50), "Market completion unlocks Farm in playable world")
	var wood_before: int = world.get_resource_amount(1, 1)
	var build_command = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "farm", farm_position)
	controller.enqueue_command(build_command, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(build_command.sequence_id).get("accepted", false)), "normal build command places Farm")
	var farms: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "farm")
	assert_equal(farms.size(), 1, "one Farm foundation is created")
	if farms.is_empty():
		return
	var farm: Dictionary = farms[0]
	var farm_id := int(farm["id"])
	assert_equal(world.get_resource_amount(1, 1), wood_before - 64, "Farm reserves discounted Roman wood cost")
	assert_equal(farm.get("state"), "foundation", "Farm begins as ordinary foundation")
	assert_equal(farm.get("resource_state"), "planting", "foundation has explicit planting state")
	assert_equal(farm.get("amount"), 0, "foundation exposes no food")
	assert_equal(catalog.building_frame_info(farm).get("graphic_id"), 82, "Farm construction uses original shared construction graphic")

	advance_until(controller, func(): return String(farm.get("state", "")) == "complete", 900)
	assert_equal(farm.get("state"), "complete", "Farm completes through ordinary worker construction (progress=%.3f worker_task=%s pos=%s slot=%s destination=%s path_status=%s reason=%s)" % [float(farm.get("construction_progress", 0.0)), String(worker.get("task", "")), str(worker.get("pos", Vector2.ZERO)), str(worker.get("building_approach_slot", null)), str(worker.get("destination", null)), String(worker.get("path_status", "")), String(worker.get("diagnostic_reason", ""))])
	if String(farm.get("state", "")) != "complete":
		return
	assert_equal(farm.get("amount"), 250, "completed Roman Farm receives original 250 food pool")
	assert_equal(farm.get("max_amount"), 250, "Farm stores authoritative maximum food")
	assert_equal(farm.get("resource_state"), "available", "completed Farm becomes gatherable")
	assert_true(world.find_resource(farm_id) == farm, "Farm participates in common resource lookup without leaving building collection")
	assert_true(world.navigation_grid.is_walkable(Vector2i(floori(farm_position.x), floori(farm_position.y))), "completed Farm interior remains walkable for Farmer")
	assert_equal(worker.get("task"), "gather", "builder automatically continues as Farmer after completion")
	assert_equal(worker.get("worker_role_source_unit_id"), 259, "gathering Farm applies original Farmer task identity")
	assert_float(float(worker.get("components", {}).get("worker", {}).get("work_rate", 0.0)), 0.44999998807907104, "Farmer uses original work rate")
	assert_float(float(worker.get("carry_capacity", 0.0)), 10.0, "Farmer uses original carrying capacity")
	var drop_site_ids: Array = worker.get("components", {}).get("worker", {}).get("drop_site_ids", []).map(func(value): return int(value))
	assert_equal(drop_site_ids, [109, 68], "Farmer uses Town Center and Granary drop sites")
	var farm_frame: Dictionary = catalog.building_frame_info(farm)
	assert_equal(farm_frame.get("graphic_id"), 273, "Farm resolves original completed graphic")
	assert_equal(farm_frame.get("asset_name"), "graphic_273_p1", "Farm resolves owner palette")
	assert_true(farm_frame.get("texture") != null, "Farm completed graphic is loadable")
	assert_true(farm_frame.get("composite_parts", []).any(func(part): return int(part.get("graphic_id", -1)) == 274), "Farm imports original composite crop layer")
	worker["anim_state"] = AnimationController.GATHER
	var farmer_state: String = catalog.unit_presentation_state(worker, "work_food")
	assert_equal(catalog.unit_frame_info(worker, farmer_state).get("asset_name"), "farmer_work", "Farmer uses original work animation")

	var food_before: int = world.get_resource_amount(1, 0)
	advance_until(controller, func(): return int(worker.get("deposit_cycles", 0)) > 0, 1800)
	assert_true(int(worker.get("deposit_cycles", 0)) > 0, "Farmer completes a gather-carry-drop-resume cycle")
	assert_true(world.get_resource_amount(1, 0) > food_before, "Farm food reaches authoritative player stockpile")
	assert_equal(worker.get("task"), "gather", "Farmer resumes work after depositing food")

	var previous_amount := int(farm.get("amount", 0))
	var previous_maximum := int(farm.get("max_amount", 0))
	var research: Variant = world.enqueue_research(int(market["id"]), 1, 81)
	assert_true(research != null, "Domestication enters normal Market research queue")
	if research != null:
		world.update_production(40.0)
	assert_true(world.get_researched_technologies(1).has(81), "Domestication completes after original research time")
	assert_equal(farm.get("amount"), previous_amount + 75, "Domestication adds 75 food to existing Farm")
	assert_equal(farm.get("max_amount"), previous_maximum + 75, "Domestication increases existing Farm capacity")
	world.grant_technology(1, 102)
	assert_equal(market.get("source_unit_id"), 116, "Bronze Age upgrades existing Market to Roman source variant 116")
	assert_equal(catalog.building_frame_info(market).get("asset_name"), "graphic_871_p1", "upgraded Market resolves player-one Roman palette")
	previous_amount = int(farm.get("amount", 0))
	previous_maximum = int(farm.get("max_amount", 0))
	var plow: Variant = world.enqueue_research(int(market["id"]), 1, 31)
	assert_true(plow != null, "Plow enters normal upgraded Market research queue")
	if plow != null:
		world.update_production(75.0)
	assert_equal(farm.get("amount"), previous_amount + 75, "Plow adds 75 food to existing Farm")
	assert_equal(farm.get("max_amount"), previous_maximum + 75, "Plow increases existing Farm capacity")
	world.grant_technology(1, 103)
	previous_amount = int(farm.get("amount", 0))
	previous_maximum = int(farm.get("max_amount", 0))
	var irrigation: Variant = world.enqueue_research(int(market["id"]), 1, 80)
	assert_true(irrigation == null, "Roman technology tree keeps Irrigation unavailable")
	assert_equal(world.last_research_failure, "technology_disabled", "Irrigation rejection comes from source civilization rules")
	assert_equal(farm.get("amount"), previous_amount, "disabled Irrigation cannot change existing Farm")
	assert_equal(farm.get("max_amount"), previous_maximum, "disabled Irrigation cannot change Farm capacity")

	var second_farm: Dictionary = world.add_building(953, "farm", Vector2(25.0, 16.0), 1)
	assert_equal(second_farm.get("amount"), 400, "future Roman Farm inherits every available yield technology")
	assert_equal(catalog.building_frame_info({"kind": "farm", "source_unit_id": 50, "team": 2, "state": "complete", "amount": 400, "harvestable": true, "components": {"ownership": {"civilization_id": 13}}}).get("asset_name"), "graphic_273_p2", "Farm resolves player-two palette")
	var second_worker: Dictionary = world.add_unit(1, "villager", Vector2(23.0, 16.0), false)
	world.assign_command_gather([second_worker], int(second_farm["id"]))
	assert_equal(second_worker.get("task"), "gather", "second worker can work a separate Farm")
	var extra_worker: Dictionary = world.add_unit(1, "villager", Vector2(18.0, 16.0), false)
	world.assign_command_gather([extra_worker], farm_id)
	assert_equal(extra_worker.get("task"), "idle", "second worker cannot occupy the same Farm working position")

	var canonical: Dictionary = SimulationSnapshot.canonical(world, controller.tick_index, controller)
	var canonical_farms: Array = canonical.get("world", {}).get("buildings", []).filter(func(building): return int(building.get("id", -1)) == farm_id)
	assert_equal(canonical_farms.size(), 1, "canonical state serializes Farm as building")
	assert_true(canonical.get("world", {}).get("resources", []).all(func(resource): return int(resource.get("id", -1)) != farm_id), "canonical state does not duplicate Farm as loose resource")
	if not canonical_farms.is_empty():
		assert_equal(canonical_farms[0].get("amount"), farm.get("amount"), "canonical state retains current Farm food")
		assert_equal(canonical_farms[0].get("resource_state"), farm.get("resource_state"), "canonical state retains Farm lifecycle state")
	var presentation: Dictionary = SimulationSnapshot.presentation(world, controller.tick_index, 1)
	var ai_commands: Array = AiEconomicPlanner.plan(presentation, controller.tick_index + 1, 1)
	assert_true(ai_commands.any(func(command): return command.command_type() == "gather" and int(command.resource_id) in [farm_id, int(second_farm["id"])]), "AI legally discovers owned visible Farm through presentation snapshot")

	world.finish_gather_order(worker, "test_depletion")
	farm["amount"] = 1
	world.update_resource_state(farm)
	world.assign_command_gather([worker], farm_id)
	assert_float(world.gather(farm_id, worker), 1.0, "Farmer removes final food through common gather path")
	assert_equal(farm.get("state"), "complete", "depleted Farm remains a building")
	assert_equal(farm.get("resource_state"), "depleted", "Farm enters explicit depleted state")
	assert_equal(catalog.building_frame_info(farm).get("graphic_id"), 148, "depleted Farm resolves original exhausted-field graphic")
	assert_equal(ContextResolver.resolve([worker], farm, farm_position, 1).get("type"), "build", "right click on depleted Farm resolves normal build command for reseed")
	world.finish_gather_order(worker, "test_reseed")
	worker["carried_amount"] = 0.0
	worker["carried_resource_type_id"] = -1

	var reseed_wood_before: int = world.get_resource_amount(1, 1)
	var reseed_command = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "farm", farm_position)
	controller.enqueue_command(reseed_command, true, 1)
	controller.process_commands()
	assert_true(bool(controller.get_command_result(reseed_command.sequence_id).get("accepted", false)), "normal build command reseeds depleted Farm")
	assert_equal(int(farm["id"]), farm_id, "reseed preserves Farm entity identity")
	assert_equal(farm.get("state"), "foundation", "reseed reuses ordinary construction lifecycle")
	assert_equal(farm.get("resource_state"), "planting", "reseed returns Farm to planting state")
	assert_equal(world.get_resource_amount(1, 1), reseed_wood_before - 64, "reseed pays ordinary Farm cost")
	assert_true(world.cancel_foundation(farm_id), "Farm reseed can be cancelled through normal foundation cancellation")
	assert_equal(farm.get("state"), "complete", "cancelled reseed restores depleted Farm")
	assert_equal(farm.get("resource_state"), "depleted", "cancelled reseed does not create food")
	assert_equal(world.get_resource_amount(1, 1), reseed_wood_before, "cancelled reseed refunds reserved cost")

	var final_reseed = Commands.BuildCommand.new(controller.tick_index, [int(worker["id"])], "farm", farm_position)
	controller.enqueue_command(final_reseed, true, 1)
	controller.process_commands()
	advance_until(controller, func(): return String(farm.get("state", "")) == "complete", 900)
	assert_equal(farm.get("amount"), 400, "completed reseed restores current technology-adjusted capacity")
	assert_equal(farm.get("resource_state"), "available", "completed reseed returns Farm to available state")

	world.begin_building_destruction(second_farm)
	assert_equal(second_farm.get("state"), "destroyed", "destroyed Farm enters building destruction lifecycle")
	assert_equal(second_worker.get("task"), "idle", "Farm destruction releases its Farmer")
	assert_true(world.find_resource(int(second_farm["id"])) == null, "destroyed Farm leaves resource lookup immediately")


func verify_ownership_and_loss(catalog) -> void:
	var world = configured_world(catalog)
	world.grant_technology(1, 26)
	world.grant_technology(2, 26)
	var farm: Dictionary = world.add_building(970, "farm", Vector2(16.0, 16.0), 1)
	var owner_worker: Dictionary = world.add_unit(1, "villager", Vector2(14.0, 16.0), false)
	var enemy_worker: Dictionary = world.add_unit(2, "villager", Vector2(20.0, 16.0), false)
	world.assign_command_gather([owner_worker], int(farm["id"]))
	assert_equal(owner_worker.get("task"), "gather", "owner can gather own Farm")

	var controller = GameController.new(world)
	var enemy_command = Commands.GatherCommand.new(0, [int(enemy_worker["id"])], int(farm["id"]))
	controller.enqueue_command(enemy_command, true, 2)
	controller.process_commands()
	assert_equal(controller.get_command_result(enemy_command.sequence_id).get("reason"), "resource_not_owned", "enemy gather command is rejected authoritatively")

	assert_true(world.transfer_entity_ownership(farm, 2), "Farm supports common ownership transfer")
	assert_equal(farm.get("team"), 2, "Farm owner is authoritative and serialized")
	assert_equal(owner_worker.get("task"), "idle", "ownership transfer releases previous owner's Farmer")
	world.assign_command_gather([enemy_worker], int(farm["id"]))
	assert_equal(enemy_worker.get("task"), "gather", "new owner can gather captured Farm")
	world.begin_building_destruction(farm)
	assert_equal(enemy_worker.get("task"), "idle", "new owner's Farmer is released when Farm is lost")


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(36, 36))
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
