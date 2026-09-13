extends SceneTree

const SpriteGeometry := preload("res://scripts/sprite_geometry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_hotspot_stays_anchored()
	test_mirror_round_trip()

	if failures.is_empty():
		print("R-004 sprite mirroring tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_hotspot_stays_anchored() -> void:
	var anchor := Vector2(320.5, 180.25)
	var hotspot := Vector2(11, 32)
	assert_vector_close(SpriteGeometry.source_to_screen(hotspot, anchor, 2.0, hotspot, false), anchor, "normal hotspot anchor")
	assert_vector_close(SpriteGeometry.source_to_screen(hotspot, anchor, 2.0, hotspot, true), anchor, "mirrored hotspot anchor")
	var rectangle := SpriteGeometry.anchored_rectangle(Vector2(20, 37), hotspot, 2.0)
	assert_equal(rectangle.position, Vector2(-22, -64), "anchored rectangle origin")


func test_mirror_round_trip() -> void:
	var anchor := Vector2(100, 90)
	var hotspot := Vector2(12, 30)
	var asymmetric_source := Vector2(3.25, 14.75)
	var normal_screen := SpriteGeometry.source_to_screen(asymmetric_source, anchor, 1.5, hotspot, false)
	var mirrored_screen := SpriteGeometry.source_to_screen(asymmetric_source, anchor, 1.5, hotspot, true)
	assert_equal(is_equal_approx(normal_screen.x + mirrored_screen.x, anchor.x * 2.0), true, "single reflection around hotspot")
	assert_vector_close(SpriteGeometry.screen_to_source(normal_screen, anchor, 1.5, hotspot, false), asymmetric_source, "normal round trip")
	assert_vector_close(SpriteGeometry.screen_to_source(mirrored_screen, anchor, 1.5, hotspot, true), asymmetric_source, "mirrored round trip")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
