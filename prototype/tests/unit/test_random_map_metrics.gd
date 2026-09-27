extends SceneTree

const RandomMapMetrics := preload("res://scripts/random_map_metrics.gd")
const RandomMapQuality := preload("res://scripts/random_map_quality.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_empty_space_and_density_metrics()
	_test_empty_space_metrics_are_balanced_by_zone()
	_test_terrain_diversity_metrics()
	_test_water_depth_metrics()
	_test_resource_contestability_metrics()
	_test_resource_distance_respects_obstacles()
	_test_generated_map_publishes_metrics()
	_finish("Random map observability metrics tests passed")


func _test_empty_space_and_density_metrics() -> void:
	var definition := _definition([Vector2(2.5, 9.5), Vector2(17.5, 9.5)])
	var open_map := _map_data(Vector2i(20, 20), _filled_terrain(Vector2i(20, 20), 0), [])
	var populated_resources: Array = []
	for y in [4, 9, 14]:
		for x in [4, 9, 14]:
			populated_resources.append(_resource(Vector2(x, y), "berries"))
	var populated_map := _map_data(Vector2i(20, 20), _filled_terrain(Vector2i(20, 20), 0), populated_resources)
	var open_metrics := RandomMapMetrics.measure(definition, open_map)
	var populated_metrics := RandomMapMetrics.measure(definition, populated_map)
	assert_true(float(open_metrics["empty_land_ratio"]) > float(populated_metrics["empty_land_ratio"]), "landmark objects reduce the measured empty-land ratio")
	assert_true(int(open_metrics["largest_empty_radius_cells"]) > int(populated_metrics["largest_empty_radius_cells"]), "landmark objects reduce the largest empty radius")
	assert_equal(int(open_metrics["land_object_cell_count"]), 0, "empty fixture has no occupied land cells")
	assert_equal(int(populated_metrics["land_object_cell_count"]), 9, "unique occupied land cells are counted")
	assert_true(float(populated_metrics["object_density_per_1000_land_cells"]) > 0.0, "object density is normalized by walkable area")


func _test_empty_space_metrics_are_balanced_by_zone() -> void:
	var size := Vector2i(30, 18)
	var resources: Array = []
	for y in [3, 8, 13]:
		for x in [3, 7, 11]:
			resources.append(_resource(Vector2(x, y), "berries"))
	var map_data := _map_data(size, _filled_terrain(size, 0), resources)
	var zone_ids := PackedInt32Array()
	zone_ids.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			zone_ids[y * size.x + x] = 2 if x < 15 else 4
	map_data["strategic_zones"] = {"zone_ids": zone_ids}
	var metrics := RandomMapMetrics.measure_occupancy(map_data)
	var empty_by_zone: Dictionary = metrics["empty_land_ratio_by_zone"]
	var density_by_zone: Dictionary = metrics["feature_density_per_1000_by_zone"]
	assert_true(float(empty_by_zone["frontier"]) > float(empty_by_zone["territory"]), "zone metrics expose an empty frontier even when the base-side territory is populated")
	assert_true(float(density_by_zone["territory"]) > float(density_by_zone["frontier"]), "zone metrics expose uneven feature density away from the bases")
	assert_true(float(metrics["outer_feature_density_spread_per_1000"]) > 0.0, "candidate scoring receives a cross-zone density spread")


func _test_terrain_diversity_metrics() -> void:
	var size := Vector2i(12, 12)
	var uniform := _filled_terrain(size, 0)
	var split := _filled_terrain(size, 0)
	for y in range(size.y):
		for x in range(6, size.x):
			split[y * size.x + x] = 6
	var definition := _definition([Vector2(2.5, 6.5), Vector2(9.5, 6.5)])
	var uniform_metrics := RandomMapMetrics.measure(definition, _map_data(size, uniform, []))
	var split_metrics := RandomMapMetrics.measure(definition, _map_data(size, split, []))
	assert_equal(int(uniform_metrics["terrain_type_count"]), 1, "uniform terrain exposes one terrain type")
	assert_approx(float(uniform_metrics["terrain_entropy_bits"]), 0.0, 0.0001, "uniform terrain has zero entropy")
	assert_equal(int(uniform_metrics["terrain_patch_count"]), 1, "uniform terrain forms one connected patch")
	assert_equal(int(split_metrics["terrain_type_count"]), 2, "split terrain exposes both terrain types")
	assert_approx(float(split_metrics["terrain_entropy_bits"]), 1.0, 0.0001, "equal terrain halves have one bit of entropy")
	assert_equal(int(split_metrics["terrain_patch_count"]), 2, "two connected halves form two patches")
	assert_equal(int(split_metrics["terrain_largest_patch_cells"]), 72, "largest terrain patch reports its cell count")


func _test_water_depth_metrics() -> void:
	var size := Vector2i(15, 12)
	var terrain := _filled_terrain(size, 0)
	for y in range(size.y):
		for x in range(4, size.x):
			terrain[y * size.x + x] = 1 if x < 7 else 22
	for y in range(3, 9):
		terrain[y * size.x + 5] = 4
	var metrics := RandomMapMetrics.measure(_definition([Vector2(2.5, 6.5)]), _map_data(size, terrain, []))
	assert_equal(int(metrics["water_depth_type_count"]), 3, "coast, walkable shallows, and deep water are measured separately")
	assert_true(int(metrics["coastal_water_cells"]) > 0, "coastal water is counted")
	assert_true(int(metrics["walkable_shallow_cells"]) > 0, "walkable shallows are counted")
	assert_true(int(metrics["deep_water_cells"]) > 0, "deep water is counted")


func _test_resource_contestability_metrics() -> void:
	var size := Vector2i(12, 12)
	var starts := [Vector2(1.5, 5.5), Vector2(9.5, 5.5)]
	var resources := [
		_resource(Vector2(2.5, 5.5), "gold_mine"),
		_resource(Vector2(8.5, 5.5), "stone_mine"),
		_resource(Vector2(5.5, 5.5), "berries"),
		_resource(Vector2(4.5, 4.5), "gazelle"),
		_owned_resource(Vector2(3.5, 5.5), starts[0]),
		{"category": "resource", "kind": "deep_fish", "position": Vector2(6.5, 6.5), "placement_domain": "water"},
	]
	var metrics := RandomMapMetrics.measure(_definition(starts), _map_data(size, _filled_terrain(size, 0), resources))
	assert_equal(int(metrics["neutral_land_resource_count"]), 4, "owned and water resources are excluded from neutral-land analysis")
	assert_equal(int(metrics["accessible_neutral_land_resource_count"]), 4, "all neutral fixture resources are reachable")
	assert_equal(int(metrics["safe_neutral_resource_count"]), 2, "resources close to one start are classified as safe")
	assert_equal(int(metrics["contested_neutral_resource_count"]), 1, "equidistant resource is classified as contested")
	assert_equal(int(metrics["frontier_neutral_resource_count"]), 1, "intermediate resource is classified as frontier")
	assert_equal(metrics["safe_neutral_resource_count_by_team"], {"1": 1, "2": 1}, "safe resources are attributed to their nearest team")
	assert_true(float(metrics["mean_neutral_resource_path_distance"]) > 0.0, "resource distance uses traversable map paths")


func _test_resource_distance_respects_obstacles() -> void:
	var size := Vector2i(12, 12)
	var terrain := _filled_terrain(size, 0)
	for y in range(10):
		terrain[y * size.x + 4] = 1
	var starts := [Vector2(1.5, 1.5), Vector2(10.5, 10.5)]
	var metrics := RandomMapMetrics.measure(_definition(starts), _map_data(size, terrain, [_resource(Vector2(6.5, 1.5), "gold_mine")]))
	assert_equal(int(metrics["safe_neutral_resource_count"]), 1, "detour converts the resource into a safe path-distance placement")
	assert_equal(metrics["safe_neutral_resource_count_by_team"], {"1": 0, "2": 1}, "resource belongs to the path-nearest team rather than the geometrically nearest team")
	assert_approx(float(metrics["mean_neutral_resource_path_distance"]), 13.0, 0.0001, "path distance follows the gap around the water barrier")


func _test_generated_map_publishes_metrics() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = "grasslands"
	settings["seed"] = 41721
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "generated fixture remains valid: %s" % str(built.get("errors", [])))
	if not bool(built.get("valid", false)):
		return
	var quality: Dictionary = RandomMapQuality.inspect(built["definition"], built["map_data"])
	var metrics: Dictionary = quality.get("metrics", {})
	for key in ["largest_empty_radius_cells", "empty_land_ratio", "empty_land_ratio_by_zone", "outer_largest_empty_radius_cells", "outer_feature_density_spread_per_1000", "object_density_per_1000_land_cells", "terrain_entropy_bits", "terrain_patch_count", "water_depth_type_count", "walkable_shallow_cells", "deep_water_cells", "contested_neutral_resource_count", "safe_neutral_resource_count_by_team"]:
		assert_true(metrics.has(key), "generated quality report publishes %s" % key)
	assert_true(float(metrics["empty_land_ratio"]) >= 0.0 and float(metrics["empty_land_ratio"]) <= 1.0, "empty-land ratio is normalized")
	assert_true(int(metrics["terrain_patch_count"]) > 0, "generated map contains measurable terrain patches")


