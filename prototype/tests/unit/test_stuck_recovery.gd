extends SceneTree

const StuckRecovery := preload("res://scripts/stuck_recovery.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_recovery_sequence_without_teleport()
	test_progress_resets_recovery()
	test_orbit_and_slow_route_progress()

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

func test_orbit_and_slow_route_progress() -> void:
	var unit := {"id": 5, "pos": Vector2(6, 6), "target": Vector2(20, 6), "destination": Vector2(20, 6), "push_priority": 2, "base_push_priority": 2, "stuck_ticks": 0, "diagnostic_reason": ""}
	StuckRecovery.update_route_progress(unit)
	var stopped := false
	for tick in range(100):
		unit["pos"] = Vector2(6, 6) + Vector2(cos(tick * 0.8), sin(tick * 0.8)) * 0.08
		if StuckRecovery.update_route_progress(unit) == "stop": stopped = true
	assert_equal(stopped, true, "continuous orbit escalates despite nonzero velocity")
	unit["destination"] = Vector2(21, 6)
	unit["target"] = Vector2(21, 6)
	StuckRecovery.update_route_progress(unit)
	assert_equal(unit["stuck_ticks"], 0, "a new destination resets the old failure")
	for tick in range(120):
		unit["pos"] += Vector2(0.002, 0)
		StuckRecovery.update_route_progress(unit)
	assert_equal(int(unit["stuck_ticks"]) < StuckRecovery.LOCAL_REPATH_TICK + 3, true, "slow accumulated forward progress does not get stopped")
	# An L-shaped route initially moves away from its final destination.
	StuckRecovery.reset(unit)
	unit["pos"] = Vector2(6, 6)
	unit["target"] = Vector2(6, 12)
	unit["destination"] = Vector2(20, 6)
	for tick in range(40):
		unit["pos"].y += 0.03
		StuckRecovery.update_route_progress(unit)
	assert_equal(unit["stuck_ticks"], 0, "leg progress accepts a legitimate detour away from the final destination")
