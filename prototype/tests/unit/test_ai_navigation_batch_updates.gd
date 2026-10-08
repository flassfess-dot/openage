extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Knowledge := preload("res://scripts/ai_navigation_knowledge.gd")
var failures: Array[String] = []

func _initialize() -> void:
	test_dense_changes_merge_once()
	test_exploration_and_obstructions_match_fresh_snapshot()
	for failure in failures:
		push_error(failure)
	print("AI navigation batch updates: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func test_dense_changes_merge_once() -> void:
	var knowledge := Knowledge.new()
	var entry: Dictionary = knowledge._new_entry(Vector2i(200, 100))
	var original: Array[Vector2] = []
	var expected: Array[Vector2] = []
	for index in range(20000):
		var point := Vector2(index % 200, index / 200) + Vector2(0.5, 0.5)
		if index % 4 == 0:
			original.append(point)
		if index % 4 in [1, 2]:
			expected.append(point)
	original.make_read_only()
	entry["buckets"]["land"] = original
	# Adjacent discoveries share an old insertion slot; deletion can use that
	# same slot too. This catches lost/duplicated points during a batch merge.
	for index in range(20000):
		var point := Vector2(index % 200, index / 200) + Vector2(0.5, 0.5)
		knowledge._set_bucket(entry, "land", index, point, index % 4 in [1, 2])
	check(is_same(entry["buckets"]["land"], original), "patch capture leaves an in-flight observation unchanged")
	knowledge._apply_bucket_changes(entry)
	check(entry["buckets"]["land"] == expected, "dense mixed additions/deletions preserve row-major points exactly")
	check(original.size() == 5000 and original[0] == Vector2(0.5, 0.5), "published old points remain intact")
	check(knowledge.last_bucket_merged_points == expected.size(), "a dense update emits each output point only once")
	check(knowledge.last_bucket_patch_count == 15000, "dense fixture actually exercises thousands of edits")
	check(entry["bucket_changes"].is_empty(), "applied patches are released after publication")
	var merged: Array = entry["buckets"]["land"]
	knowledge._set_bucket(entry, "land", 0, Vector2(0.5, 0.5), true)
	knowledge._set_bucket(entry, "land", 0, Vector2(0.5, 0.5), false)
	knowledge._apply_bucket_changes(entry)
	check(is_same(entry["buckets"]["land"], merged), "cancelled patches preserve the unchanged bucket identity")

func test_exploration_and_obstructions_match_fresh_snapshot() -> void:
	var world := World.new(Vector2i(40, 24))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.add_unit(1, "villager", Vector2(4.5, 4.5), false)
	var fog = world.get_fog_of_war()
	fog.ensure_player(1)
	for y in range(24):
		for x in range(20):
			fog.reveal_explored_cell(1, Vector2i(x, y))
	var knowledge := Knowledge.new()
	var first := knowledge.snapshot(world, fog, 1)
	var preserved := first.duplicate(true)
	var unchanged := knowledge.snapshot(world, fog, 1)
	check(knowledge.last_bucket_merged_points == 0, "unchanged decisions copy no navigation points")
	check(is_same(first["land"], unchanged["land"]), "unchanged decisions share frozen point buckets")
	for x in range(20, 30):
		for y in range(24):
			fog.reveal_explored_cell(1, Vector2i(x, y))
	var occupied: Array[Vector2i] = []
	for y in range(0, 24, 2):
		occupied.append(Vector2i(10, y))
		occupied.append(Vector2i(22, y))
	world.navigation_grid.occupy(occupied, "static_obstruction", 90)
	var updated := knowledge.snapshot(world, fog, 1)
	var reference := Knowledge.new()
	check(updated == reference.snapshot(world, fog, 1), "batched exploration, frontier and occupancy changes match a fresh navigation projection")
	check(first == preserved, "later discoveries and blockers cannot modify earlier observations")
	var output_points := 0
	for name in Knowledge.BUCKET_NAMES:
		output_points += knowledge.entries[1]["buckets"][name].size()
	check(knowledge.last_bucket_merged_points <= output_points, "all dirty buckets are merged once regardless of discovery count")
	for points in updated.get("frontier_by_region", {}).values():
		check(points.is_typed() and points.get_typed_builtin() == TYPE_VECTOR2 and points.is_read_only(), "region frontiers remain safely shareable without per-point revalidation")
	world.navigation_grid.release_occupant(occupied, "static_obstruction", 90)
	var reopened := knowledge.snapshot(world, fog, 1)
	check(reopened == Knowledge.new().snapshot(world, fog, 1), "removing a batch of obstructions restores exactly the reference navigation")
	world.task_coordinator.shutdown()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)