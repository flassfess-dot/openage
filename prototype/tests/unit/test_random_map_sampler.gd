extends SceneTree

const RandomMapSampler := preload("res://scripts/random_map_sampler.gd")
const RandomMapZones := preload("res://scripts/random_map_zones.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_deterministic_minimum_distance_sampling()
	_test_zone_and_blocking_filters()
	_test_coastal_filter()
	_finish("Random map zone sampler tests passed")


func _test_deterministic_minimum_distance_sampling() -> void:
	var size := Vector2i(24, 24)
	var zones := _zones(size, RandomMapZones.ZONE_FRONTIER)
	var first := RandomMapSampler.sample_zone_cells(zones, size, [RandomMapZones.ZONE_FRONTIER], 18, 4.0, 41721)
	var second := RandomMapSampler.sample_zone_cells(zones, size, [RandomMapZones.ZONE_FRONTIER], 18, 4.0, 41721)
	var changed := RandomMapSampler.sample_zone_cells(zones, size, [RandomMapZones.ZONE_FRONTIER], 18, 4.0, 41722)
	assert_equal(first, second, "same seed produces identical anchors")
	assert_true(first != changed, "different seed changes anchor selection")
	assert_equal(first.size(), 18, "open fixture reaches its requested anchor budget")
	for first_index in range(first.size()):
		for second_index in range(first_index + 1, first.size()):
			assert_true(Vector2(first[first_index]).distance_to(Vector2(first[second_index])) + 0.0001 >= 4.0, "every anchor pair respects minimum distance")


func _test_zone_and_blocking_filters() -> void:
	var size := Vector2i(20, 20)
	var zones := _zones(size, RandomMapZones.ZONE_TERRITORY)
	var zone_ids: PackedInt32Array = zones["zone_ids"]
	for y in range(size.y):
		for x in range(10, size.x):
			zone_ids[y * size.x + x] = RandomMapZones.ZONE_CONTESTED
	var blocked := {Vector2i(12, 10): true}
	var existing: Array[Vector2i] = [Vector2i(15, 10)]
	var sampled := RandomMapSampler.sample_zone_cells(zones, size, [RandomMapZones.ZONE_CONTESTED], 10, 3.0, 99, blocked, existing)
	assert_true(sampled.all(func(cell): return cell.x >= 10), "sampler only uses requested strategic zones")
	assert_true(not sampled.has(Vector2i(12, 10)), "explicitly blocked cell is never sampled")
	assert_true(sampled.all(func(cell): return Vector2(cell).distance_to(Vector2(existing[0])) + 0.0001 >= 3.0), "new anchors respect existing anchor spacing")


func _test_coastal_filter() -> void:
	var size := Vector2i(18, 18)
	var zones := _zones(size, RandomMapZones.ZONE_FRONTIER)
	var coastal_mask: PackedByteArray = zones["coastal_land_mask"]
	for y in range(2, size.y - 2):
		coastal_mask[y * size.x + 3] = 1
	var sampled := RandomMapSampler.sample_zone_cells(zones, size, [RandomMapZones.ZONE_FRONTIER], 4, 2.5, 123, {}, [], {}, "coastal")
	assert_true(not sampled.is_empty(), "coastal fixture produces anchors")
	assert_true(sampled.all(func(cell): return cell.x == 3), "coastal mode only samples the published coast mask")


func _zones(size: Vector2i, default_zone: int) -> Dictionary:
	var zone_ids := PackedInt32Array()
	var coastal_mask := PackedByteArray()
	var start_distances := PackedInt32Array()
	zone_ids.resize(size.x * size.y)
	zone_ids.fill(default_zone)
	coastal_mask.resize(size.x * size.y)
	start_distances.resize(size.x * size.y)
	start_distances.fill(20)
	return {
		"zone_ids": zone_ids,
		"coastal_land_mask": coastal_mask,
		"nearest_start_distances": start_distances,
	}


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
