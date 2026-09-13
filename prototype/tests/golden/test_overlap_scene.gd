extends SceneTree

const RenderItem := preload("res://scripts/render_item.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const Coordinates := preload("res://scripts/coordinates.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.add_building(100, "town_center", Vector2(22.0, 15.0))
	for index in range(6):
		world.add_resource("tree" if index < 4 else "berries", Vector2(8.0 + index, 10.0 + index % 2), 75)
	var origins: Dictionary = {}
	for index in range(30):
		var kind := "archer" if index % 3 == 0 else "clubman"
		var position := Vector2(11.5 + float(index % 6) * 0.42, 11.5 + float(index / 6) * 0.42)
		var unit: Dictionary = world.add_unit(1 if index < 29 else 2, kind, position, false)
		origins[int(unit["id"])] = position
	world.configure_demo_elevation(Vector2i(13, 13), 4, 2)
	world.spawn_projectile(world.get_units()[0], world.get_units()[29])

	var renderer = RenderWorld.new()
	var baseline: Array = []
	var directions := [
		Vector2(0, -1), Vector2(1, -1).normalized(), Vector2(1, 0), Vector2(1, 1).normalized(),
		Vector2(0, 1), Vector2(-1, 1).normalized(), Vector2(-1, 0), Vector2(-1, -1).normalized(),
	]
	for direction in directions:
		for unit in world.get_units():
			var origin: Vector2 = origins[int(unit["id"])]
			unit["previous_pos"] = origin - direction * 0.15
			unit["pos"] = origin + direction * 0.15
		world.sync_all_components()
		var first: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return Coordinates.iso_raw(position), 0.5, Callable(self, "fake_frame_info"))
		var second: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return Coordinates.iso_raw(position), 0.5, Callable(self, "fake_frame_info"))
		assert_equal(render_signature(first), render_signature(second), "repeated render order is stable for direction %s" % direction)
		assert_sorted(first)
		if baseline.is_empty():
			baseline = render_signature(first)
		else:
			assert_equal(render_signature(first), baseline, "symmetric interpolation does not flicker for direction %s" % direction)

	var items: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position, 0.5, Callable(self, "fake_frame_info"))
	assert_equal(items.filter(func(item): return item["kind"] == "unit").size(), 30, "overlap scene contains 30 units")
	assert_equal(items.filter(func(item): return item["kind"] == "shadow").size(), 30, "every living unit has a separate shadow")
	assert_equal(items.filter(func(item): return item["kind"] == "projectile").size(), 1, "overlap scene contains a real projectile")
	assert_true(items.any(func(item): return float(item["elevation"]) > 0.0), "overlap scene includes elevated objects")

	if failures.is_empty():
		print("G-007 overlap golden scenario passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func fake_frame_info(_kind: String, _data: Variant) -> Dictionary:
	return {"frame_index": 0, "hotspot": Vector2(8, 20), "mirrored": false}


func render_signature(items: Array) -> Array:
	var result: Array = []
	for item in items:
		result.append("%s:%d:%.5f:%.5f" % [item["kind"], item["stable_id"], item["screen_y"], item["elevation"]])
	return result


func assert_sorted(items: Array) -> void:
	for index in range(1, items.size()):
		assert_true(not RenderItem.less(items[index], items[index - 1]), "render order remains sorted at %d" % index)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
