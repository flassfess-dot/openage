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


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
