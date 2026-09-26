extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	for profile in ["continental", "mediterranean", "hill_country", "narrows"]:
		for player_count in [2, 4, 8]:
			for seed in [41721, 7919]:
				var settings := SkirmishSettings.default_settings()
				settings["map_type_id"] = profile
				settings["map_size_id"] = "large" if player_count == 8 else "standard"
				settings["seed"] = seed
				for index in range(8):
					settings["players"][index]["enabled"] = index < player_count
					settings["players"][index]["controller"] = "human" if index == 0 else "ai"
				var result := SkirmishSettings.build(settings)
				var context := "%s/%d players/seed %d" % [profile, player_count, seed]
				assert_true(bool(result.get("valid", false)), "%s meets map quality gates: %s" % [context, result.get("errors", [])])
				if not bool(result.get("valid", false)):
					continue
				var quality: Dictionary = result["map_quality"]["metrics"]
				var map_data: Dictionary = result["map_data"]
				var map_size: Vector2i = map_data["size"]
				assert_equal(int(quality["player_count"]), player_count, "%s retains all starts" % context)
				assert_true(int(quality["land_analysis_cells"]) <= map_size.x * map_size.y, "%s analyzes each land cell at most once" % context)
				if profile in ["continental", "mediterranean"]:
					assert_equal(int(quality["naval_start_count"]), player_count, "%s has one valid coast for each player" % context)
				if profile in ["hill_country", "narrows"]:
					assert_true(int(quality["cliff_cell_count"]) > 0, "%s has explicit non-water cliffs" % context)
				if profile == "narrows":
					assert_true(int(quality["narrows_gate_width"]) >= 5, "%s retains a traversable central gate" % context)
				assert_equal(map_data["terrain_ids"].size(), map_size.x * map_size.y, "%s covers the declared grid" % context)
	if failures.is_empty():
		print("P09 RoR random map profile matrix tests passed")
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
