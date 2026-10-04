extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Finder := preload("res://scripts/pathfinder.gd")
const Probe := preload("res://scripts/performance_probe.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var expected := []
	for native in [false, true]:
		var grid = Grid.new(Vector2i(24, 16))
		grid.configure_terrain(func(cell): return "water" if cell.x == 12 else "grass")
		var finder = Finder.new(grid)
		finder.set_native_enabled(native)
		var probe := Probe.new()
		finder.set_performance_probe(probe)
		check(not finder.cells_connected(Vector2i(2, 5), Vector2i(20, 5)), "separate islands are disconnected")
		check(finder.find_cell_path(Vector2i(2, 5), Vector2i(20, 5)).is_empty(), "unreachable route fails immediately")
		check(int(probe.counters.get("navigation.expanded_nodes", 0)) == 0, "unreachable search expands no A* nodes")
		var labels := [finder.component_id(Vector2i(2, 5)), finder.component_id(Vector2i(20, 5))]
		if not native: expected = labels
		else: check(labels == expected, "native and fallback region IDs are identical")
		grid.set_terrain(Vector2i(12, 8), "grass")
		check(finder.cells_connected(Vector2i(2, 5), Vector2i(20, 5), "land", -1, 0.3), "opened bridge connects small units")
		check(not finder.cells_connected(Vector2i(2, 5), Vector2i(20, 5), "land", -1, 0.75), "clearance rejects a bridge narrower than the unit")
		check(not finder.find_cell_path(Vector2i(2, 5), Vector2i(20, 5), "land", -1, 0.3).is_empty(), "topology edit invalidates failed routes and region labels")
		grid.occupy([Vector2i(2, 5)], "building", 50)
		check(finder.component_id(Vector2i(2, 5)) == -1, "occupied origin has no component")
		check(finder.cells_connected(Vector2i(2, 5), Vector2i(20, 5)), "unit can escape an occupied origin")
		check(not finder.find_cell_path(Vector2i(2, 5), Vector2i(20, 5)).is_empty(), "blocked-origin escape preserves A* behavior")
		var corner = Grid.new(Vector2i(2, 2))
		corner.configure_terrain(func(cell): return "water" if cell.x != cell.y else "grass")
		var diagonal = Finder.new(corner)
		diagonal.set_native_enabled(native)
		check(not diagonal.cells_connected(Vector2i.ZERO, Vector2i.ONE), "components never join across a blocked diagonal")
	finish()
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	print("Navigation components: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
