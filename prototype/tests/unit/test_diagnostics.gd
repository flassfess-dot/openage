extends SceneTree

const Diagnostics := preload("res://scripts/diagnostics.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_unit_snapshot()

	if failures.is_empty():
		print("A-007 diagnostics tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_unit_snapshot() -> void:
	var unit := {
		"id": 17,
		"pos": Vector2(4.0, 5.0),
		"previous_pos": Vector2(3.95, 5.0),
		"target": Vector2(8.0, 5.0),
		"task": "move",
		"speed": 1.25,
		"facing": 2,
		"anim_state": "move",
		"footprint_radius": 0.4,
	}
	var snapshot: Dictionary = Diagnostics.unit_snapshot(unit, 0.05)
	assert_equal(snapshot["id"], 17, "entity ID")
	assert_vector_close(snapshot["actual_velocity"], Vector2(1.0, 0.0), "actual velocity")
	assert_vector_close(snapshot["desired_velocity"], Vector2(1.25, 0.0), "desired velocity")
	assert_equal(snapshot["target"], Vector2(8.0, 5.0), "formation slot/target")
	assert_equal(snapshot["facing"], 2, "facing")
	assert_equal(snapshot["order"], "move", "order")
	assert_equal(snapshot["animation"], "move", "animation state")
	assert_equal(snapshot["stance"], "passive", "missing legacy stance has a stable fallback")
	assert_equal(snapshot["target_id"], -1, "missing legacy combat target has a stable fallback")
	assert_equal(snapshot["formation_slot_mode"], "none", "legacy entity has no formation constraint")
	assert_equal(snapshot["footprint_radius"], 0.4, "footprint")


func assert_vector_close(actual: Vector2, expected: Vector2, context: String) -> void:
	if not actual.is_equal_approx(expected):
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
