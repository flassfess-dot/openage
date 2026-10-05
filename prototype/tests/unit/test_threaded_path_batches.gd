extends SceneTree
const Grid := preload("res://scripts/navigation_grid.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const Probe := preload("res://scripts/performance_probe.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func finish() -> void:
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var grid := Grid.new(Vector2i(24, 24))
	grid.configure_terrain(func(cell): return "water" if cell.x == 12 and cell.y != 10 else "grass")
	var planner := Pathfinder.new(grid)
	var coordinator := Coordinator.new()
	var requests: Array = []
	for endpoint in [Vector2(20.5, 20.5), Vector2(5.5, 6.5), Vector2(13.5, 10.5), Vector2(20.5, 2.5)]:
		requests.append({"start": Vector2(3.5, 3.5), "goal": endpoint, "domain": "land", "restriction": -1, "clearance": 0.3})
	var expected: Array = []
	for request in requests:
		expected.append(planner.find_path(request["start"], request["goal"], "land", -1, 0.3))
	planner.clear_cache()
	var probe := Probe.new()
	planner.set_performance_probe(probe)
	check(planner.find_paths_batch(requests, coordinator) == expected, "raw/smoothed endpoint order matches sequential queries")
	check(probe.sample_count("navigation.path_query") == requests.size(), "batch retains an observation for every path")
	check(int(probe.counters.get("navigation.path_queries", 0)) == requests.size(), "batch query counter is merged exactly once")
	check(planner.path_query_tick_microseconds() > 0, "batch contributes elapsed owner time to the tick")
	probe.clear()
	check(planner.find_paths_batch(requests, coordinator) == expected, "retained batch routes match original paths")
	check(probe.sample_count("navigation.path_query") == requests.size() and int(probe.counters.get("navigation.path_cache_hits", 0)) == requests.size(), "cached batch queries retain their observations and hit counts")
	coordinator.subsystem_enabled["navigation_paths"] = false
	check(planner.find_paths_batch(requests, coordinator) == expected, "disabled batch retains paths")
	if planner.uses_native_kernel():
		var kernel = planner._native_kernel_for("land", -1)
		var context = kernel.create_search_context()
		var old_path = context.find_cell_path(Vector2i(3, 3), Vector2i(20, 20), 0.3)
		kernel.update_walkable(grid.revision + 1, PackedInt32Array([10 * 24 + 12]), PackedByteArray([0]))
		check(context.find_cell_path(Vector2i(3, 3), Vector2i(20, 20), 0.3) == old_path, "native context retains isolated topology after owner patch")
	coordinator.shutdown()
	finish()
