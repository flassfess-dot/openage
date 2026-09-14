extends SceneTree

const ViewportCulling := preload("res://scripts/viewport_culling.gd")
const FogPresentation := preload("res://scripts/fog_presentation.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var bounds := ViewportCulling.tile_bounds(Vector2i(250, 250), [Vector2(30, 40), Vector2(50, 40), Vector2(50, 60), Vector2(30, 60)], 4)
	assert_equal(bounds, Rect2i(26, 36, 29, 29), "visible bounds expand screen footprint but do not traverse the full map")
	var cells: Array = [0, 0, 2, 2, 1, 1, 1, 2]
	var runs := ViewportCulling.fog_runs(cells, Vector2i(4, 2), 2)
	assert_equal(runs.size(), 2, "minimap fog merges adjacent cells of the same state into row runs")
	assert_equal(runs[0], {"y": 0, "x_from": 0, "x_to": 2, "state": 0}, "unknown row run keeps exact extent")
	assert_equal(runs[1], {"y": 1, "x_from": 0, "x_to": 3, "state": 1}, "explored row run keeps exact extent")
	test_fog_run_coverage()
	test_fog_presentation_contract()
	test_cell_triangle_fog_geometry()
	test_map_edge_guard_geometry()
	if failures.is_empty():
		print("I12-020D viewport culling tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_fog_run_coverage() -> void:
	var size := Vector2i(5, 3)
	var cells := PackedByteArray([
		0, 0, 2, 1, 1,
		2, 0, 2, 0, 2,
		1, 1, 1, 2, 0,
	])
	var coverage := PackedByteArray()
	coverage.resize(cells.size())
	var hidden_count := 0
	for state in cells:
		if int(state) != 2:
			hidden_count += 1
	for run_value in ViewportCulling.fog_runs(cells, size, 2):
		var run: Dictionary = run_value
		assert_true(int(run["x_from"]) >= 0 and int(run["x_to"]) <= size.x, "fog run stays inside horizontal map bounds")
		assert_true(int(run["y"]) >= 0 and int(run["y"]) < size.y, "fog run stays inside vertical map bounds")
		for x in range(int(run["x_from"]), int(run["x_to"])):
			var index := int(run["y"]) * size.x + x
			coverage[index] += 1
	var covered_count := 0
	for index in range(cells.size()):
		if int(cells[index]) == 2:
			assert_equal(int(coverage[index]), 0, "visible cell %d has no fog geometry" % index)
		else:
			assert_equal(int(coverage[index]), 1, "hidden cell %d is covered exactly once" % index)
			covered_count += int(coverage[index])
	assert_equal(covered_count, hidden_count, "fog runs cover every non-visible map cell")


func test_fog_presentation_contract() -> void:
	assert_equal(FogPresentation.color_for_state(0).a, 1.0, "unknown world terrain is fully opaque")
	assert_equal(FogPresentation.color_for_state(0, true).a, 1.0, "unknown minimap terrain is fully opaque")
	var run := {"y": 2, "x_from": 1, "x_to": 4, "state": 0}
	var points := FogPresentation.terrain_conforming_run_polygon(
		run,
		func(world: Vector2): return world * 3.0 + Vector2(0.4, 0.6)
	)
	assert_equal(points.size(), 4, "flat fog run removes only collinear terrain samples")
	for point in points:
		assert_equal(point, point.round(), "fog polygon vertices are pixel snapped")
	var elevated_points := FogPresentation.terrain_conforming_run_polygon(
		run,
		func(world: Vector2):
			var lift := 7.0 if is_equal_approx(world.x, 2.0) else 0.0
			return world * 3.0 + Vector2(0.4, 0.6 - lift)
	)
	assert_true(elevated_points.size() > 4, "elevation bends survive collinear fog simplification")
	assert_true(Vector2(6, 0) in elevated_points, "top elevation boundary remains in fog polygon")
	assert_true(Vector2(6, 3) in elevated_points, "bottom elevation boundary remains in fog polygon")


func test_cell_triangle_fog_geometry() -> void:
	var vertex_heights := {
		Vector2i(2, 3): 1,
		Vector2i(3, 3): 0,
		Vector2i(3, 4): 0,
		Vector2i(2, 4): 0,
	}
	var projector := func(world: Vector2):
		var vertex := Vector2i(roundi(world.x), roundi(world.y))
		var elevation := float(vertex_heights.get(vertex, 0))
		return Vector2((world.x - world.y) * 32.0, (world.x + world.y) * 16.0 - elevation * 16.0)
	var triangles := FogPresentation.terrain_conforming_cell_triangles(Vector2i(2, 3), projector)
	assert_equal(triangles.size(), 2, "one fog cell has exactly two deterministic triangles")
	assert_equal(triangles[0].size(), 3, "first fog triangle has three vertices")
	assert_equal(triangles[1].size(), 3, "second fog triangle has three vertices")
	assert_equal(triangles[0][0], triangles[1][0], "fog triangles share the first diagonal vertex")
	assert_equal(triangles[0][2], triangles[1][1], "fog triangles share the second diagonal vertex")
	for triangle in triangles:
		for point in triangle:
			assert_equal(point, point.round(), "cell fog geometry is pixel snapped")
	var invalid := FogPresentation.terrain_conforming_cell_triangles(Vector2i.ZERO, Callable())
	assert_true(invalid.is_empty(), "invalid projector creates no fog geometry")


func test_map_edge_guard_geometry() -> void:
	var chains := FogPresentation.map_edge_guard_chains(
		Vector2i(3, 2),
		func(world: Vector2): return world * 10.0 + Vector2(0.4, 0.6)
	)
	assert_equal(chains.size(), 4, "finite map has four independent outer guard chains")
	assert_equal(chains[0].size(), 4, "top map edge contains every horizontal source vertex")
	assert_equal(chains[1].size(), 3, "right map edge contains every vertical source vertex")
	assert_equal(chains[0][0], Vector2(0, 1), "edge vertices use the same pixel snapping as terrain fog")
	assert_equal(chains[0][chains[0].size() - 1], Vector2(30, 1), "top guard reaches exact map corner")
	assert_equal(chains[1][0], Vector2(30, 1), "adjacent guards share exact corner pixels")
	assert_equal(chains[1][chains[1].size() - 1], Vector2(30, 21), "right guard reaches exact map corner")
	assert_true(FogPresentation.map_edge_guard_chains(Vector2i.ZERO, Callable()).is_empty(), "invalid map produces no guard geometry")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
