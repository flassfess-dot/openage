extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_sound_variants_and_bindings()

	if failures.is_empty():
		print("D-006 sound catalog tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_sound_variants_and_bindings() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var data: Dictionary = catalog.sound_catalog_data
	assert_equal(data.get("sound_count"), 234, "logical sound count")
	assert_equal(data.get("sounds", {}).size(), data.get("sound_count"), "every logical sound exported")
	assert_equal(data.get("unresolved_sound_ids", []).size(), 0, "all event sound IDs resolve")
	assert_equal(String(data.get("cache", {}).get("key", "")).length(), 64, "sound cache key")
	for key in data.get("sounds", {}):
		var sound: Dictionary = data["sounds"][key]
		for field in ["play_delay", "volume", "total_probability", "items", "categories", "event_bindings"]:
			assert_true(sound.has(field), "sound %s has %s" % [key, field])
		var summed_probability := 0
		for item in sound["items"]:
			summed_probability += int(item["probability"])
			if item["source_drs"] != null:
				assert_true(item["audio"].get("valid", false), "sound %s available WAV metadata" % key)
		assert_equal(sound["total_probability"], summed_probability, "sound %s probability total" % key)
	var selection: Dictionary = data["sounds"].get("47", {})
	assert_equal(selection.get("items", []).size(), 5, "villager selection variants")
	assert_equal(selection.get("total_probability"), 100, "villager selection probability")
	assert_true(selection.get("categories", []).has("voice_selection"), "selection category")
	assert_true(not selection.get("event_bindings", []).is_empty(), "selection event bindings")
	assert_true(selection["items"][0]["source_drs"] != null, "selection WAV resolves")
	var production: Dictionary = data["sounds"].get("128", {})
	assert_true(production.get("categories", []).has("production"), "production category")
	assert_equal(production.get("volume", {}).get("value"), null, "unstored volume is not guessed")
	assert_true(String(production.get("volume", {}).get("source", "")).contains("not stored"), "volume limitation documented")
	for missing in data.get("missing_audio", []):
		assert_true(int(missing["resource_id"]) >= 0, "sentinel WAV IDs are not reported missing")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
