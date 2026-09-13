extends SceneTree

const PixelScaling := preload("res://scripts/pixel_scaling.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_project_uses_fixed_virtual_frame()
	test_zoom_is_discrete_and_pixel_safe()
	test_sprite_anchor_is_snapped_once()

	if failures.is_empty():
		print("G-005 pixel-perfect tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_project_uses_fixed_virtual_frame() -> void:
	assert_equal(int(ProjectSettings.get_setting("display/window/size/viewport_width")), PixelScaling.VIRTUAL_SIZE.x, "virtual width")
	assert_equal(int(ProjectSettings.get_setting("display/window/size/viewport_height")), PixelScaling.VIRTUAL_SIZE.y, "virtual height")
	assert_equal(String(ProjectSettings.get_setting("display/window/stretch/mode")), "viewport", "final-frame scaling mode")
	assert_equal(String(ProjectSettings.get_setting("display/window/stretch/aspect")), "keep", "virtual aspect is preserved")
	assert_equal(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter")), 0, "nearest texture filtering")


func test_zoom_is_discrete_and_pixel_safe() -> void:
	var zoom := 1.0
	zoom = PixelScaling.step_zoom(zoom, 1)
	assert_equal(zoom, 2.0, "zoom in reaches next integer level")
	zoom = PixelScaling.step_zoom(zoom, 1)
	assert_equal(zoom, 3.0, "second zoom in reaches 3x")
	zoom = PixelScaling.step_zoom(zoom, 1)
	assert_equal(zoom, 3.0, "zoom clamps at maximum")
	for level in PixelScaling.ZOOM_LEVELS:
		assert_equal(PixelScaling.is_pixel_safe_zoom(level), true, "zoom level %s is pixel-safe" % level)


func test_sprite_anchor_is_snapped_once() -> void:
	assert_equal(PixelScaling.snap_screen(Vector2(10.49, 20.51)), Vector2(10, 21), "screen anchor rounding")
	assert_equal(PixelScaling.snap_screen(Vector2(10, 21)), Vector2(10, 21), "snapping is idempotent")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
