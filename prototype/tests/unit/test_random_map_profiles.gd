extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const RandomMapGenerator := preload("res://scripts/random_map_generator.gd")
const RandomMapQuality := preload("res://scripts/random_map_quality.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := SkirmishSettings.catalog()
	var profiles: Array = catalog.get("map_types", [])
	assert_equal(profiles.size(), 4, "catalog exposes two land and two water-capable profiles")
	for profile_value in profiles:
		var profile: Dictionary = profile_value
		for seed in [1, 41721, 99991]:
			var settings := four_player_settings(String(profile.get("id", "")), seed)
			var built := SkirmishSettings.build(settings)
			assert_true(bool(built.get("valid", false)), "%s seed %d builds: %s" % [profile.get("id"), seed, built.get("errors", [])])
			if not bool(built.get("valid", false)):
				continue
			var definition: Dictionary = built["definition"]
			var first: Dictionary = built["map_data"]
			var second := RandomMapGenerator.generate(definition)
			assert_equal(first, second, "%s seed %d is byte-for-byte deterministic" % [profile.get("id"), seed])
			var quality := RandomMapQuality.inspect(definition, first)
			assert_true(bool(quality.get("valid", false)), "%s seed %d satisfies fairness/connectivity/resources: %s" % [profile.get("id"), seed, quality.get("errors", [])])
			assert_equal(int(quality.get("metrics", {}).get("player_count", 0)), 4, "%s audits every active start" % profile.get("id"))
			if bool(profile.get("requires_naval_starts", false)):
				assert_equal(int(quality.get("metrics", {}).get("naval_start_count", 0)), 4, "%s gives every player a legal dock/staging pair" % profile.get("id"))
				var deep_fish: Array = first.get("resources", []).filter(func(resource): return String(resource.get("kind", "")) == "deep_fish")
				assert_equal(deep_fish.size(), 12, "%s gives every naval start a deterministic deep-fish cluster" % profile.get("id"))
				assert_true(deep_fish.all(func(resource): return RandomMapGenerator._cell_matches_domain_with_clearance(Vector2i(Vector2(resource.get("position", Vector2.ZERO))), first["size"], first["terrain_ids"], "water", 2)), "%s keeps every generated deep-fish pool in navigable open water" % profile.get("id"))
				for zone_value in first.get("naval_start_zones", []):
					var zone: Dictionary = zone_value
					var nearby := deep_fish.filter(func(resource): return Vector2(resource.get("position", Vector2.ZERO)).distance_to(Vector2(zone.get("water_staging", Vector2.ZERO))) <= 12.0)
					assert_true(nearby.size() >= 2, "%s keeps harvestable water food near team %d's Dock staging" % [profile.get("id"), int(zone.get("team", 0))])
			else:
				assert_equal(int(quality.get("metrics", {}).get("naval_start_count", 0)), 0, "%s does not invent naval starts" % profile.get("id"))
				assert_true(first.get("resources", []).all(func(resource): return String(resource.get("kind", "")) != "deep_fish"), "%s does not place naval food on a land-only profile" % profile.get("id"))
	_finish("E5-003 random map profile tests passed")


func four_player_settings(map_type_id: String, seed: int) -> Dictionary:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "standard"
	settings["map_type_id"] = map_type_id
	settings["seed"] = seed
	for index in range(8):
		settings["players"][index]["enabled"] = index < 4
		settings["players"][index]["controller"] = "human" if index == 0 else "ai"
	return settings


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
