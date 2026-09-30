extends SceneTree

const RandomMapWater := preload("res://scripts/random_map_water.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_distance_banded_water_and_walkable_sandbars()
	_test_deterministic_water_detail()
	_finish("Random map water depth and sandbar tests passed")


func _test_distance_banded_water_and_walkable_sandbars() -> void:
	var size := Vector2i(30, 20)
	var terrain := _coastal_fixture(size)
	var summary := RandomMapWater.apply(terrain, size, 41721, "coastal")
	var shallow_cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			var terrain_id := int(terrain[y * size.x + x])
			if x in [7, 8]:
				assert_true(terrain_id in [1, 4], "first two water bands remain coastal or walkable shallow")
			if terrain_id == 4:
				shallow_cells.append(Vector2i(x, y))
	assert_true(int(summary.get("deep_water_cells", 0)) > 0, "offshore cells become deep water")
	assert_true(not shallow_cells.is_empty(), "coast receives at least one walkable sandbar")
	assert_true(bool(summary.get("sandbar_count", 0) > 0), "sandbar summary publishes generated groups")
	assert_true(TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(4)), "land units can traverse source shallows")
	assert_true(TerrainRules.is_water_navigable(TerrainRules.logical_for_terrain_id(4)), "ships can traverse source shallows")
	for shallow in shallow_cells:
		assert_true(_connected_to_land(shallow, terrain, size), "every shallow component remains attached to the coast")
	for anchor in summary["sandbar_anchors"]:
		var lateral_neighbors := 0
		for dy in [-1, 1]:
			if terrain[(anchor.y + dy) * size.x + anchor.x] == 4: lateral_neighbors += 1
		assert_true(lateral_neighbors == 2, "straight coastline creates broad rounded shoals instead of one-cell rays")


func _test_deterministic_water_detail() -> void:
	var size := Vector2i(34, 22)
	var first := _coastal_fixture(size)
	var second := first.duplicate()
	var changed := first.duplicate()
	var first_summary := RandomMapWater.apply(first, size, 7919, "coastal")
	var second_summary := RandomMapWater.apply(second, size, 7919, "coastal")
	RandomMapWater.apply(changed, size, 7920, "coastal")
	assert_equal(first, second, "same seed produces identical depth bands and sandbars")
	assert_equal(first_summary, second_summary, "same seed publishes identical water metadata")
	assert_true(first != changed, "different seed changes offshore contours or sandbar placement")


func _coastal_fixture(size: Vector2i) -> Array[int]:
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			terrain[y * size.x + x] = 0 if x < 7 else 1
	return terrain


func _connected_to_land(origin: Vector2i, terrain: Array[int], size: Vector2i) -> bool:
	var queue: Array[Vector2i] = [origin]
	var visited := {origin: true}
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		cursor += 1
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.y:
				continue
			var terrain_id := int(terrain[neighbor.y * size.x + neighbor.x])
			if terrain_id not in TerrainRules.WATER_TERRAIN_IDS:
				return true
			if terrain_id == 4 and not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return false


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
