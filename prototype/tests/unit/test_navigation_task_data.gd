extends SceneTree

const Grid := preload("res://scripts/navigation_grid.gd")
const KnowledgeGrid := preload("res://scripts/navigation_knowledge_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const NavigationData := preload("res://scripts/navigation_task_data.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []

func _initialize() -> void:
	test_incremental_publications()
	test_full_invalidation_and_source_identity()
	test_knowledge_and_serialization()
	for failure in failures: push_error(failure)
	print("Navigation task publications: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func test_incremental_publications() -> void:
	var grid = Grid.new(Vector2i(64, 64))
	grid.configure_terrain(func(_cell): return "grass")
	grid.occupy([Vector2i(9, 9)], "resource", 10)
	var finder = Pathfinder.new(grid)
	var first: Dictionary = finder.detached_task_topology()
	check(is_same(first, finder.detached_task_topology()), "unchanged revision reuses publication")
	grid.occupy([Vector2i(10, 9)], "building", 20)
	var second: Dictionary = finder.detached_task_topology()
	for field in ["terrain_cells", "terrain_ids", "elevation_cells", "slope_cells", "terrain_restrictions"]:
		check(is_same(first[field], second[field]), "occupancy changes share unchanged field: " + field)
	check(not first["occupied_cells"].has(Vector2i(10, 9)) and second["occupied_cells"].has(Vector2i(10, 9)), "retained worker input cannot observe a new building")
	grid.occupy([Vector2i(9, 9)], "resource", 11)
	var third: Dictionary = finder.detached_task_topology()
	check(is_same(second["occupied_cells"], third["occupied_cells"]), "a second occupant does not copy unchanged blockage")
	grid.release_occupant([Vector2i(9, 9)], "resource", 10)
	check(finder.detached_task_topology()["occupied_cells"].has(Vector2i(9, 9)), "remaining occupant still blocks")
	grid.release_occupant([Vector2i(9, 9)], "resource", 11)
	var fourth: Dictionary = finder.detached_task_topology()
	check(not fourth["occupied_cells"].has(Vector2i(9, 9)) and first["occupied_cells"].has(Vector2i(9, 9)), "removing last occupant only changes new publication")
	grid.set_terrain(Vector2i(3, 3), "water")
	grid.set_terrain_id(Vector2i(4, 4), 7)
	grid.set_elevation(Vector2i(5, 5), 2, true)
	var fifth: Dictionary = finder.detached_task_topology()
	check(fifth["terrain_cells"][Vector2i(3, 3)] == "water" and first["terrain_cells"][Vector2i(3, 3)] == "grass", "terrain patch preserves old surface")
	check(fifth["terrain_ids"][Vector2i(4, 4)] == 7, "terrain ID patch is present")
	check(fifth["elevation_cells"][Vector2i(5, 5)] == 2 and fifth["slope_cells"][Vector2i(5, 5)], "elevation and slope patches are present")
	var detached = NavigationData.create_grid(fifth)
	for domain in ["land", "water"]:
		for y in range(grid.size.y):
			for x in range(grid.size.x):
				check(grid.is_walkable_for(Vector2i(x, y), domain) == detached.is_walkable_for(Vector2i(x, y), domain), "worker walkability matches owner")
	# Saturating the identity registries must not turn map capture into a recursive
	# scan or copy. The engine's key/value types certify immutable scalar leaves.
	for index in range(Data.MAX_SEALED_ROOTS + Data.MAX_IMMUTABLE_ROOTS + 2):
		Data.seal({"transient": index})
		Data.freeze_detached({"transient": index})
	for field in NavigationData.CELL_FIELDS:
		check(Data.is_trusted_immutable(fifth[field]), "typed field remains trusted after eviction: " + field)
		check(is_same(Data.capture(fifth[field]), fifth[field]), "capture retains immutable field: " + field)

func test_full_invalidation_and_source_identity() -> void:
	var grid = Grid.new(Vector2i(12, 12))
	grid.configure_terrain(func(_cell): return "grass")
	var finder = Pathfinder.new(grid)
	var first: Dictionary = finder.detached_task_topology()
	grid.configure_terrain(func(_cell): return "water")
	var water: Dictionary = finder.detached_task_topology()
	check(water["terrain_cells"][Vector2i(0, 0)] == "water", "bulk invalidation rebuilds fields")
	check(first["terrain_cells"][Vector2i(0, 0)] == "grass", "bulk invalidation preserves retained input")
	# A same-revision epoch reset must not return the old publication.
	grid.terrain_cells[Vector2i(0, 0)] = "grass"
	grid.cache_epoch += 1
	check(finder.detached_task_topology()["terrain_cells"][Vector2i(0, 0)] == "grass", "epoch reset invalidates publication")
	var replacement = Grid.new(grid.size)
	replacement.configure_terrain(func(_cell): return "grass")
	replacement.revision = grid.revision
	finder.grid = replacement
	check(finder.detached_task_topology()["terrain_cells"][Vector2i(1, 1)] == "grass", "equal revision of different source cannot reuse map")
	var before: Dictionary = finder.detached_task_topology()
	for index in range(130): replacement.set_terrain_id(Vector2i(index % 12, index / 12), index + 100)
	var expired: Dictionary = finder.detached_task_topology()
	check(expired["terrain_ids"][Vector2i(0, 0)] == 100 and before["terrain_ids"][Vector2i(0, 0)] != 100, "expired change journal falls back to current full map")

func test_knowledge_and_serialization() -> void:
	var grid = KnowledgeGrid.new(Vector2i(10, 10))
	grid.terrain_cells[Vector2i(2, 2)] = "water"
	grid.terrain_ids[Vector2i(2, 2)] = 1
	grid.learned[22] = 1
	var snapshot := NavigationData.capture(grid)
	var decoded: Dictionary = bytes_to_var(var_to_bytes(snapshot))
	var restored = NavigationData.create_grid(decoded)
	check(restored.is_walkable_for(Vector2i(1, 1), "land") and not restored.is_walkable_for(Vector2i(2, 2), "land"), "save DTO retains unknown-cell and remembered terrain behavior")
	grid.learned[22] = 0
	check(restored.learned[22] == 1, "knowledge flags are detached")
	var unsafe: Dictionary[Vector2i, Object] = {Vector2i.ZERO: RefCounted.new()}
	unsafe.make_read_only()
	check(not Data.is_detached(unsafe), "typed Object dictionary must not bypass isolation")
	var nested: Dictionary[Vector2i, Array] = {Vector2i.ZERO: [RefCounted.new()]}
	nested.make_read_only()
	check(not Data.is_detached(nested), "typed containers must not bypass nested validation")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
