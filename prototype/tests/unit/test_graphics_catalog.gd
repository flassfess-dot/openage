extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_complete_graphics_catalog()

	if failures.is_empty():
		print("D-002 graphics catalog tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_complete_graphics_catalog() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var data: Dictionary = catalog.graphics_catalog_data
	assert_equal(data.get("graphic_count"), 941, "source graphic count")
	assert_equal(data.get("entry_count"), data.get("graphic_count"), "every graphic ID exported")
	assert_equal(data.get("graphics", {}).size(), data.get("graphic_count"), "catalog key count")
	assert_equal(String(data.get("cache", {}).get("key", "")).length(), 64, "catalog cache key")
	for key in data.get("graphics", {}):
		var graphic: Dictionary = data["graphics"][key]
		for field in ["graphic_id", "source_drs", "slp_id", "coordinates", "frames_per_angle", "angle_count", "frame_rate", "speed_adjust", "deltas", "player_color", "sounds", "slp"]:
			assert_true(graphic.has(field), "graphic %s has %s" % [key, field])
		assert_true(graphic["player_color"].has("force_id"), "graphic %s player color metadata" % key)
		assert_true(graphic["sounds"].has("sound_id"), "graphic %s linked sound" % key)
		if graphic["slp"].get("valid", false):
			assert_equal(graphic["slp"]["frames"].size(), graphic["slp"]["frame_count"], "graphic %s frame geometry count" % key)
			for frame in graphic["slp"]["frames"]:
				assert_true(frame.has("width") and frame.has("height") and frame.has("hotspot"), "graphic %s frame geometry" % key)
	var accent: Dictionary = data["graphics"].get("599", {})
	assert_equal(accent.get("source_drs"), "data/graphics.drs", "known composite source DRS")
	assert_equal(accent.get("slp_id"), 230, "known composite SLP ID")
	assert_equal(accent.get("slp", {}).get("frame_count"), 3, "known composite frame count")
	assert_equal(accent.get("slp", {}).get("frames", []).size(), 3, "known composite sizes and hotspots")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
