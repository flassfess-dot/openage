extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load_generated_data()
	test_data_driven_production_locations(catalog)
	test_age_filtered_build_palette(catalog)
	test_foundation_completion_unlocks_unit(catalog)
	test_unknown_runtime_type_is_rejected(catalog)
	test_local_ai_build_sites(catalog)
	test_local_build_site_cache_is_bounded(catalog)
	if failures.is_empty():
		print("I8-002 production availability tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_data_driven_production_locations(catalog) -> void:
	var world = configured_world(catalog)
	var town_center: Dictionary = world.add_building(700, "town_center", Vector2(12.0, 12.0), 1)
	var barracks: Dictionary = world.add_building(701, "barracks", Vector2(6.0, 12.0), 1)
	assert_true(world.is_object_available(1, 73), "Barracks completion applies hidden source technology 62")
	assert_equal(world.enqueue_unit_production(int(town_center["id"]), 1, "clubman"), null, "Town Center cannot train Clubman")
	assert_equal(world.last_production_failure, "wrong_production_location", "wrong producer rejection is explicit")
	var clubman_order: Variant = world.enqueue_unit_production(int(barracks["id"]), 1, "clubman")
	assert_true(clubman_order != null, "Barracks accepts Clubman after its completion unlock")
	assert_equal(int(world.production_building_for(1, "clubman")["id"]), int(barracks["id"]), "automatic producer lookup uses source train location")

	var archery_range: Dictionary = world.add_building(702, "archery_range", Vector2(18.0, 12.0), 1)
	assert_true(world.is_object_available(1, 4), "Archery Range completion applies hidden source technology 55")
	assert_true(world.enqueue_unit_production(int(archery_range["id"]), 1, "archer") != null, "Archery Range accepts Bowman")


func test_age_filtered_build_palette(catalog) -> void:
	var world = configured_world(catalog)
	var options: Array = world.get_build_options(1)
	var house: Dictionary = option_for(options, "house")
	assert_true(not house.is_empty(), "Stone Age build palette exposes House")
	assert_equal(house.get("source_unit_id"), 70, "House palette entry preserves source object ID")
	assert_equal(house.get("icon_id"), 15, "House palette entry preserves original DAT icon ID")
	assert_equal(house.get("button_id"), 1, "House palette entry preserves original button slot")
	assert_true(bool(house.get("accepted", false)), "affordable House command is enabled")
	assert_true(option_for(options, "government_center").is_empty(), "Bronze Age Government Center is hidden in Stone Age")
	assert_true(option_for(options, "wall").is_empty(), "Tool Age Wall is hidden before its connector technology")
	for index in range(1, options.size()):
		assert_true(int(options[index - 1].get("button_id", 0)) <= int(options[index].get("button_id", 0)), "build palette follows original button ordering")


func test_foundation_completion_unlocks_unit(catalog) -> void:
	var world = configured_world(catalog)
	var foundation: Dictionary = world.add_building(710, "barracks", Vector2(8.0, 8.0), 1, false)
	assert_true(not world.is_object_available(1, 73), "foundation does not unlock production")
	world.complete_foundation(foundation)
	assert_true(world.is_object_available(1, 73), "completed foundation unlocks production")


func test_unknown_runtime_type_is_rejected(catalog) -> void:
	var world = configured_world(catalog)
	world.update_fog_of_war()
	assert_equal(world.place_foundation(1, "not_in_catalog", Vector2(4.0, 4.0)), null, "unknown building is not instantiated")
	assert_equal(world.last_build_failure, "unknown_building_type", "unknown building rejection is explicit")


func test_local_ai_build_sites(catalog) -> void:
	var world = configured_world(catalog)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(12.5, 12.5), false)
	world.update_fog_of_war()
	assert_true(not world.can_place_foundation(1, "house", Vector2(worker["pos"])), "a foundation cannot trap a living unit inside its occupied cells")
	assert_equal(world.last_build_failure, "occupied_by_unit", "unit overlap has a stable placement rejection")
	worker["pos"] = Vector2(14.1, 12.5)
	assert_true(not world.can_place_foundation(1, "house", Vector2(12.5, 12.5)), "foundation placement accounts for the mobile radius outside the occupied center cells")
	assert_equal(world.last_build_failure, "occupied_by_unit", "mobile-radius overlap uses the same stable rejection")
	worker["pos"] = Vector2(16.0, 12.5)
	var sites: Array = world.get_local_build_sites(1, ["house"], 2).get("house", [])
	assert_equal(sites.size(), 2, "local AI placement returns the requested bounded number of House sites")
	for site_value in sites:
		assert_true(world.can_place_foundation(1, "house", Vector2(site_value)), "every exposed local AI site passes the authoritative placement rules")
	var existing: Dictionary = world.add_building(711, "house", Vector2(15.5, 15.5), 1)
	var spaced_sites: Array = world.get_local_build_sites(1, ["house"], 2, 12, {}, [], 2.0).get("house", [])
	assert_equal(spaced_sites.size(), 2, "bounded site search continues until it finds enough candidates that preserve the requested structure gap")
	var option: Dictionary = option_for(world.get_build_options(1), "house")
	var clearance := float(existing.get("footprint_radius", 1.0)) + float(option.get("footprint_radius", 1.0)) + 2.0
	for site_value in spaced_sites:
		assert_true(Vector2(site_value).distance_to(Vector2(existing.get("pos", Vector2.ZERO))) >= clearance, "site query applies the structure gap before consuming its candidate budget")


func test_local_build_site_cache_is_bounded(catalog) -> void:
	var world = configured_world(catalog)
	world.add_unit(1, "villager", Vector2(12.0, 12.0), false)
	world.update_fog_of_war()
	for index in range(80):
		world.local_build_site_cache[index] = {"tick": 99, "sites": {"house": []}}
	world.local_build_site_cache[10001] = {"tick": 0, "sites": {"house": []}}
	var sites: Dictionary = world.get_cached_local_build_sites(1, ["house"], 100, 10, 1)
	assert_true(not sites.get("house", []).is_empty(), "cache eviction preserves a fresh authoritative site query")
	assert_true(world.local_build_site_cache.size() <= world.MAX_LOCAL_BUILD_SITE_CACHE_ENTRIES, "build-site cache has a fixed entry bound")
	assert_true(not world.local_build_site_cache.has(10001), "expired build-site cache entry is evicted")


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_resource_amount(1, 0, 1000)
	world.set_resource_amount(1, 1, 1000)
	return world


func option_for(options: Array, kind: String) -> Dictionary:
	for option_value in options:
		var option: Dictionary = option_value
		if String(option.get("kind", "")) == kind:
			return option
	return {}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
