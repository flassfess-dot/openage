extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_complete_object_catalog()

	if failures.is_empty():
		print("D-003 object catalog tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_complete_object_catalog() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var data: Dictionary = catalog.object_catalog_data
	assert_equal(data.get("counts", {}).get("civilizations"), 17, "civilization count")
	assert_equal(data.get("counts", {}).get("objects"), data.get("objects", {}).size(), "object count")
	assert_equal(data.get("counts", {}).get("technologies"), 127, "technology count")
	assert_equal(data.get("counts", {}).get("effect_bundles"), 218, "effect bundle count")
	assert_true(data.get("counts", {}).get("buildings", 0) > 0, "building catalog is populated")
	assert_true(data.get("counts", {}).get("resource_objects", 0) > 0, "resource catalog is populated")
	assert_true(data.get("counts", {}).get("resource_objects", 0) < data.get("counts", {}).get("objects", 0), "empty storage slots are not resources")
	assert_equal(String(data.get("cache", {}).get("key", "")).length(), 64, "object catalog cache key")
	var archer: Dictionary = data.get("objects", {}).get("13:4", {})
	assert_equal(archer.get("unit_id"), 4, "Roman archer ID")
	assert_true(not archer.get("combat", {}).get("attacks", []).is_empty(), "attacks extracted")
	assert_true(not archer.get("combat", {}).get("armors", []).is_empty(), "armor extracted")
	assert_true(not archer.get("commands", []).is_empty(), "unit commands extracted")
	assert_true(archer.get("graphics", {}).has("attack"), "graphic links extracted")
	assert_true(archer.get("sounds", {}).has("command"), "sound links extracted")
	assert_true(archer.get("resources", {}).has("cost"), "resource links extracted")
	assert_true(data.get("building_keys", []).has("13:109"), "Town Center classified as building")
	var romans: Dictionary = data.get("civilizations", [])[13]
	assert_true(not romans.get("resources", []).is_empty(), "civilization resources extracted")
	assert_true(romans.get("object_keys", []).has("13:4"), "civilization links its objects")
	var technology: Dictionary = data.get("technologies", {}).values()[0]
	for field in ["required_technology_ids", "research_location_id", "research_time", "resource_costs", "effect_bundle_id"]:
		assert_true(technology.has(field), "technology has %s" % field)
	assert_true(not data.get("commands", {}).get("unit", {}).is_empty(), "unit command catalog")
	assert_true(not data.get("commands", {}).get("technology_effect", {}).is_empty(), "technology effect command catalog")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