func _definition(starts: Array) -> Dictionary:
	var players: Array = []
	for index in range(starts.size()):
		players.append({"team": index + 1, "start": starts[index]})
	return {"players": players, "map": {"generator": {}}}


func _map_data(size: Vector2i, terrain_ids: Array[int], resources: Array) -> Dictionary:
	var vertex_levels: Array[int] = []
	vertex_levels.resize((size.x + 1) * (size.y + 1))
	vertex_levels.fill(0)
	return {
		"size": size,
		"terrain_ids": terrain_ids,
		"vertex_levels": vertex_levels,
		"resources": resources,
		"scenery": [],
		"cliff_cells": [],
	}


func _filled_terrain(size: Vector2i, terrain_id: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(size.x * size.y)
	result.fill(terrain_id)
	return result


func _resource(position: Vector2, kind: String) -> Dictionary:
	return {"category": "resource", "kind": kind, "position": position, "placement_domain": "land", "owner_start": []}


func _owned_resource(position: Vector2, owner_start: Vector2) -> Dictionary:
	return {"category": "resource", "kind": "berries", "position": position, "placement_domain": "land", "owner_start": [owner_start.x, owner_start.y]}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_approx(actual: float, expected: float, tolerance: float, context: String) -> void:
	if absf(actual - expected) > tolerance:
		failures.append("%s: expected %s +/- %s, got %s" % [context, expected, tolerance, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
