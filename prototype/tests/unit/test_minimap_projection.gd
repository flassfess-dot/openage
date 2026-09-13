extends SceneTree

const MinimapProjection := preload("res://scripts/minimap_projection.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var center := Vector2(500.0, 300.0)
	var scale := 3.25
	for world in [Vector2.ZERO, Vector2(24, 0), Vector2(0, 24), Vector2(24, 24), Vector2(7.25, 18.5)]:
		var screen := MinimapProjection.world_to_minimap(world, center, scale)
		assert_vector(MinimapProjection.minimap_to_world(screen, center, scale), world, "minimap projection round-trip")
	var polygon := MinimapProjection.map_polygon(Vector2i(24, 24), center, scale)
	assert_equal(polygon.size(), 4, "map polygon has four isometric corners")
	assert_true(MinimapProjection.contains_world(MinimapProjection.world_to_minimap(Vector2(12, 12), center, scale), Vector2i(24, 24), center, scale), "map center is interactive")
	assert_true(not MinimapProjection.contains_world(center + Vector2(200, 0), Vector2i(24, 24), center, scale), "outside point is rejected")

	if failures.is_empty():
		print("I10-005 minimap projection tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_vector(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
