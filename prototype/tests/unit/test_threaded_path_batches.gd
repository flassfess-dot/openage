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
	test_saturated_batch_cache(planner, coordinator, requests, expected)
	coordinator.subsystem_enabled["navigation_paths"] = false
	check(planner.find_paths_batch(requests, coordinator) == expected, "disabled batch retains paths")
	if planner.uses_native_kernel():
		var kernel = planner._native_kernel_for("land", -1)
		var context = kernel.create_search_context()
		var old_path = context.find_cell_path(Vector2i(3, 3), Vector2i(20, 20), 0.3)
		kernel.update_walkable(grid.revision + 1, PackedInt32Array([10 * 24 + 12]), PackedByteArray([0]))
		check(context.find_cell_path(Vector2i(3, 3), Vector2i(20, 20), 0.3) == old_path, "native context retains isolated topology after owner patch")
	coordinator.shutdown()
	test_blocked_endpoint_retains_resolved_cell_route()
	test_eviction_preserves_sequential_geometry(false)
	test_eviction_preserves_sequential_geometry(true)
	finish()


func test_saturated_batch_cache(planner, coordinator, requests: Array, expected: Array) -> void:
	# A long match fills the cache even on static terrain. Batch preparation
	# must remain proportional to the current requests and keep using workers.
	for category in ["world", "cells", "smooth"]:
		var bucket: Dictionary = planner._geometry_bucket(category)
		for index in range(Pathfinder.MAX_ROUTE_CACHE_ENTRIES - bucket.size()):
			var key := "unrelated_history_%d" % index
			bucket[key] = {"path": [Vector2i(1, 1)], "direct": true} if category == "smooth" else [Vector2(1.5, 1.5)]
			planner.geometry_metadata[category][key] = {"bounds": Rect2i(0, 0, 2, 2), "empty": false}
	var snapshot: Dictionary = planner.detached_route_caches_for(requests)
	for category in ["cache", "cells", "smoothed"]:
		check(snapshot[category].size() <= requests.size(), "route snapshot excludes unrelated match history: %s" % category)
	check(snapshot["cache"].size() == requests.size(), "route snapshot retains exact cached requests")
	var first_key: String = snapshot["cache"].keys()[0]
	var expected_copy: Array = snapshot["cache"][first_key].duplicate()
	planner.cache[first_key].append(Vector2(-100.0, -100.0))
	check(snapshot["cache"][first_key] == expected_copy, "route snapshot owns isolated cached geometry")
	planner.cache[first_key].pop_back()
	var submitted_before: int = coordinator.next_request_id
	check(planner.find_paths_batch(requests, coordinator) == expected, "saturated batch preserves request order and paths")
	if planner.uses_native_kernel() and coordinator.is_enabled("navigation_paths"):
		check(coordinator.next_request_id > submitted_before, "a full cache does not permanently disable path workers")
	var fresh_requests: Array = requests.duplicate(true)
	for request in fresh_requests:
		request["start"] = Vector2(4.5, 4.5)
	# Duplicates straddle worker chunks, exercising final FIFO insertion order.
	fresh_requests.append(fresh_requests[0].duplicate())
	fresh_requests.append(fresh_requests[1].duplicate())
	var reference := Pathfinder.new(planner.grid)
	reference.set_native_enabled(planner.native_enabled)
	reference.route_cache_revision = planner.route_cache_revision
	reference.cache = planner.cache.duplicate(true)
	reference.cell_cache = planner.cell_cache.duplicate(true)
	reference.smoothed_cell_cache = planner.smoothed_cell_cache.duplicate(true)
	reference.geometry_metadata = planner.geometry_metadata.duplicate(true)
	var fresh_expected: Array = []
	for request in fresh_requests:
		fresh_expected.append(reference.find_path(request["start"], request["goal"], String(request["domain"]), int(request["restriction"]), float(request["clearance"])))
	check(planner.find_paths_batch(fresh_requests, coordinator) == fresh_expected, "new routes merge correctly after old cache history fills capacity")
	for category in ["world", "cells", "smooth"]:
		check(planner._geometry_bucket(category).size() <= Pathfinder.MAX_ROUTE_CACHE_ENTRIES, "saturated worker merge keeps route cache bounded: %s" % category)
		check(planner.geometry_metadata[category].size() == planner._geometry_bucket(category).size(), "saturated merge retires matching route metadata: %s" % category)
		check(planner._geometry_bucket(category).keys() == reference._geometry_bucket(category).keys(), "saturated duplicate batches preserve sequential FIFO cache order: %s" % category)


