extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "giant"
	settings["map_type_id"] = "narrows"
	settings["seed"] = 41721
	for index in range(8):
		settings["players"][index]["enabled"] = true
		settings["players"][index]["controller"] = "human" if index == 0 else "ai"
	var result := SkirmishSettings.build(settings)
	assert_true(bool(result.get("valid", false)), "Gigantic eight-player Narrows map meets quality gates: %s" % [result.get("errors", [])])
	if bool(result.get("valid", false)):
		var size: Vector2i = result["map_data"]["size"]
		var metrics: Dictionary = result["map_quality"]["metrics"]
		assert_equal(size, Vector2i(200, 200), "Gigantic retains its 200×200 contract")
		assert_true(int(metrics["land_analysis_cells"]) <= size.x * size.y, "land connectivity analysis is bounded by map area, not players times area")
		assert_equal(int(metrics["player_count"]), 8, "performance gate includes all eight starts")
	if failures.is_empty():
		print("P09 Gigantic generation structural performance gate passed")
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
