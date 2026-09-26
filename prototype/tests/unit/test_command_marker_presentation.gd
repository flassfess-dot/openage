extends SceneTree

const CommandMarkerPresentation := preload("res://scripts/command_marker_presentation.gd")
const SourceCursorPresentation := preload("res://scripts/source_cursor_presentation.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var marker := CommandMarkerPresentation.new()
	marker.trigger(Vector2(7.5, 9.25))
	var wide: Dictionary = marker.snapshot()
	assert_equal(wide.get("world_position"), Vector2(7.5, 9.25), "marker stays anchored to accepted world target")
	assert_equal(wide.get("frame_index"), 1, "marker starts with the source wide-arrows frame")

	marker.advance(CommandMarkerPresentation.DEFAULT_DURATION * 0.5)
	var contracted: Dictionary = marker.snapshot()
	assert_equal(contracted.get("frame_index"), 4, "marker advances through source frames")
	assert_true(marker.active, "contracted phase remains visible before the duration boundary")

	marker.advance(CommandMarkerPresentation.DEFAULT_DURATION)
	assert_true(not marker.active, "marker expires without simulation state")
	assert_true(marker.snapshot().is_empty(), "expired marker has no drawable snapshot")

	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	for frame_index in range(1, 7):
		var texture: Texture2D = load("res://assets/generated/ror_command_marker_%02d.png" % frame_index)
		assert_true(texture != null, "source marker frame %d was imported" % frame_index)
		assert_equal(int(catalog.get_texture_metadata("ror_command_marker", frame_index).get("id", -1)), 50405, "marker frame provenance %d" % frame_index)
	for frame_index in range(7):
		var texture: Texture2D = load("res://assets/generated/ror_cursor_%02d.png" % frame_index)
		assert_true(texture != null, "source cursor frame %d was imported" % frame_index)
		assert_equal(int(catalog.get_texture_metadata("ror_cursor", frame_index).get("id", -1)), 51000, "cursor frame provenance %d" % frame_index)
	assert_equal(SourceCursorPresentation.frame_for_semantic("attack"), 4, "attack uses source sword cursor")
	assert_equal(SourceCursorPresentation.frame_for_semantic("gather"), 3, "gather uses source hand cursor")
	assert_equal(SourceCursorPresentation.frame_for_semantic("default"), 0, "default uses source pointer")

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