func detour_fixture(blocked_endpoint: bool) -> Dictionary:
	var grid := Grid.new(Vector2i(32, 24))
	grid.configure_terrain(func(_cell): return "grass")
	var wall: Array = []
	for y in range(24):
		if y != 4:
			wall.append(Vector2i(15, y))
	grid.occupy(wall, "building", 1000)
	if blocked_endpoint:
		grid.occupy([Vector2i(20, 12)], "resource", 1001)
	var request := {"start": Vector2(10.5, 12.5), "goal": Vector2(20.5, 12.5), "domain": "land", "restriction": -1, "clearance": 0.0}
	var sequential := Pathfinder.new(grid)
	var batched := Pathfinder.new(grid)
	var old_path: Array = sequential.find_path(request["start"], request["goal"])
	check(batched.find_path(request["start"], request["goal"]) == old_path, "detour fixture warms identical geometry")
	# This shorter passage is outside the old route bounds. A valid retained
	# route intentionally survives, while a fresh search can use the new gate.
	grid.release_occupant([Vector2i(15, 15)], "building", 1000)
	sequential._sync_route_revision()
	batched._sync_route_revision()
	var fresh := Pathfinder.new(grid)
	check(fresh.find_path(request["start"], request["goal"]) != old_path, "off-route shortcut distinguishes retained geometry from a fresh search")
	return {"grid": grid, "request": request, "sequential": sequential, "batched": batched, "old_path": old_path}


func test_blocked_endpoint_retains_resolved_cell_route() -> void:
	if not ClassDB.class_exists("RoRPathKernel"):
		return
	var fixture := detour_fixture(true)
	var planner = fixture["batched"]
	var request: Dictionary = fixture["request"]
	check(planner.cache.is_empty() and not planner.smoothed_cell_cache.is_empty(), "blocked endpoint invalidates global world route but retains resolved cell geometry")
	var requests: Array = []
	for index in range(4):
		var entry: Dictionary = request.duplicate()
		entry["start"] = Vector2(10.5 + float(index) * 0.01, 12.5)
		requests.append(entry)
	var snapshot: Dictionary = planner.detached_route_caches_for(requests)
	var resolved: Vector2i = planner.nearest_walkable(Vector2i(20, 12))
	var resolved_key: String = planner._cell_key(Vector2i(10, 12), resolved, "land", -1, 0.0)
	check(snapshot["smoothed"].has(resolved_key), "blocked endpoint snapshot includes the resolved-goal cache key")
	var expected: Array = []
	for entry in requests:
		expected.append(fixture["sequential"].find_path(entry["start"], entry["goal"]))
	var coordinator := Coordinator.new()
	check(planner.find_paths_batch(requests, coordinator) == expected, "blocked endpoint batch preserves warmed geometry after an unrelated shortcut opens")
	coordinator.shutdown()


func test_eviction_preserves_sequential_geometry(blocked_endpoint: bool) -> void:
	if not ClassDB.class_exists("RoRPathKernel"):
		return
	var fixture := detour_fixture(blocked_endpoint)
	var planner = fixture["batched"]
	for finder in [fixture["sequential"], planner]:
		for category in ["world", "smooth"]:
			var bucket: Dictionary = finder._geometry_bucket(category)
			for index in range(Pathfinder.MAX_ROUTE_CACHE_ENTRIES - bucket.size()):
				var key := "history_%d" % index
				bucket[key] = {"path": [Vector2i(1, 1)], "direct": true} if category == "smooth" else [Vector2(1.5, 1.5)]
				finder.geometry_metadata[category][key] = {"bounds": Rect2i(0, 0, 2, 2), "empty": false}
	var first := {"start": Vector2(2.5, 20.5), "goal": Vector2(6.5, 20.5), "domain": "land", "restriction": -1, "clearance": 0.0}
	var requests: Array = [first, fixture["request"], first.duplicate(), fixture["request"].duplicate()]
	var snapshot: Dictionary = planner.detached_route_caches_for(requests)
	check(planner._batch_may_evict_required_geometry(snapshot), "eviction guard detects a later retained route (blocked=%s)" % blocked_endpoint)
	var expected: Array = []
	for request in requests:
		expected.append(fixture["sequential"].find_path(request["start"], request["goal"]))
	check(expected[1] != fixture["old_path"], "early miss evicts warmed geometry before the later request (blocked=%s)" % blocked_endpoint)
	var coordinator := Coordinator.new()
	var submitted_before: int = coordinator.next_request_id
	check(planner.find_paths_batch(requests, coordinator) == expected, "capacity-sensitive batch matches sequential route choices (blocked=%s)" % blocked_endpoint)
	check(coordinator.next_request_id == submitted_before, "capacity-sensitive batch uses ordered fallback (blocked=%s)" % blocked_endpoint)
	for category in ["world", "cells", "smooth"]:
		check(planner._geometry_bucket(category).keys() == fixture["sequential"]._geometry_bucket(category).keys(), "fallback preserves final cache order: %s blocked=%s" % [category, blocked_endpoint])
	coordinator.shutdown()
