extends SceneTree

const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const RandomMapMetrics := preload("res://scripts/random_map_metrics.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_bounded_candidate_selection()
	_test_sparse_fill_pass()
	_test_candidate_budget_scales_with_map_area()
	_finish("Random map candidate selection tests passed")


func _test_bounded_candidate_selection() -> void:
	var first := _build("grasslands", "standard", 41721)
	var repeated := _build("grasslands", "standard", 41721)
	assert_true(bool(first.get("valid", false)), "candidate fixture builds: %s" % str(first.get("errors", [])))
	assert_true(bool(repeated.get("valid", false)), "repeated candidate fixture builds: %s" % str(repeated.get("errors", [])))
	if not bool(first.get("valid", false)) or not bool(repeated.get("valid", false)):
		return
	var map_data: Dictionary = first["map_data"]
	var metadata: Dictionary = map_data.get("generation_candidates", {})
	var scores: Array = metadata.get("scores", [])
	assert_equal(int(metadata.get("candidate_count", 0)), 3, "standard maps compare three bounded ambient candidates")
	assert_equal(scores.size(), 3, "every evaluated candidate publishes a compact score")
	assert_equal(map_data, repeated["map_data"], "candidate selection remains byte-for-byte deterministic")
	var selected_index := int(metadata.get("selected_candidate_index", -1))
	assert_true(selected_index >= 0 and selected_index < scores.size(), "selected candidate index points at a published score")
	if selected_index < 0 or selected_index >= scores.size():
		return
	var selected_score: Dictionary = scores[selected_index]
	for score_value in scores:
		var score: Dictionary = score_value
		assert_true(not RandomMapGenerator._ambient_score_is_better(score, selected_score), "no rejected candidate has a better empty-space score than the selected one")
	assert_equal(int(metadata.get("selected_candidate_seed", 0)), int(selected_score.get("seed", -1)), "selected seed matches the winning score")
	var recreated := RandomMapGenerator._seeded_ambient_scenery(
		map_data["size"],
		map_data["terrain_ids"],
		map_data["resources"],
		map_data["strategic_zones"],
		int(metadata["selected_candidate_seed"])
	)
	assert_equal(map_data.get("scenery", []), recreated, "published scenery is exactly the selected candidate")


func _test_sparse_fill_pass() -> void:
	var built := _build("grasslands", "standard", 7919)
	assert_true(bool(built.get("valid", false)), "sparse-fill fixture builds: %s" % str(built.get("errors", [])))
	if not bool(built.get("valid", false)):
		return
	var map_data: Dictionary = built["map_data"]
	var scenery: Array = map_data.get("scenery", [])
	var fill: Array = scenery.filter(func(entity): return bool(entity.get("sparse_fill", false)))
	assert_true(not fill.is_empty(), "a standard map receives a second pass for sparse regions")
	var before_fill := map_data.duplicate(true)
	before_fill["scenery"] = scenery.filter(func(entity): return not bool(entity.get("sparse_fill", false)))
	var before_metrics := RandomMapMetrics.measure_occupancy(before_fill)
	var after_metrics := RandomMapMetrics.measure_occupancy(map_data)
	assert_true(int(after_metrics.get("largest_empty_radius_cells", 0)) <= int(before_metrics.get("largest_empty_radius_cells", 0)), "sparse fill does not enlarge the widest empty region")
	assert_true(float(after_metrics.get("empty_land_ratio", 0.0)) <= float(before_metrics.get("empty_land_ratio", 0.0)), "sparse fill does not increase empty land")
	assert_true(int(after_metrics.get("outer_largest_empty_radius_cells", 0)) <= int(before_metrics.get("outer_largest_empty_radius_cells", 0)), "sparse fill improves or preserves the worst non-base zone")
	assert_true(float(after_metrics.get("outer_empty_land_ratio_max", 0.0)) <= float(before_metrics.get("outer_empty_land_ratio_max", 0.0)), "sparse fill improves or preserves the emptiest non-base zone")


func _test_candidate_budget_scales_with_map_area() -> void:
	assert_equal(RandomMapGenerator._ambient_candidate_count(Vector2i(72, 72)), 3, "standard maps receive the full candidate budget")
	assert_equal(RandomMapGenerator._ambient_candidate_count(Vector2i(200, 200)), 2, "large maps use a reduced candidate budget")
	assert_equal(RandomMapGenerator._ambient_candidate_count(Vector2i(400, 400)), 1, "supergiant maps avoid repeated whole-map scoring")


func _build(profile: String, map_size: String, seed: int) -> Dictionary:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = profile
	settings["map_size_id"] = map_size
	settings["seed"] = seed
	return SkirmishSettings.build(settings)


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
