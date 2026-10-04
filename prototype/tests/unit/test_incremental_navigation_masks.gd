extends SceneTree

const Grid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []

func _initialize() -> void:
	check(ClassDB.class_exists("RoRPathKernel"), "native path kernel is packaged")
	if not failures.is_empty(): finish(); return
	var grid := Grid.new(Vector2i(400, 400))
	grid.configure_terrain(func(_cell): return "land")
	var finder := Pathfinder.new(grid)
	var fallback := Pathfinder.new(grid)
	fallback.set_native_enabled(false)
	var probe := Probe.new()
	finder.set_performance_probe(probe)
	var start := Vector2i(180, 180)
	var goal := Vector2i(190, 180)
	finder.find_cell_path(start, goal)
	check(int(probe.counters.get("navigation.native_mask_rebuilds", 0)) == 1, "initial 400x400 mask is built once")
	probe.clear()
	for iteration in range(12):
		var cell := Vector2i(185, 180 + iteration % 3)
		grid.occupy([cell], "building", iteration + 1)
		check(finder.find_cell_path(start, goal) == fallback.find_cell_path(start, goal), "local obstruction retains reference routing")
		grid.release_occupant([cell], "building", iteration + 1)
		check(finder.find_cell_path(start, goal) == fallback.find_cell_path(start, goal), "released obstruction restores reference routing")
	check(int(probe.counters.get("navigation.native_mask_rebuilds", 0)) == 0, "24 local changes never rescan the full giant map")
	check(int(probe.counters.get("navigation.native_mask_updated_cells", 0)) > 0 and int(probe.counters.get("navigation.native_mask_updated_cells", 0)) <= 24, "lazy cache reuse patches only changed cells without forcing every revision to search")
	check(fallback.fallback_components.is_empty(), "short reference routes never require a full 400x400 component index")
	grid.set_terrain(Vector2i(185, 180), "water")
	check(finder.find_cell_path(start, goal) == fallback.find_cell_path(start, goal), "unbounded terrain change safely rebuilds mask")
	check(int(probe.counters.get("navigation.native_mask_rebuilds", 0)) == 1, "full topology change still invalidates mask")
	for iteration in range(120): grid.occupy([Vector2i(20 + iteration, 20)], "building", 1000 + iteration)
	finder.find_cell_path(start, goal)
	check(int(probe.counters.get("navigation.native_mask_rebuilds", 0)) == 2, "expired delta journal falls back to full rebuild")
	var kernel = finder.native_kernels["land:-1"]
	var revision: int = kernel.get_revision()
	check(not kernel.update_walkable(revision + 1, PackedInt32Array([0, 160000]), PackedByteArray([0, 0])), "invalid native patch is rejected atomically")
	check(int(kernel.get_revision()) == revision, "invalid patch cannot advance revision")
	var world := World.new(Vector2i(8, 8))
	world.map_terrain_ids[Vector2i(4, 4)] = 1000
	var before: int = world.terrain_revision
	var tree: Dictionary = world.add_resource("tree", Vector2(4.5, 4.5), 100)
	check(world.terrain_revision == before, "tree on imported ground does not invalidate terrain")
	world.unregister_forest_resource(tree)
	check(world.terrain_revision == before, "felling tree on imported ground keeps terrain and fog caches")
	world.map_terrain_ids[Vector2i(5, 5)] = 0
	before = world.terrain_revision
	var old_tree: Dictionary = world.add_resource("tree", Vector2(5.5, 5.5), 100)
	check(world.terrain_revision > before, "legacy forest-floor change invalidates terrain")
	before = world.terrain_revision
	world.unregister_forest_resource(old_tree)
	check(world.terrain_revision > before, "restoring legacy grass invalidates terrain")
	finish()

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)

func finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Giant-map incremental navigation masks and forest surface invalidation passed")
	quit(0 if failures.is_empty() else 1)
