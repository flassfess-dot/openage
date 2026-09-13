extends SceneTree

const StuckRecovery := preload("res://scripts/stuck_recovery.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_recovery_sequence_without_teleport()
	test_progress_resets_recovery()

	if failures.is_empty():
		print("N-007 stuck recovery tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_recovery_sequence_without_teleport() -> void:
	var unit := {"id": 5, "pos": Vector2(6.25, 7.75), "push_priority": 2, "base_push_priority": 2, "stuck_ticks": 0, "diagnostic_reason": ""}
	var actions: Array[String] = []
	for _tick in range(StuckRecovery.STOP_TICK):
		var action := StuckRecovery.update(unit, 0.0)
		if action != "":
			actions.append(action)
	assert_equal(actions, ["local_repath", "priority_boost", "global_repath", "stop"], "ordered recovery actions")
	assert_equal(unit["pos"], Vector2(6.25, 7.75), "recovery never teleports")
	assert_equal(unit["diagnostic_reason"], "stuck_stopped_nearest_valid", "final reason is diagnostic")


func test_progress_resets_recovery() -> void:
	var unit := {"push_priority": 4, "base_push_priority": 2, "stuck_ticks": 14, "diagnostic_reason": "stuck_priority_boost"}
	assert_equal(StuckRecovery.update(unit, 0.01), "", "progress has no recovery action")
	assert_equal(unit["stuck_ticks"], 0, "progress resets counter")
	assert_equal(unit["push_priority"], 2, "progress restores base priority")
	assert_equal(unit["diagnostic_reason"], "", "progress clears stuck reason")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
