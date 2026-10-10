extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	check(ClassDB.class_exists("RoRPathKernel"), "native path kernel is installed")
	var kernel = ClassDB.instantiate("RoRPathKernel")
	check(kernel.has_method("group_points_by_component"), "rebuilt native module exposes region grouping")
	if not kernel.has_method("group_points_by_component"): quit(1); return
	var mask := PackedByteArray()
	mask.resize(32 * 32)
	mask.fill(1)
	for y in range(32): mask[y * 32 + 16] = 0
	kernel.configure(32, 32, 1, mask)
	var points: Array[Vector2] = [Vector2(-1.5, 1.5), Vector2(2.5, 2.5), Vector2(20.5, 2.5), Vector2(2.5, 4.5), Vector2(16.5, 2.5), Vector2(20.5, 4.5), Vector2(32.5, 3.5)]
	for radius in [0.0, 0.3, 0.6]:
		var expected := {}
		for point in points:
			var region: int = kernel.component_id(Vector2i(point), radius)
			if region < 0: continue
			if not expected.has(region): expected[region] = []
			expected[region].append(point)
		var grouped: Dictionary = kernel.group_points_by_component(points, radius)
		check(grouped == expected, "grouping preserves exact region IDs, bounds, clearance and point order")
		var saved := grouped.duplicate(true)
		kernel.group_points_by_component([Vector2(5.5, 5.5)] as Array[Vector2], radius)
		check(grouped == saved, "successive queries cannot mutate old groups")
	for failure in failures: push_error(failure)
	print("Native region grouping: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
