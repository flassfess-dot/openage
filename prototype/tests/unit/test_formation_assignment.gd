extends SceneTree

const Assignment := preload("res://scripts/formation_assignment.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_minimum_total_movement_avoids_crossing()
	test_previous_slot_is_preserved_when_it_fits()
	test_ties_resolve_by_entity_id()

	if failures.is_empty():
		print("F-004 formation assignment tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_minimum_total_movement_avoids_crossing() -> void:
	var units := [unit(1, Vector2(9, 0)), unit(2, Vector2(1, 0))]
	var slots := [slot(0, Vector2(0, 0)), slot(1, Vector2(10, 0))]
	var result := Assignment.assign(units, slots)
	assert_equal(result, {1: 1, 2: 0}, "nearest assignment avoids crossing")
	var sequential := {1: 0, 2: 1}
	assert_true(Assignment.total_distance_squared(units, slots, result) < Assignment.total_distance_squared(units, slots, sequential), "total movement is minimized")


func test_previous_slot_is_preserved_when_it_fits() -> void:
	var units := [unit(4, Vector2(9, 0)), unit(8, Vector2(1, 0))]
	var slots := [slot(0, Vector2(0, 0)), slot(1, Vector2(10, 0))]
	var result := Assignment.assign(units, slots, {4: 0, 8: 1})
	assert_equal(result, {4: 0, 8: 1}, "valid previous slots are retained")


func test_ties_resolve_by_entity_id() -> void:
	var units := [unit(9, Vector2(5, 5)), unit(3, Vector2(5, 5))]
	var slots := [slot(0, Vector2(4, 5)), slot(1, Vector2(6, 5))]
	var result := Assignment.assign(units, slots)
	assert_equal(result[3], 0, "lower EntityId receives lower slot on a tie")
	assert_equal(result[9], 1, "higher EntityId receives remaining slot")


func unit(id: int, position: Vector2) -> Dictionary:
	return {"id": id, "pos": position, "footprint_radius": 0.3}


func slot(id: int, position: Vector2) -> Dictionary:
	return {"slot_id": id, "world": position, "capacity_radius": 0.45}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
