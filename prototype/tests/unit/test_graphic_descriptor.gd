extends SceneTree

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_slp_direction_mapping()
	test_forward_frame_order_and_looping()
	test_hotspots_and_events()

	if failures.is_empty():
		print("R-001 graphic descriptor tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_slp_direction_mapping() -> void:
	var spec := {"frames_per_angle": 15, "angle_count": 8, "frame_rate": 0.1, "mirroring_mode": 6}
	var descriptor = GraphicDescriptor.new("clubman_attack", spec, 75, true)
	assert_equal(descriptor.logical_angle_count, 8, "logical directions")
	assert_equal(descriptor.stored_angle_count, 5, "stored SLP directions")
	assert_equal(descriptor.slp_direction_order, [0, 45, 90, 135, 180, 225, 270, 315], "clockwise SLP order")
	var expected_sources := [0, 1, 2, 3, 4, 3, 2, 1]
	for facing in range(8):
		var resolved: Dictionary = descriptor.resolve(facing, 0.0, 75)
		assert_equal(resolved["source_direction"], expected_sources[facing], "source direction %d" % facing)
		assert_equal(resolved["mirrored"], facing > 4, "mirror direction %d" % facing)


func test_forward_frame_order_and_looping() -> void:
	var looping = GraphicDescriptor.new("walk", {"frames_per_angle": 4, "angle_count": 1, "frame_rate": 0.1}, 4, true)
	assert_equal(looping.resolve(0, 0.0, 4)["animation_frame"], 0, "animation starts at first frame")
	assert_equal(looping.resolve(0, 0.11, 4)["animation_frame"], 1, "animation advances forward")
	assert_equal(looping.resolve(0, 0.41, 4)["animation_frame"], 0, "loop returns to first frame")
	var one_shot = GraphicDescriptor.new("death", {"frames_per_angle": 4, "angle_count": 1, "frame_rate": 0.1}, 4, false)
	assert_equal(one_shot.resolve(0, 2.0, 4)["animation_frame"], 3, "one-shot clamps to final frame")


func test_hotspots_and_events() -> void:
	var descriptor = GraphicDescriptor.new("attack", {
		"frames_per_angle": 2,
		"angle_count": 1,
		"frame_rate": 0.1,
		"damage_frame": 1,
		"deltas": [{"graphic_id": 12}],
	}, 2, true)
	descriptor.set_hotspots([Vector2(3, 7), Vector2(4, 8)])
	assert_equal(descriptor.hotspot_for(1, Vector2.ZERO), Vector2(4, 8), "per-frame hotspot")
	assert_equal(descriptor.frame_events["damage_frame"], 1, "gameplay action frame")
	assert_equal(descriptor.deltas.size(), 1, "graphic deltas")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
