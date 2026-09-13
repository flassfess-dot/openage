extends SceneTree

const SelectionResolver := preload("res://scripts/selection_resolver.gd")
const SpatialHash := preload("res://scripts/spatial_hash.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_topmost_is_stable()
	test_texture_alpha_hit_and_mirror()
	test_spatial_candidates()

	if failures.is_empty():
		print("C-002 selection resolver tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_topmost_is_stable() -> void:
	var lower := {"id": 3}
	var upper := {"id": 9}
	var candidates := [
		{"entity": lower, "sort_y": 125.0, "id": 3},
		{"entity": upper, "sort_y": 125.0, "id": 9},
		{"entity": {"id": 1}, "sort_y": 100.0, "id": 1},
	]
	for attempt in range(100):
		assert_equal(SelectionResolver.topmost(candidates)["id"], 9, "stable topmost attempt %d" % attempt)


func test_texture_alpha_hit_and_mirror() -> void:
	var texture: Texture2D = load("res://assets/generated/villager_idle_00.png")
	var image := texture.get_image()
	var opaque_pixel := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				opaque_pixel = Vector2i(x, y)
				break
		if opaque_pixel.x >= 0:
			break
	var anchor := Vector2(200, 160)
	var hotspot := Vector2(11, 32)
	var source_center := Vector2(opaque_pixel) + Vector2(0.25, 0.25)
	var normal_mouse := anchor + source_center - hotspot
	var mirrored_mouse := anchor + Vector2(hotspot.x - source_center.x, source_center.y - hotspot.y)
	assert_equal(SelectionResolver.texture_hit(normal_mouse, anchor, 1.0, texture, hotspot, false), true, "opaque normal pixel")
	assert_equal(SelectionResolver.texture_hit(mirrored_mouse, anchor, 1.0, texture, hotspot, true), true, "opaque mirrored pixel")
	assert_equal(SelectionResolver.texture_hit(anchor + Vector2(500, 500), anchor, 1.0, texture, hotspot, false), false, "outside texture")


func test_spatial_candidates() -> void:
	var index = SpatialHash.new(2.0)
	var near_unit := {"id": 4}
	var far_unit := {"id": 8}
	index.insert(near_unit, Vector2(4.0, 4.0), 0.3, "unit")
	index.insert(far_unit, Vector2(12.0, 12.0), 0.3, "unit")
	index.insert({"id": 10}, Vector2(4.1, 4.1), 0.4, "resource")
	var result: Array = index.query_circle(Vector2(4.0, 4.0), 1.0, "unit")
	assert_equal(result.size(), 1, "spatial unit candidate count")
	assert_equal(result[0]["id"], 4, "spatial unit candidate")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
