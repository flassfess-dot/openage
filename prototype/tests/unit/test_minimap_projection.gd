extends SceneTree

const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const MinimapTerrainRaster := preload("res://scripts/minimap_terrain_raster.gd")

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

	var rectangle := Rect2(Vector2.ZERO, Vector2(128, 96))
	var raster_center := Vector2(64, 6)
	var raster := MinimapTerrainRaster.build(Vector2i(8, 8), rectangle, raster_center, 8.0, func(cell: Vector2i): return 1 if cell.x < 4 else 0)
	var water := MinimapProjection.world_to_minimap(Vector2(2.5, 3.5), raster_center, 8.0)
	var land := MinimapProjection.world_to_minimap(Vector2(5.5, 3.5), raster_center, 8.0)
	assert_true(raster.get_pixelv(Vector2i(water)).is_equal_approx(MinimapTerrainRaster.color_for_terrain_id(1)), "minimap paints geography independent of fog")
	assert_true(raster.get_pixelv(Vector2i(land)).is_equal_approx(MinimapTerrainRaster.color_for_terrain_id(0)), "minimap distinguishes land from water")
	assert_true(raster.get_pixel(0, 0).a < 0.01, "outside the map diamond stays transparent")
	var samples := {"count": 0}
	MinimapTerrainRaster.build(Vector2i(1024, 1024), rectangle, raster_center, 0.0625, func(_cell: Vector2i):
		samples["count"] = int(samples["count"]) + 1
		return 0
	)
	assert_true(int(samples["count"]) > 0 and int(samples["count"]) <= 128 * 96, "supergiant minimap samples screen pixels, never every map cell")

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
