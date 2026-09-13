extends SceneTree

const FacingConvention := preload("res://scripts/facing_convention.gd")
const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_world_to_slp_compass()
	test_screen_round_trip()
	test_stored_source_and_mirror_table()

	if failures.is_empty():
		print("I5-001 facing convention tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_world_to_slp_compass() -> void:
	var expected := {
		Vector2(1, 1): 0,
		Vector2(0, 1): 1,
		Vector2(-1, 1): 2,
		Vector2(-1, 0): 3,
		Vector2(-1, -1): 4,
		Vector2(0, -1): 5,
		Vector2(1, -1): 6,
		Vector2(1, 0): 7,
	}
	for world_direction in expected:
		assert_equal(FacingConvention.logical_for_world(world_direction), expected[world_direction], "world %s maps to %s" % [world_direction, FacingConvention.LABELS[expected[world_direction]]])


func test_screen_round_trip() -> void:
	for facing in range(8):
		assert_equal(FacingConvention.logical_for_screen(FacingConvention.screen_vector(facing)), facing, "screen vector round trip %d" % facing)


func test_stored_source_and_mirror_table() -> void:
	var descriptor = GraphicDescriptor.new("real_ror_8_angle", {"frames_per_angle": 15, "angle_count": 8, "mirroring_mode": 6}, 75, true)
	var expected_sources := [0, 1, 2, 3, 4, 3, 2, 1]
	for facing in range(8):
		var resolved: Dictionary = descriptor.resolve(facing, 0.0, 75)
		assert_equal(resolved["source_direction"], expected_sources[facing], "source block for %s" % FacingConvention.LABELS[facing])
		assert_equal(resolved["mirrored"], facing >= 5, "mirror flag for %s" % FacingConvention.LABELS[facing])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
