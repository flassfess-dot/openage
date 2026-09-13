extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var definition := MatchDefinition.load_json()
	var map_data := RandomMapGenerator.generate(definition)
	var world = SimulationWorld.new(map_data["size"])
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var result := MatchBootstrap.apply(world, definition, map_data)

	assert_equal(world.get_units().size(), 11, "bootstrap creates all declared starting units")
	assert_equal(world.get_buildings().size(), 1, "legacy hidden Town Center is replaced by declared building")
	assert_equal(world.get_resources().size(), 23, "land and naval procedural resource clusters enter simulation")
	assert_true(not world.is_bulk_loading(), "bootstrap closes its bulk-load transaction")
	assert_equal(world.get_resources().filter(func(resource): return String(resource.get("kind", "")) in ["deep_fish", "shore_fish", "whale"]).size(), 5, "bootstrap preserves all seeded fish and Whale resources")
	assert_equal(result["selected_ids"].size(), 7, "initial selection is presentation bootstrap data")
	assert_equal(world.get_resource_amount(1, 0), 200, "starting food comes from player definition")
	assert_equal(world.get_resource_amount(1, 1), 200, "starting wood comes from player definition")
	assert_equal(world.get_population_cap(1), 8, "starting housing comes from player definition")
	assert_equal(world.navigation_grid.terrain(Vector2i(0, 0)), "water", "generated terrain configures navigation domain")
	assert_equal(world.navigation_grid.terrain(Vector2i(2, 1)), "shore", "generated shore configures navigation domain")
	assert_equal(world.terrain_elevation.vertex_elevation(Vector2i(18, 7)), 2, "generated height field configures simulation elevation")
	assert_equal(world.victory_system.rules[0]["type"], "conquest", "match victory rules configure authoritative system")
	assert_true(bool(result.get("naval_start_guarantees_met", false)), "every player receives a source-valid Dock footprint on generated coast (zones=%s)" % str(result.get("naval_start_zones", [])))
	for zone_value in result.get("naval_start_zones", []):
		var dock_position := Vector2(zone_value.get("dock_position", Vector2.ZERO))
		assert_true(world.map_supports_foundation("dock", dock_position), "published Dock anchor passes authoritative terrain and domain policy (zone=%s, audit=%s)" % [str(zone_value), str(world.foundation_map_audit("dock", dock_position))])

	var entity_ids: Dictionary = {}
	for collection in [world.get_units(), world.get_buildings(), world.get_resources()]:
		for entity in collection:
			entity_ids[int(entity["id"])] = true
	var entity_count := world.get_units().size() + world.get_buildings().size() + world.get_resources().size()
	assert_equal(entity_ids.size(), entity_count, "all bootstrapped entities receive unique IDs")

	var second := MatchBootstrap.apply(world, definition, map_data)
	assert_equal(second["selected_ids"], result["selected_ids"], "restart reproduces entity identity and initial selection")
	assert_equal(world.get_units().size(), 11, "restart does not accumulate entities")
	assert_true(not world.is_bulk_loading(), "restart also closes its bulk-load transaction")

	if failures.is_empty():
		print("I11-003 match bootstrap integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
