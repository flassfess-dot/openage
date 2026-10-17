extends SceneTree
var failures: Array[String] = []
func _initialize() -> void:
	var size := Vector2i(128, 128)
	var mask := PackedByteArray()
	mask.resize(size.x * size.y)
	mask.fill(1)
	var a := 10 * size.x + 10
	var b := 110 * size.x + 110
	mask[a] = 0
	mask[b] = 0
	var kernel = ClassDB.instantiate("RoRPathKernel")
	kernel.configure(size.x, size.y, 1, mask)
	kernel.component_id(Vector2i(4, 4), 0.3)
	var retained = kernel.create_search_context()
	var rebuilds: int = kernel.get_connectivity_rebuild_count()
	mask[a] = 1
	mask[b] = 1
	check(kernel.update_walkable(2, PackedInt32Array([a,b]), PackedByteArray([1,1])), "distant edits are accepted")
	check(kernel.cells_connected(Vector2i(10,10), Vector2i(110,110), 0.3), "newly open cells remain connected")
	check(kernel.get_connectivity_rebuild_count() == rebuilds, "independent distant edits do not flood the whole map")
	check(retained.component_id(Vector2i(10,10), 0.3) == -1, "retained context keeps its old mask and labels")
	# Two distant closures may jointly split a region; preserving labels then
	# requires the same conservative proof as a single local closure.
	for y in range(size.y): mask[y * size.x + 64] = 0
	kernel.configure(size.x, size.y, 3, mask)
	check(not kernel.cells_connected(Vector2i(10,64), Vector2i(110,64), 0.3), "closed wall initially separates the map")
	var before_merge: int = kernel.get_connectivity_rebuild_count()
	var bridges := PackedInt32Array([20 * size.x + 64, 100 * size.x + 64])
	for index in bridges: mask[index] = 1
	kernel.update_walkable(4, bridges, PackedByteArray([1,1]))
	check(kernel.cells_connected(Vector2i(10,64), Vector2i(110,64), 0.3), "two bridges initially connect the map")
	check(kernel.get_connectivity_rebuild_count() == before_merge, "openings merge old components without a full map flood")
	for index in bridges: mask[index] = 0
	kernel.update_walkable(5, bridges, PackedByteArray([0,0]))
	check(not kernel.cells_connected(Vector2i(10,64), Vector2i(110,64), 0.3), "joint distant closures correctly split connectivity")
	var line := PackedByteArray()
	line.resize(64)
	line.fill(0)
	for index in range(4): line[index] = 1
	var roots = ClassDB.instantiate("RoRPathKernel")
	roots.configure(8, 8, 1, line)
	roots.component_id(Vector2i(3,0), 0.3)
	roots.update_walkable(2, PackedInt32Array([0]), PackedByteArray([0]))
	roots.component_id(Vector2i(3,0), 0.3)
	roots.update_walkable(3, PackedInt32Array([1]), PackedByteArray([0]))
	roots.component_id(Vector2i(3,0), 0.3)
	roots.update_walkable(4, PackedInt32Array([0]), PackedByteArray([1]))
	check(not roots.cells_connected(Vector2i(0,0), Vector2i(3,0), 0.3), "reopening an old root cannot alias a remote component")
	var rng := RandomNumberGenerator.new()
	rng.seed = 41721
	for revision in range(6, 26):
		var indices := PackedInt32Array()
		var values := PackedByteArray()
		for edit in range(5):
			var index := rng.randi_range(0, mask.size() - 1)
			mask[index] = 1 - mask[index]
			indices.append(index)
			values.append(mask[index])
		kernel.update_walkable(revision, indices, values)
		var fresh = ClassDB.instantiate("RoRPathKernel")
		fresh.configure(size.x, size.y, revision, mask)
		for radius in [0.0, 0.3, 0.8]:
			for sample in range(20):
				var first := Vector2i(rng.randi_range(0,127), rng.randi_range(0,127))
				var second := Vector2i(rng.randi_range(0,127), rng.randi_range(0,127))
				check(kernel.cells_connected(first, second, radius) == fresh.cells_connected(first, second, radius), "patched connectivity matches a full flood")
				check(kernel.component_id(first, radius) == fresh.component_id(first, radius), "cached root IDs match a fresh flood after mixed edits")
	for failure in failures: push_error(failure)
	print("Sparse connectivity updates: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value and not failures.has(message): failures.append(message)
