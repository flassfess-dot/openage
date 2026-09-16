extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_source_and_placement_contract(catalog)
	verify_fishing_boat_economy(catalog)
	verify_shore_fisherman_economy(catalog)
	if failures.is_empty():
		print("I12-019 naval economy vertical pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_source_and_placement_contract(catalog) -> void:
	var world = configured_world(catalog)
	var dock_definition: Dictionary = catalog.runtime_catalog_data.get("archetypes", {}).get("dock", {})
	var fishing_definition: Dictionary = catalog.runtime_catalog_data.get("archetypes", {}).get("fishing_boat", {})
	var whale_definition: Dictionary = catalog.runtime_catalog_data.get("archetypes", {}).get("whale", {})
	assert_equal(dock_definition.get("identifiers", {}).get("source_unit_id"), 45, "Dock identity uses source object 45")
	assert_equal(dock_definition.get("runtime", {}).get("placement", {}).get("terrain_restriction_id"), 6, "Dock uses original terrain restriction 6")
	assert_equal(fishing_definition.get("identifiers", {}).get("source_unit_id"), 13, "Fishing Boat identity uses source object 13")
	assert_equal(whale_definition.get("identifiers", {}).get("source_unit_id"), 370, "Whale identity uses source object 370")
	var whale: Dictionary = world.add_resource("whale", Vector2(3.5, 18.5), 250)
	assert_equal(whale.get("source_unit_id"), 370, "Whale reaches the common resource simulation with source identity")
	assert_equal(whale.get("placement_domain"), "water", "Whale is constrained to water navigation cells")
	assert_equal(catalog.resource_frame_info(whale, 1.0).get("asset_name"), "whale", "Whale resolves original animated presentation")
	assert_equal(world.building_cost("dock", 1), {1: 85}, "Roman Dock applies the original 15 percent building discount")
	assert_true(world.get_researched_technologies(1).has(90), "Stone Age initialization resolves original Dock connector 90")
	assert_true(world.is_object_available(1, 45), "Dock is source-enabled after its automatic connector")

	var worker: Dictionary = world.add_unit(1, "villager", Vector2(9.5, 12.5), false)
	world.set_resource_amount(1, 1, 1000)
	assert_true(world.can_place_foundation(1, "dock", Vector2(5.5, 12.5)), "Dock footprint may span water and beach with land and water access (reason=%s)" % world.last_build_failure)
	assert_true(not world.can_place_foundation(1, "dock", Vector2(11.5, 12.5)), "Dock is rejected on ordinary land")
	assert_true(not world.can_place_foundation(1, "dock", Vector2(2.5, 12.5)), "Dock is rejected in open water without land access")
	var build_sites: Dictionary = world.get_mixed_domain_build_sites(1)
	assert_true(not build_sites.get("dock", []).is_empty(), "authoritative AI knowledge exposes at least one explored legal Dock site")
	for site_value in build_sites.get("dock", []):
		assert_true(world.can_place_foundation(1, "dock", Vector2(site_value)), "every published Dock candidate passes the same authoritative placement policy")
	var dock: Variant = world.place_foundation(1, "dock", Vector2(5.5, 12.5), [worker])
	assert_true(dock != null, "normal foundation pipeline creates a shoreline Dock")
	if dock == null:
		return
	assert_equal(dock.get("state"), "foundation", "Dock begins as an ordinary foundation")
	assert_equal(dock.get("construction_required"), 50.0, "Dock preserves original construction time")
	assert_equal(catalog.building_frame_info(dock).get("graphic_id"), 85, "Dock foundation uses original construction graphic")
	assert_true(catalog.building_frame_info(dock).get("texture") != null, "Dock construction graphic is loadable")


func verify_fishing_boat_economy(catalog) -> void:
	var world = configured_world(catalog)
	world.set_population_cap(1, 50)
	world.set_population_housing(1, 50)
	for resource_type in range(4):
		world.set_resource_amount(1, resource_type, 10000)
	var dock: Dictionary = world.add_building(1200, "dock", Vector2(5.5, 12.5), 1)
	var options: Array = world.get_unit_production_options(int(dock["id"]), 1)
	var fishing_options: Array = options.filter(func(option): return String(option.get("kind", "")) == "fishing_boat")
	assert_equal(fishing_options.size(), 1, "Dock exposes Fishing Boat through the common production palette")
	if not fishing_options.is_empty():
		assert_equal(fishing_options[0].get("source_unit_id"), 13, "Stone Age production resolves Fishing Boat source 13")
		assert_equal(fishing_options[0].get("icon_id"), 18, "Fishing Boat uses original icon 18")
		assert_equal(fishing_options[0].get("button_id"), 1, "Fishing Boat uses original button 1")
	var wood_before: int = world.get_resource_amount(1, 1)
	var order: Variant = world.enqueue_unit_production(int(dock["id"]), 1, "fishing_boat")
	assert_true(order != null, "Fishing Boat enters normal Dock production")
	assert_equal(world.get_resource_amount(1, 1), wood_before - 50, "Fishing Boat reserves original 50 wood cost")
	world.update_production(40.0)
	var boats: Array = world.get_units().filter(func(unit): return String(unit.get("kind", "")) == "fishing_boat")
	assert_equal(boats.size(), 1, "Fishing Boat completes after original 40 seconds (queue=%s)" % str(dock.get("production_queue", [])))
	if boats.is_empty():
		return
	var boat: Dictionary = boats[0]
	assert_equal(boat.get("movement_domain"), "water", "Fishing Boat uses water navigation")
	assert_true(world.navigation_grid.surface_accessible(Vector2i(floori(boat["pos"].x), floori(boat["pos"].y)), "water"), "Dock spawns Fishing Boat on navigable water")
	assert_true(world.entity_is_worker(boat), "Fishing Boat participates in the common worker pipeline")
	assert_equal(catalog.unit_frame_info(boat, "idle").get("asset_name"), "fishing_boat_idle", "Fishing Boat resolves original idle art")
	assert_true(catalog.unit_frame_info(boat, "work").get("texture") != null, "Fishing Boat work art is loadable")

	var fish: Dictionary = world.add_resource("deep_fish", Vector2(11.5, 12.5), 3)
	assert_equal(fish.get("placement_domain"), "water", "deep fish is placed in the water domain")
	assert_equal(catalog.resource_frame_info(fish).get("asset_name"), "deep_fish", "deep fish resolves original resource art")
	var food_before: int = world.get_resource_amount(1, 0)
	world.assign_command_gather([boat], int(fish["id"]))
	assert_equal(boat.get("task"), "gather", "Fishing Boat accepts normal Gather order")
	advance_until(world, func(): return int(world.get_resource_amount(1, 0)) > food_before, 1600)
	assert_equal(world.get_resource_amount(1, 0), food_before + 3, "Fishing Boat gathers and deposits the exact fish pool at Dock")
	assert_true(int(boat.get("deposit_cycles", 0)) > 0, "Fishing Boat completes a common delivery cycle")

	world.grant_technology(1, 102)
	assert_equal(dock.get("source_unit_id"), 133, "Bronze Age upgrades existing Dock to source 133")
	assert_equal(catalog.building_frame_info(dock).get("graphic_id"), 859, "upgraded Dock resolves original Roman graphic root")
	assert_true(catalog.building_frame_info(dock).get("texture") != null, "upgraded Dock base graphic is loadable")
	var research: Variant = world.enqueue_research(int(dock["id"]), 1, 4)
	assert_true(research != null, "Fishing Ship upgrade enters normal Dock research")
	if research != null:
		world.update_production(30.0)
	assert_equal(boat.get("source_unit_id"), 14, "existing Fishing Boat upgrades to Fishing Ship source 14")
	assert_equal(boat.get("max_hp"), 75.0, "Fishing Ship receives original 75 hit points")
	assert_equal(catalog.unit_frame_info(boat, "idle").get("asset_name"), "fishing_ship_idle", "Fishing Ship resolves upgraded original art")
	assert_true(world.dropoff_accepts_resource(dock, 0, {45: true}), "upgraded Dock lineage remains a valid fishing drop site")


func verify_shore_fisherman_economy(catalog) -> void:
	var world = configured_world(catalog)
	world.add_building(1300, "town_center", Vector2(13.5, 12.5), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(9.5, 12.5), false)
	var shore_fish: Dictionary = world.add_resource("shore_fish", Vector2(6.5, 12.5), 2)
	var deep_fish: Dictionary = world.add_resource("deep_fish", Vector2(3.5, 18.5), 2)
	world.assign_command_gather([worker], int(deep_fish["id"]))
	assert_equal(worker.get("task"), "idle", "land worker cannot gather deep-water fish")
	assert_equal(worker.get("components", {}).get("order", {}).get("completion_reason"), "incompatible_gatherer", "incompatible resource domain is explicit")
	var controller = GameController.new(world)
	var incompatible_command = Commands.GatherCommand.new(0, [int(worker["id"])], int(deep_fish["id"]))
	controller.enqueue_command(incompatible_command, true, 1)
	controller.process_commands()
	assert_equal(controller.get_command_result(incompatible_command.sequence_id).get("reason"), "incompatible_gatherer", "public gather command rejects an incompatible domain instead of accepting a no-op")
	var food_before: int = world.get_resource_amount(1, 0)
	world.assign_command_gather([worker], int(shore_fish["id"]))
	assert_equal(worker.get("worker_role_source_unit_id"), 119, "shore fish activates original Fisherman task form 119")
	assert_equal(catalog.unit_frame_info(worker, "fisherman_work").get("asset_name"), "fisherman_work", "Fisherman resolves original work art")
	advance_until(world, func(): return int(world.get_resource_amount(1, 0)) > food_before, 1600)
	assert_equal(world.get_resource_amount(1, 0), food_before + 2, "Fisherman gathers and returns the exact shore fish pool (task=%s stage=%s pos=%s destination=%s path=%s reason=%s fish=%s carried=%s)" % [worker.get("task"), worker.get("gather_stage"), worker.get("pos"), worker.get("destination"), worker.get("path_status"), worker.get("diagnostic_reason"), shore_fish.get("amount"), worker.get("carried_amount")])


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
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(24.5, 24.5), false)
	enemy["stance"] = "passive"
	return world


func advance_until(world, condition: Callable, maximum_ticks: int) -> void:
	for unused in range(maximum_ticks):
		world.advance(0.05, 1, 2)
		if condition.call():
			return


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
