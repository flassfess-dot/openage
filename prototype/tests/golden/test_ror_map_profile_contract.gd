extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	for profile in ["continental", "mediterranean", "hill_country", "narrows"]:
		for seed in [41721, 7919]:
			var settings := SkirmishSettings.default_settings()
			settings["map_type_id"] = profile
			settings["seed"] = seed
			var first := SkirmishSettings.build(settings)
			var second := SkirmishSettings.build(settings)
			assert_true(bool(first.get("valid", false)), "%s seed %d builds" % [profile, seed])
			if not bool(first.get("valid", false)):
				continue
			assert_equal(first["identity"], second["identity"], "%s seed %d match identity is stable" % [profile, seed])
			assert_equal(first["map_data"]["terrain_ids"], second["map_data"]["terrain_ids"], "%s seed %d coast is deterministic" % [profile, seed])
			assert_equal(first["map_data"]["cliff_cells"], second["map_data"]["cliff_cells"], "%s seed %d cliff contract is deterministic" % [profile, seed])
			if profile == "narrows":
				var narrows_size: Vector2i = first["map_data"]["size"]
				assert_true(first["map_data"]["cliff_cells"].has(Vector2i(int(narrows_size.x / 2), 0)), "Narrows barrier reaches the north edge")
				assert_true(not first["map_data"]["cliff_cells"].has(Vector2i(int(narrows_size.x / 2), int(narrows_size.y / 2))), "Narrows retains the central gate")
			if profile == "mediterranean":
				var sea_size: Vector2i = first["map_data"]["size"]
				assert_true(int(first["map_data"]["terrain_ids"][int(sea_size.y / 2) * sea_size.x + int(sea_size.x / 2)]) in TerrainRules.WATER_TERRAIN_IDS, "Mediterranean center is navigable water")
	if failures.is_empty():
		print("P09 fixed-seed coast, cliff and Narrows golden contracts passed")
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
