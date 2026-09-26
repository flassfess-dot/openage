extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var defaults := SkirmishSettings.default_settings()
	assert_true(not bool(defaults.get("full_tech_tree", true)), "Full Tech Tree defaults off")
	var catalog: Dictionary = SkirmishSettings.catalog()
	for profile in ["continental", "mediterranean", "hill_country", "narrows"]:
		assert_true(catalog["map_types"].any(func(entry): return String(entry.get("id", "")) == profile), "%s is a selectable map profile" % profile)
	var random_settings := defaults.duplicate(true)
	random_settings["players"][0]["civilization_id"] = 0
	random_settings["players"][1]["civilization_id"] = 0
	random_settings["full_tech_tree"] = true
	var first := SkirmishSettings.build(random_settings)
	var second := SkirmishSettings.build(random_settings)
	assert_true(bool(first.get("valid", false)), "seeded Random civilization match builds: %s" % [first.get("errors", [])])
	if bool(first.get("valid", false)):
		assert_equal(first.get("identity"), second.get("identity"), "Random civilization is resolved once before match identity")
		for index in range(2):
			var civilization_id := int(first["definition"]["players"][index]["civilization_id"])
			assert_true(civilization_id >= 1 and civilization_id <= 16, "Random slot resolves to a playable civilization")
			assert_equal(civilization_id, int(second["definition"]["players"][index]["civilization_id"]), "same seed yields the same civilization assignment")
		assert_true(bool(first["definition"].get("full_tech_tree", false)), "Full Tech Tree reaches the normalized match rule")
	var invalid := defaults.duplicate(true)
	invalid["full_tech_tree"] = "yes"
	assert_true(SkirmishSettings.normalize(invalid)["errors"].has("skirmish_full_tech_tree_invalid"), "Full Tech Tree rejects non-boolean values")
	invalid = defaults.duplicate(true)
	invalid["players"][0]["civilization_id"] = 17
	assert_true(SkirmishSettings.normalize(invalid)["errors"].has("skirmish_player_civilization_invalid:1"), "Random sentinel does not accept out-of-range civilization IDs")
	if failures.is_empty():
		print("P09 RoR skirmish settings tests passed")
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
