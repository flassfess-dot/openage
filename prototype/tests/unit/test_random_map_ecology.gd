extends SceneTree

const Decorations := preload("res://scripts/random_map_decorations.gd")
const RandomMapMetrics := preload("res://scripts/random_map_metrics.gd")
const RandomMapZones := preload("res://scripts/random_map_zones.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_inland_ecology_and_density()
	_test_coastal_predators()
	_finish("Random map zoned ecology tests passed")


func _test_inland_ecology_and_density() -> void:
	var built := _build("grasslands", 4, 41721)
	assert_true(bool(built.get("valid", false)), "grasslands fixture builds: %s" % str(built.get("errors", [])))
	if not bool(built.get("valid", false)):
		return
	var definition: Dictionary = built["definition"]
	var map_data: Dictionary = built["map_data"]
	var global_objects: Array = map_data.get("resources", []).filter(func(entity): return bool(entity.get("source_global", false)))
	var global_wildlife: Array = global_objects.filter(func(entity): return String(entity.get("category", "")) == "unit")
	for kind in ["gazelle", "elephant", "lion"]:
		assert_true(global_wildlife.any(func(entity): return String(entity.get("kind", "")) == kind), "inland ecology includes source-global %s groups" % kind)
	assert_true(global_objects.all(func(entity): return String(entity.get("strategic_zone", "")) in ["territory", "frontier", "contested"]), "global groups retain a non-sanctuary strategic role")
	var scenery: Array = map_data.get("scenery", [])
	assert_true(scenery.size() >= 20, "standard inland map receives a visible ambient scenery budget")
	assert_true(scenery.all(func(entity): return bool(entity.get("ambient", false))), "decoration remains presentation-only")
	assert_true(scenery.any(func(entity): return String(entity.get("decoration_key", "")).contains("rock") or entity.get("decoration_key") == "boulders"), "ambient layer contains terrain-matched rocks")
	assert_true(scenery.any(func(entity): return entity.get("presentation_layer") == "decal"), "ambient layer includes actual flat ground detail")
	var specs: Dictionary = {}
	for spec in Decorations.palette(): specs[spec["key"]] = spec
	for first_index in range(scenery.size()):
		for second_index in range(first_index + 1, scenery.size()):
			var left: Dictionary = scenery[first_index]
			var right: Dictionary = scenery[second_index]
			if left["presentation_layer"] != right["presentation_layer"]: continue
			var distance := (float(specs[left["decoration_key"]]["placement"]["spacing"]) + float(specs[right["decoration_key"]]["placement"]["spacing"])) * 0.5
			assert_true(Vector2(left["position"]).distance_to(right["position"]) + 0.0001 >= distance, "decorations retain palette-specific clearance after jitter")
	var without_scenery := map_data.duplicate(true)
	without_scenery["scenery"] = []
	var dense_metrics := RandomMapMetrics.measure(definition, map_data)
	var sparse_metrics := RandomMapMetrics.measure(definition, without_scenery)
	assert_true(float(dense_metrics["object_density_per_1000_land_cells"]) > float(sparse_metrics["object_density_per_1000_land_cells"]), "ambient pass increases normalized map occupancy")
	assert_true(int(dense_metrics["largest_empty_radius_cells"]) <= int(sparse_metrics["largest_empty_radius_cells"]), "ambient pass never enlarges the largest empty region")


func _test_coastal_predators() -> void:
	var built := _build("coastal", 2, 7919)
	assert_true(bool(built.get("valid", false)), "coastal fixture builds: %s" % str(built.get("errors", [])))
	if not bool(built.get("valid", false)):
		return
	var map_data: Dictionary = built["map_data"]
	var alligators: Array = map_data.get("resources", []).filter(func(entity):
		return bool(entity.get("source_global", false)) and int(entity.get("source_unit_id", -1)) == 1 and String(entity.get("kind", "")) == "alligator"
	)
	assert_true(not alligators.is_empty(), "coastal source profile produces global alligators")
	assert_true(alligators.all(func(entity): return _near_published_coast(map_data, Vector2i(Vector2(entity.get("position", Vector2.ZERO))), 2)), "global alligators remain near their coastal anchor")
	var water_features: Dictionary = map_data.get("water_features", {})
	assert_true(int(water_features.get("coastal_water_cells", 0)) > 0, "coastal map contains a light near-shore water band")
	assert_true(int(water_features.get("deep_water_cells", 0)) > 0, "coastal map contains deep water away from land")
	assert_true(int(water_features.get("walkable_shallow_cells", 0)) > 0, "coastal map contains walkable sandbars")
	assert_true(map_data.get("scenery", []).any(func(entity): return entity.get("decoration_key", "") == "ror_shallows"), "walkable shallows receive varied original-game water detail")


func _near_published_coast(map_data: Dictionary, origin: Vector2i, radius: int) -> bool:
	var size: Vector2i = map_data["size"]
	var zones: Dictionary = map_data["strategic_zones"]
	for y in range(maxi(0, origin.y - radius), mini(size.y, origin.y + radius + 1)):
		for x in range(maxi(0, origin.x - radius), mini(size.x, origin.x + radius + 1)):
			if RandomMapZones.is_coastal_at(zones, size, Vector2i(x, y)):
				return true
	return false


func _build(profile: String, player_count: int, seed: int) -> Dictionary:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = profile
	settings["seed"] = seed
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = index < player_count
		settings["players"][index]["controller"] = "human" if index == 0 else "ai"
	return SkirmishSettings.build(settings)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
