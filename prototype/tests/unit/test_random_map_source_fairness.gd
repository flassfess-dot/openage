extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var profiles: Array = SkirmishSettings.catalog().get("map_types", [])
	assert_equal(profiles.size(), 9, "all source RoR menu profiles are available")
	for profile_index in range(profiles.size()):
		var profile: Dictionary = profiles[profile_index]
		var profile_id := String(profile.get("id", ""))
		var previous_starts: Array = []
		for player_count in [2, 4, 8]:
			for seed in [1, 7919]:
				var settings := SkirmishSettings.default_settings()
				settings["map_type_id"] = profile_id
				settings["map_size_id"] = "large" if player_count == 8 else "standard"
				settings["seed"] = seed
				for slot in range(8):
					settings["players"][slot]["enabled"] = slot < player_count
				var built := SkirmishSettings.build(settings)
				var context := "%s/%dp/seed%d" % [profile_id, player_count, seed]
				assert_true(bool(built.get("valid", false)), "%s satisfies topology and reachable owned resources: %s" % [context, built.get("errors", [])])
				if not bool(built.get("valid", false)):
					continue
				var definition: Dictionary = built["definition"]
				var map_data: Dictionary = built["map_data"]
				var source_profile: Dictionary = definition.get("map", {}).get("generator", {}).get("source_profile", {})
				assert_equal(int(source_profile.get("source_index", -1)), profile_index, "%s uses the matching RoR DAT record" % context)
				var starts: Array = definition.get("players", []).map(func(player): return player.get("start", Vector2.ZERO))
				if player_count == 4 and not previous_starts.is_empty():
					assert_true(starts != previous_starts, "%s seed changes starting positions" % context)
				if player_count == 4:
					previous_starts = starts
				var occupied: Dictionary = {}
				var owned_count := 0
				var neutral_count := 0
				var wildlife_count := 0
				for entity_value in map_data.get("resources", []):
					var entity: Dictionary = entity_value
					var cell := Vector2i(Vector2(entity.get("position", Vector2.ZERO)))
					assert_true(not occupied.has(cell), "%s generated objects occupy separate cells" % context)
					occupied[cell] = true
					if not entity.get("owner_start", []).is_empty():
						owned_count += 1
					elif String(entity.get("category", "")) == "resource" and String(entity.get("placement_domain", "land")) == "land":
						neutral_count += 1
					if String(entity.get("category", "")) == "unit":
						wildlife_count += 1
				assert_true(owned_count >= player_count * 20, "%s has source-backed groups for every player" % context)
				assert_true(neutral_count > 0, "%s has neutral resources beyond starts" % context)
				assert_true(wildlife_count > 0, "%s has source-backed wildlife" % context)
				var terrain_ids: Array = map_data.get("terrain_ids", [])
				assert_true(terrain_ids.any(func(value): return int(value) in TerrainRules.SOURCE_FOREST_TERRAIN_IDS), "%s has source terrain clumps" % context)
				print("RoR map fairness checked %s" % context)
	if failures.is_empty():
		print("RoR DAT-backed random map fairness matrix passed")
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
