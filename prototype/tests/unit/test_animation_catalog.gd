extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_each_loaded_animation_has_own_descriptor()
	test_ambient_birds_use_directional_flight_graphics()

	if failures.is_empty():
		print("R-003 animation catalog audit passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_each_loaded_animation_has_own_descriptor() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	for texture_key in catalog.unit_presentation_keys():
		for animation_state in catalog.unit_animation_states(texture_key):
			var frames: Array = catalog.unit_animation_frames(texture_key, animation_state)
			var descriptor = catalog.get_graphic_descriptor(texture_key, animation_state)
			assert_true(descriptor != null, "%s/%s descriptor" % [texture_key, animation_state])
			if descriptor == null:
				continue
			assert_true(descriptor.frames_per_angle > 0, "%s/%s frame count" % [texture_key, animation_state])
			assert_true(descriptor.logical_angle_count > 0, "%s/%s direction count" % [texture_key, animation_state])
			if animation_state in ["attack", "death", "corpse"]:
				assert_true(not descriptor.loop, "%s/%s is a one-shot clip" % [texture_key, animation_state])
			for facing in range(descriptor.logical_angle_count):
				var resolved: Dictionary = descriptor.resolve(facing, 0.0, frames.size())
				assert_true(resolved["frame_index"] >= 0 and resolved["frame_index"] < frames.size(), "%s/%s facing %d frame bounds" % [texture_key, animation_state, facing])


func test_ambient_birds_use_directional_flight_graphics() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var eagle := {
		"id": -200001,
		"scenario_object_id": 17,
		"source_unit_id": 96,
		"graphic_id": 485,
		"asset_name": "graphic_485",
		"presentation_layer": "ambient_actor",
		"animated": true,
		"movement_direction": Vector2(1.0, 0.0),
	}
	var frame: Dictionary = catalog.environment_frame_info(eagle, 0.25)
	assert_true(not frame.is_empty(), "eagle flight frame is available")
	assert_true(int(frame.get("graphic_id", -1)) == 483, "eagle uses the source movement graphic instead of rotating idle directions")
	assert_true(String(frame.get("asset_name", "")) == "graphic_483", "eagle flight asset identity is retained")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("failed: %s" % context)
