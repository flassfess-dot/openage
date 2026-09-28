extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json()
	var first := RandomMapGenerator.generate(definition)
	var second := RandomMapGenerator.generate(definition)
	assert_equal(first, second, "same match seed generates byte-equivalent map data")
	assert_equal(first["terrain_ids"].size(), 24 * 24, "terrain covers every cell")
	assert_equal(first["vertex_levels"].size(), 25 * 25, "height field covers every vertex")
	assert_equal(first["terrain_ids"][0], 1, "declared coastal water reaches terrain grid")
	assert_equal(first["terrain_ids"][1 * 24 + 2], 2, "declared shore band reaches terrain grid")
	assert_equal(first["resources"].size(), 23, "fish clusters preserve their declared number of large selectable schools")
	var deep_fish: Array = first["resources"].filter(func(resource): return String(resource.get("kind", "")) == "deep_fish")
	var shore_fish: Array = first["resources"].filter(func(resource): return String(resource.get("kind", "")) == "shore_fish")
	var whales: Array = first["resources"].filter(func(resource): return String(resource.get("kind", "")) == "whale")
	assert_equal(deep_fish.size(), 2, "seeded map includes every declared large deep-fish school")
	assert_equal(shore_fish.size(), 2, "seeded map includes every declared large shore-fish school")
	assert_true(deep_fish.all(func(resource): return int(resource.get("amount", 0)) == 250), "each large deep-fish school keeps its declared food")
	assert_true(shore_fish.all(func(resource): return int(resource.get("amount", 0)) == 250), "each large shore-fish school keeps its declared food")
	assert_equal(int(deep_fish[0].get("source_unit_id", -1)), 53, "deep fish use the large-school source unit")
	assert_equal(int(deep_fish[0].get("source_graphic_id", -1)), 316, "deep fish use the large-school source graphic")
	assert_equal(int(shore_fish[0].get("source_unit_id", -1)), 263, "shore fish use the large-school source unit")
	assert_equal(int(shore_fish[0].get("source_graphic_id", -1)), 319, "shore fish use the large-school source graphic")
	assert_equal(whales.size(), 1, "seeded map includes source Whale 370")
	assert_true(deep_fish.all(func(resource):
		var pos := Vector2(resource["position"])
		return int(first["terrain_ids"][floori(pos.y) * 24 + floori(pos.x)]) in TerrainRules.WATER_TERRAIN_IDS
	), "deep fish remain in water cells")
	assert_true(whales.all(func(resource):
		var pos := Vector2(resource["position"])
		return int(first["terrain_ids"][floori(pos.y) * 24 + floori(pos.x)]) in TerrainRules.WATER_TERRAIN_IDS
	), "Whale remains in deep navigable water")
	assert_true(shore_fish.all(func(resource): return String(resource.get("placement_domain", "")) == "shore_water"), "shore fish retain shore-water placement intent")
	assert_true(first["vertex_levels"].max() == 2, "declared hill reaches maximum elevation")
	var naval_settings: Dictionary = definition.get("map", {}).get("generator", {}).get("naval_start", {})
	var reference_anchor := Vector2(1.5, 13.5)
	var reference_staging := RandomMapGenerator._nearest_staging_pair(reference_anchor, Vector2i(24, 24), first["terrain_ids"], int(naval_settings.get("dock_footprint_radius_cells", 1)))
	assert_true(RandomMapGenerator._dock_anchor_valid(reference_anchor, Vector2i(24, 24), first["terrain_ids"], int(naval_settings.get("dock_footprint_radius_cells", 1)), naval_settings.get("dock_surface_terrain_ids", []), {}), "reference coast accepts source Dock footprint (staging=%s)" % str(reference_staging))
	assert_equal(first.get("naval_start_zones", []).size(), 2, "generator publishes one deterministic coastal start zone per player")
	assert_true(not first.get("reserved_foundation_cells", []).is_empty(), "generator publishes authoritative resource exclusion cells for naval foundations")
	for zone_value in first.get("naval_start_zones", []):
		var zone: Dictionary = zone_value
		assert_true(zone.get("dock_position", null) is Vector2, "naval start zone contains a Dock anchor")
		assert_true(Vector2(zone.get("land_staging", Vector2.ZERO)).distance_to(Vector2(zone.get("water_staging", Vector2.ZERO))) <= 2.0, "naval start zone joins adjacent land and water staging cells outside the Dock footprint")
		var dock_cell := Vector2i(Vector2(zone.get("dock_position", Vector2.ZERO)))
		for resource_value in first.get("resources", []):
			var resource_cell := Vector2i(Vector2(resource_value.get("position", Vector2.ZERO)))
			assert_true(absi(resource_cell.x - dock_cell.x) > 1 or absi(resource_cell.y - dock_cell.y) > 1, "procedural resources never occupy a reserved Dock footprint")

	var changed_definition: Dictionary = definition.duplicate(true)
	changed_definition["map"]["seed"] = int(definition["map"]["seed"]) + 1
	var changed := RandomMapGenerator.generate(changed_definition)
	assert_true(changed["resources"] != first["resources"], "different seed changes procedural placements")
	assert_equal(changed["terrain_ids"], first["terrain_ids"], "seed does not alter fully declarative coast geometry")
	var coast: Array[int] = []
	coast.resize(12 * 12)
	coast.fill(0)
	coast[8 * 12 + 8] = 1
	for y in range(2, 7):
		for x in range(2, 7):
			coast[y * 12 + x] = 1
	coast[4 * 12 + 4] = 0
	RandomMapGenerator._smooth_water_mask(coast, Vector2i(12, 12))
	assert_equal(coast[8 * 12 + 8], 0, "isolated water spike is removed before drawing the coast")
	assert_equal(coast[4 * 12 + 4], 1, "single land pinhole is removed from open water")
	assert_equal(coast[3 * 12 + 3], 1, "broad navigable water survives coast smoothing")
	var diagonal_shore: Array[int] = []
	diagonal_shore.resize(3 * 3)
	diagonal_shore.fill(0)
	diagonal_shore[0] = 1
	RandomMapGenerator._apply_shore_band(diagonal_shore, Vector2i(3, 3))
	assert_equal(diagonal_shore[1 * 3 + 1], 2, "diagonal coast cells join the beach band instead of rendering isolated land diamonds")
	assert_equal(diagonal_shore[0], 1, "shore-band painting never replaces navigable water")

	if failures.is_empty():
		print("I11-002 seeded random map tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
