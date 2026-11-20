extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const Registry := preload("res://scripts/interface_icon_registry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var icons = catalog.interface_icons
	assert_equal(icons.frame_count("object"), 61, "complete RoR object icon sheet")
	assert_equal(icons.frame_count("technology"), 101, "complete RoR technology icon sheet")
	assert_equal(icons.frame_count("command"), 15, "complete source command glyph sheet")
	assert_equal(icons.frame_count("building_4"), 50, "complete Roman building icon sheet")
	assert_true(icons.has_icon("object", 1), "Priest object icon is available by DAT icon ID")
	assert_true(icons.has_icon("technology", 97), "Medicine technology icon is available by DAT icon ID")
	assert_true(icons.has_icon("command", 3), "source stop glyph is available")
	assert_true(icons.has_icon("building_4", 15), "Roman House icon is available by DAT icon ID")
	assert_true(icons.texture("object", 1) != null, "object icon lazily loads as a texture")
	assert_true(icons.texture("technology", 97) != null, "technology icon lazily loads as a texture")
	assert_true(icons.texture("building_4", 15) != icons.texture("unit", 15), "building icons cannot silently fall back to the unit sheet")
	assert_true(not icons.has_icon("technology", 101), "out-of-range icon remains explicit")

	var fingerprints := {}
	for kind in ["command_custom", "gate_mode", "trade_resource"]:
		for id in range(icons.frame_count(kind)):
			var texture: Texture2D = icons.texture(kind, id)
			var context := "%s/%d" % [kind, id]
			assert_true(texture != null, context + " loads")
			if texture == null:
				continue
			var image := texture.get_image()
			var bounds := image.get_used_rect()
			assert_equal(image.get_size(), Vector2i(50, 50), context + " uses a square canvas")
			assert_true(bounds.size.x >= 30 and bounds.size.y >= 30, context + " isn't blank or lost in transparent padding")
			assert_true(image.get_pixel(0, 0).a == 0.0, context + " preserves the source backplate")
			var fingerprint := hash(image.get_data())
			assert_true(not fingerprints.has(fingerprint), context + " does not repeat another symbol")
			fingerprints[fingerprint] = true
			assert_true(icons.texture(kind, id, 2) == texture, context + " does not duplicate textures per player")
		assert_true(not icons.has_icon(kind, icons.frame_count(kind)), "%s bounds are explicit" % kind)
	assert_equal(fingerprints.size(), 13, "complete distinct modern action, gate and trade art")
	assert_equal(Registry.command_icon("open_build_menu").get("icon_id"), 2, "first hammer still opens construction")
	assert_equal(Registry.command_icon("repair").get("icon_id"), 0, "second hammer still repairs")
	assert_equal(Registry.command_icon("close_build_menu"), Registry.command_icon("delete"), "Back and Delete retain the source cross")

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
