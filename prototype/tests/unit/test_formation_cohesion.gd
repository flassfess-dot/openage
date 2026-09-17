extends SceneTree

const FormationCohesion := preload("res://scripts/formation_cohesion.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_front_waits_and_rear_catches_up()
	test_stuck_member_does_not_hold_group_forever()
	test_small_detour_keeps_group_membership()
	test_aligned_group_uses_shared_motion()
	test_deformed_or_unsafe_group_uses_individual_motion()

	if failures.is_empty():
		print("F-009 formation cohesion tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_front_waits_and_rear_catches_up() -> void:
	var front := moving_unit(1, 8.0, 10.0)
	var middle := moving_unit(2, 6.0, 10.0)
	var rear := moving_unit(3, 3.0, 10.0)
	var members := [front, middle, rear]
	FormationCohesion.update(members)
	assert_true(front["cohesion_speed_scale"] < 1.0, "front rank waits for group")
	assert_true(rear["cohesion_speed_scale"] > 1.0, "rear rank may catch up")
	assert_equal(middle["cohesion_speed_scale"], 1.0, "middle keeps normal pace")
	var movement := LocalMovement.calculate(rear, rear["target"], [], open_grid(), 0.05)
	assert_true(movement["actual_velocity"].length() > rear["speed"], "catch-up scale reaches movement")
	assert_true(movement["actual_velocity"].length() <= rear["speed"] * FormationCohesion.MAX_CATCHUP_SCALE + 0.0001, "catch-up remains capped")


func test_stuck_member_does_not_hold_group_forever() -> void:
	var front := moving_unit(1, 8.0, 10.0)
	var middle := moving_unit(2, 7.2, 10.0)
	var stuck_rear := moving_unit(3, 1.0, 10.0)
	stuck_rear["stuck_ticks"] = FormationCohesion.DETACH_STUCK_TICKS
	FormationCohesion.update([front, middle, stuck_rear])
	assert_equal(front["cohesion_speed_scale"], 1.0, "detached stuck member no longer slows front")
	assert_equal(stuck_rear["cohesion_speed_scale"], 1.0, "stuck member remains under recovery control")


func test_small_detour_keeps_group_membership() -> void:
	var unit := moving_unit(7, 5.0, 10.0)
	unit["path"] = [Vector2(5.5, 6.5), Vector2(8.5, 8.5), Vector2(10.0, 5.0)]
	var before_group: int = int(unit["formation_group_id"])
	FormationCohesion.update([unit])
	assert_equal(unit["formation_group_id"], before_group, "detour preserves group")
	assert_equal(unit["path"].size(), 3, "cohesion does not replace local route")


func test_aligned_group_uses_shared_motion() -> void:
	var first := moving_unit(10, 3.0, 13.0)
	var second := moving_unit(11, 4.0, 14.0)
	FormationCohesion.update([first, second])
	assert_equal(first["formation_shared_motion"], true, "aligned safe member enters shared motion")
	assert_equal(second["formation_shared_motion"], true, "whole aligned group enters shared motion")
	assert_equal(first["formation_shared_isolated"], true, "distant formation skips redundant member queries")
	var outsider := moving_unit(12, 3.5, 13.5)
	outsider["formation_group_id"] = -1
	FormationCohesion.update([first, second, outsider])
	assert_equal(first["formation_shared_motion"], true, "nearby outsider does not break rigid internal motion")
	assert_equal(first["formation_shared_isolated"], false, "nearby outsider restores external avoidance query")


func test_deformed_or_unsafe_group_uses_individual_motion() -> void:
	var first := moving_unit(20, 3.0, 13.0)
	var deformed := moving_unit(21, 4.0, 13.0)
	FormationCohesion.update([first, deformed])
	assert_equal(first["formation_shared_motion"], false, "different displacement keeps individual avoidance")
	var large_first := moving_unit(30, 3.0, 13.0)
	var large_second := moving_unit(31, 4.0, 14.0)
	large_first["footprint_radius"] = 0.46
	large_second["footprint_radius"] = 0.46
	FormationCohesion.update([large_first, large_second])
	assert_equal(large_first["formation_shared_motion"], false, "unsafe slot spacing keeps individual avoidance")


func moving_unit(id: int, x: float, destination_x: float) -> Dictionary:
	return {
		"id": id,
		"hp": 20.0,
		"task": "move",
		"formation_group_id": 4,
		"pos": Vector2(x, 5.0),
		"previous_pos": Vector2(x, 5.0),
		"target": Vector2(destination_x, 5.0),
		"destination": Vector2(destination_x, 5.0),
		"path": [Vector2(destination_x, 5.0)],
		"path_index": 0,
		"speed": 1.2,
		"stuck_ticks": 0,
		"footprint_radius": 0.3,
		"minimum_clearance": 0.08,
		"push_priority": 2,
	}


func open_grid():
	var grid = NavigationGrid.new(Vector2i(16, 16))
	grid.configure_terrain(func(_cell): return "grass")
	return grid


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
