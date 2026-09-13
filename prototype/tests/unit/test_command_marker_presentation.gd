extends SceneTree

const CommandMarkerPresentation := preload("res://scripts/command_marker_presentation.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var marker := CommandMarkerPresentation.new()
	marker.trigger(Vector2(7.5, 9.25))
	var wide: Dictionary = marker.snapshot()
	assert_equal(wide.get("world_position"), Vector2(7.5, 9.25), "marker stays anchored to accepted world target")
	assert_equal(wide.get("half_extent"), Vector2(22.0, 14.0), "initial silhouette matches measured wide phase")
	assert_equal(wide.get("bright_color"), Color8(255, 1, 1), "marker uses measured source red")

	marker.advance(CommandMarkerPresentation.DEFAULT_DURATION * CommandMarkerPresentation.CONTRACT_DURATION_RATIO)
	var contracted: Dictionary = marker.snapshot()
	assert_vector_close(contracted.get("half_extent", Vector2.ZERO), Vector2(13.0, 10.0), 0.001, "arrows converge to measured contracted phase")
	assert_true(marker.active, "contracted phase remains visible before the duration boundary")

	marker.advance(CommandMarkerPresentation.DEFAULT_DURATION)
	assert_true(not marker.active, "marker expires without simulation state")
	assert_true(marker.snapshot().is_empty(), "expired marker has no drawable snapshot")

	var horizontal := CommandMarkerPresentation.arrow_polygon(Vector2.RIGHT, 22.0)
	assert_equal(horizontal.size(), 7, "arrow geometry is one stable pixel-art polygon")
	assert_true(horizontal[0].x < horizontal[3].x, "arrow points inward from its outer tail")

	if failures.is_empty():
		print("I3/I10 command marker presentation tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append(context)


func assert_vector_close(actual: Vector2, expected: Vector2, tolerance: float, context: String) -> void:
	if actual.distance_to(expected) > tolerance:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
