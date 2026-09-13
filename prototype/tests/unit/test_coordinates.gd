extends SceneTree

const Coordinates := preload("res://scripts/coordinates.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_world_screen_round_trip()
	test_tile_conversion()
	test_world_clamping()

	if failures.is_empty():
		print("A-001 coordinate tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_world_screen_round_trip() -> void:
	var samples: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(23.0, 23.0),
		Vector2(0.25, 23.75),
		Vector2(-3.5, 2.125),
		Vector2(12.75, -4.25),
	]
	var zoom_values: Array[float] = [0.72, 1.0, 1.12, 2.4]
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(640.0, 180.0),
		Vector2(-125.5, 77.25),
	]

	for world in samples:
		for zoom in zoom_values:
			for offset in offsets:
				var screen := Coordinates.world_to_screen(world, zoom, offset)
				var restored := Coordinates.screen_to_world(screen, zoom, offset)
				assert_vector_close(restored, world, "round trip world=%s zoom=%s offset=%s" % [world, zoom, offset])


func test_tile_conversion() -> void:
	assert_equal(Coordinates.world_to_tile(Vector2(4.9, 7.1)), Vector2i(4, 7), "positive world_to_tile")
	assert_equal(Coordinates.world_to_tile(Vector2(-0.1, -1.01)), Vector2i(-1, -2), "negative world_to_tile")
	assert_vector_close(Coordinates.tile_to_world(Vector2i(-3, 8)), Vector2(-3.0, 8.0), "tile_to_world")

	var wrapped_world = Coordinates.WorldPosition.new(Vector2(-0.1, 3.9))
	assert_equal(wrapped_world.to_tile(), Vector2i(-1, 3), "WorldPosition.to_tile")
	var wrapped_tile = Coordinates.TilePosition.new(Vector2i(5, -2))
	assert_vector_close(wrapped_tile.to_world().to_vector2(), Vector2(5.0, -2.0), "TilePosition.to_world")


func test_world_clamping() -> void:
	var map_size := Vector2i(24, 18)
	assert_vector_close(Coordinates.clamp_world(Vector2(-10.0, 99.0), map_size), Vector2(0.5, 17.5), "outside map clamp")
	assert_vector_close(Coordinates.clamp_world(Vector2(4.25, 6.75), map_size), Vector2(4.25, 6.75), "inside map clamp")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
