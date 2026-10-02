extends SceneTree

const InterfaceLayout := preload("res://scripts/interface_layout.gd")
var failures: Array[String] = []

func _initialize() -> void:
	assert_equal(InterfaceLayout.shell_asset_name(1024, 4), "hud_shell_1024_4", "Roman artwork retains its own family")
	for width in [320, 430, 640, 719, 720, 800, 840, 960, 1024, 1280, 2560]:
		var size := Vector2(width, 720)
		var layout := InterfaceLayout.for_viewport(size)
		var narrow: bool = width < 720
		var top_height := 64.0 if narrow else 32.0
		var bottom_height := 252.0 if narrow else 126.0
		assert_equal(layout["source_width"], 1024, "all widths compose the same measured source at %d" % width)
		assert_equal(layout["top"], Rect2(0, 0, width, top_height), "flat top strip at %d" % width)
		assert_equal(layout["bottom"], Rect2(0, 720 - bottom_height, width, bottom_height), "compact bottom panel at %d" % width)
		assert_equal(layout["world"], Rect2(0, top_height, width, 720 - bottom_height - top_height), "world excludes both panels at %d" % width)
		for region_name in ["selection", "command", "production", "minimap_plane"]:
			assert_true(layout["bottom"].encloses(layout[region_name]), "%s stays inside its shell at %d" % [region_name, width])
		for pair in [["selection", "command"], ["selection", "production"], ["command", "production"], ["command", "minimap_plane"], ["production", "minimap_plane"]]:
			assert_true(not layout[pair[0]].intersects(layout[pair[1]]), "%s/%s cannot overlap at %d" % [pair[0], pair[1], width])
		assert_equal(layout["minimap"].size, Vector2(219, 109) * float(layout["minimap_scale"]), "native minimap opening at %d" % width)
		assert_true((layout["minimap"].position - layout["minimap_plane"].position).distance_to(Vector2(4, 7) * float(layout["minimap_scale"])) < 0.001, "native opening offset at %d" % width)
		assert_true(layout["production"].size.x <= InterfaceLayout.PRODUCTION_MAX_WIDTH, "production width is bounded at %d" % width)
		var command: Rect2 = layout["command"]
		var columns := floori((command.size.x + InterfaceLayout.COMMAND_GAP) / (InterfaceLayout.COMMAND_CELL_SIZE + InterfaceLayout.COMMAND_GAP))
		assert_equal(command.size.x, columns * (InterfaceLayout.COMMAND_CELL_SIZE + InterfaceLayout.COMMAND_GAP) - InterfaceLayout.COMMAND_GAP, "command space reserves whole fixed-size columns at %d" % width)
		assert_true(columns >= 3, "at least three full-size columns remain usable at %d" % width)
		if width >= 1280:
			assert_equal(columns, 10, "full late-age construction palette fits at %d" % width)
		if not narrow:
			assert_equal(layout["production"].position.x, command.end.x + InterfaceLayout.PRODUCTION_GAP, "production is pinned beside command area at %d" % width)
			assert_equal(layout["selection"].position.y, layout["command"].position.y, "icons align with the panel top")
			assert_equal(layout["production"].position.y, layout["command"].position.y, "production aligns with the panel top")
	finish()

func finish() -> void:
	for failure in failures:
		push_error(failure)
	if failures.is_empty(): print("Adaptive native HUD layout tests passed")
	quit(0 if failures.is_empty() else 1)

func assert_true(value: bool, context: String) -> void:
	if not value: failures.append(context)

func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected: failures.append("%s: expected %s, got %s" % [context, expected, actual])