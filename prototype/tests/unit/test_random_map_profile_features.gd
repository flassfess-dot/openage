extends SceneTree

const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_multilobed_source_terrain_clumps()
	_test_profile_relief_chains()
	_test_generated_profiles_keep_distinct_relief()
	_finish("Random map profile feature tests passed")


func _test_multilobed_source_terrain_clumps() -> void:
	var size := Vector2i(64, 64)
	var source_profile := {
		"terrain_groups": [{
			"terrain_id": 10,
			"proportion": 15,
			"number_of_clumps": 3,
			"edge_spacing": 5,
			"clumpiness": 32,
		}],
	}
	var starts: Array[Vector2] = [Vector2(32.5, 32.5)]
	var first := _filled_terrain(size, 0)
	var second := _filled_terrain(size, 0)
	RandomMapGenerator._apply_source_terrain_groups(first, size, starts, source_profile, 41721)
	RandomMapGenerator._apply_source_terrain_groups(second, size, starts, source_profile, 41721)
	assert_equal(first, second, "same seed produces identical multilobed terrain clumps")
	var forest_cells: Array[Vector2i] = []
	var row_widths: Dictionary = {}
	for y in range(size.y):
		var row_count := 0
		for x in range(size.x):
			if int(first[y * size.x + x]) != 10:
				continue
			forest_cells.append(Vector2i(x, y))
			row_count += 1
			assert_true(x >= 5 and y >= 5 and x < size.x - 5 and y < size.y - 5, "edge spacing keeps source clumps away from the map border")
			assert_true((Vector2(x, y) + Vector2.ONE * 0.5).distance_to(starts[0]) >= 6.0, "forest clumps preserve the start clearing")
		if row_count > 0:
			row_widths[row_count] = true
	assert_true(forest_cells.size() > 100, "source terrain proportion creates a substantial forest area")
	assert_true(row_widths.size() >= 4, "multilobed clumps produce varied row silhouettes rather than one repeated disk width")


func _test_profile_relief_chains() -> void:
	var size := Vector2i(72, 72)
	var terrain := _filled_terrain(size, 0)
	var starts: Array[Vector2] = [Vector2(18.5, 18.5), Vector2(53.5, 53.5)]
	var inland := RandomMapGenerator._seeded_relief_hills(size, starts, terrain, 7919, "inland")
	var highlands := RandomMapGenerator._seeded_relief_hills(size, starts, terrain, 7919, "highlands")
	var repeated := RandomMapGenerator._seeded_relief_hills(size, starts, terrain, 7919, "highlands")
	var hill_country := RandomMapGenerator._seeded_relief_hills(size, starts, terrain, 7919, "hill_country")
	assert_equal(highlands, repeated, "profile relief chains are deterministic")
	assert_true(highlands.size() > inland.size(), "Highlands receives more structured relief than open inland terrain")
	assert_true(highlands.any(func(hill): return String(hill.get("relief_shape", "")) == "ridge"), "Highlands contains ridge-chain segments")
	assert_true(hill_country.any(func(hill): return String(hill.get("relief_shape", "")) == "ridge"), "Hill Country contains broken ridge-chain segments")
	assert_true(inland.all(func(hill): return String(hill.get("relief_shape", "")) == "hill"), "open inland terrain keeps isolated low hills")
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	levels.fill(0)
	for hill_value in highlands:
		RandomMapGenerator._apply_relief_hill(levels, size, terrain, hill_value)
	assert_true(int(levels.max()) >= 2, "Highlands ridge chain reaches visible multi-level elevation")


func _test_generated_profiles_keep_distinct_relief() -> void:
	var highlands := _build("highlands", 41721)
	var hill_country := _build("hill_country", 41721)
	assert_true(bool(highlands.get("valid", false)), "Highlands fixture remains valid: %s" % str(highlands.get("errors", [])))
	assert_true(bool(hill_country.get("valid", false)), "Hill Country fixture remains valid: %s" % str(hill_country.get("errors", [])))
	if bool(highlands.get("valid", false)) and bool(hill_country.get("valid", false)):
		assert_true(highlands["map_data"]["vertex_levels"] != hill_country["map_data"]["vertex_levels"], "profiles no longer share the same relief field")


func _build(profile: String, seed: int) -> Dictionary:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = profile
	settings["seed"] = seed
	return SkirmishSettings.build(settings)


func _filled_terrain(size: Vector2i, terrain_id: int) -> Array[int]:
	var result: Array[int] = []
	result.resize(size.x * size.y)
	result.fill(terrain_id)
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
