extends SceneTree

const InterfaceLayout := preload("res://scripts/interface_layout.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_source_resolution_layouts()
	test_wide_layout_preserves_source_edges()
	if failures.is_empty():
		print("I12-020L source HUD layout tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_source_resolution_layouts() -> void:
	for size in [Vector2(640, 480), Vector2(800, 600), Vector2(1024, 768)]:
		var layout := InterfaceLayout.for_viewport(size)
		assert_equal(int(layout["source_width"]), int(size.x), "source width %d" % int(size.x))
		assert_equal(layout["top"], Rect2(0, 0, size.x, 20), "top source frame %d" % int(size.x))
		assert_equal(layout["bottom"], Rect2(0, size.y - 126, size.x, 126), "bottom source frame %d" % int(size.x))
		assert_equal(layout["world"], Rect2(0, 20, size.x, size.y - 146), "world excludes exact source shell %d" % int(size.x))
		assert_non_overlapping(layout["command"], layout["selection"], "command/selection %d" % int(size.x))
		assert_non_overlapping(layout["selection"], layout["minimap"], "selection/minimap %d" % int(size.x))
		for region_name in ["command", "selection", "minimap"]:
			var region: Rect2 = layout[region_name]
			assert_true(layout["bottom"].encloses(region), "%s remains in bottom shell at %d" % [region_name, int(size.x)])


func test_wide_layout_preserves_source_edges() -> void:
	var layout := InterfaceLayout.for_viewport(Vector2(1536, 864))
	assert_equal(layout["source_width"], 1024, "wide viewport uses largest source shell")
	assert_true(bool(layout["expanded"]), "wide viewport declares composed expansion")
	assert_equal(layout["command"].position.x, 4.0, "wide command region keeps original left anchor")
	assert_equal(layout["minimap"].end.x, 1532.0, "wide minimap region keeps original right inset")
	assert_non_overlapping(layout["command"], layout["selection"], "wide command/selection")
	assert_non_overlapping(layout["selection"], layout["minimap"], "wide selection/minimap")


func assert_non_overlapping(left: Rect2, right: Rect2, context: String) -> void:
	assert_true(not left.intersects(right), "%s do not overlap: %s / %s" % [context, left, right])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])

