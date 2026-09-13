extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var icons = catalog.interface_icons
	assert_equal(icons.frame_count("object"), 61, "complete RoR object icon sheet")
	assert_equal(icons.frame_count("technology"), 101, "complete RoR technology icon sheet")
	assert_true(icons.has_icon("object", 1), "Priest object icon is available by DAT icon ID")
	assert_true(icons.has_icon("technology", 97), "Medicine technology icon is available by DAT icon ID")
	assert_true(icons.texture("object", 1) != null, "object icon lazily loads as a texture")
	assert_true(icons.texture("technology", 97) != null, "technology icon lazily loads as a texture")
	assert_true(not icons.has_icon("technology", 101), "out-of-range icon remains explicit")

	if failures.is_empty():
		print("I12-018 interface icon registry tests passed")
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
