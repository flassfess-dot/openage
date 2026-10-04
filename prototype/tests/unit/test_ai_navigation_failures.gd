extends SceneTree
const Policy := preload("res://scripts/ai_navigation_policy.gd")
const Tactical := preload("res://scripts/ai_tactical_planner.gd")
const Strategic := preload("res://scripts/ai_strategic_planner.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Ai := preload("res://scripts/ai_player.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var unit := {"id": 7, "team": 2, "hp": 40, "pos": Vector2(3.5, 3.5), "task": "idle", "diagnostic_reason": "no_group_route", "path_request_id": 1, "combat_enabled": true, "movement_domain": "land"}
	var cache := {}
	var store := Store.new()
	var projected := store._project_entity(cache, unit, 2)
	check(int(projected.get("path_request_id", 0)) == 1, "compact own-unit observations include the request identity")
	unit["path_request_id"] = 2
	check(int(store._project_entity(cache, unit, 2).get("path_request_id", 0)) == 2, "retained observations refresh the request identity")
	check(not Snapshot.compact_ai_entity(unit, 3).has("path_request_id"), "opponent request history remains private")
	unit["team"] = 3
	check(not store._project_entity(cache, unit, 2).has("path_request_id"), "ownership changes remove retained private request data")
	unit["team"] = 2
	unit["path_request_id"] = 1
	var snapshot := {"observer_team": 2, "units": [unit], "navigation": {"unit_regions": {7: "a"}, "frontier_by_region": {"a": [Vector2(6.5, 3.5)]}, "recovery_positions": {7: Vector2(3.5, 4.5)}}}
	var policy := Policy.new()
	check(policy.reserved_units(snapshot, 100).has(7), "failed group routes are delayed")
	for tick in range(120, 180, 20): check(policy.reserved_units(snapshot, tick).has(7), "observing the same failure never resets its deadline")
	check(not policy.reserved_units(snapshot, 180).has(7), "failed units get a retry")
	unit["path_request_id"] = 2
	check(policy.reserved_units(snapshot, 180).has(7) and int(policy.failures[7]["retry_tick"]) == 340, "new failures increase retry delay")
	var restored := Policy.new()
	check(restored.restore_state(policy.canonical_state()), "retry policy restores")
	check(restored.reserved_units(snapshot, 320) == policy.reserved_units(snapshot, 320), "load preserves retry timing")
	var commands: Array = Tactical.plan(snapshot, 340, 2, {"type": "explore", "positions_by_domain": {"land": Vector2(90, 90)}})
	check(commands.size() == 1 and commands[0].params.get("target") == Vector2(3.5, 4.5), "group failure recovers locally instead of repeating its old destination")
	unit["pos"] = Vector2(3.5, 4.5)
	unit["diagnostic_reason"] = ""
	check(policy.reserved_units(snapshot, 341).is_empty() and policy.failures.is_empty(), "movement clears the failure")
	unit["diagnostic_reason"] = "no_path"
	policy.reserved_units(snapshot, 400)
	snapshot["units"] = []
	policy.reserved_units(snapshot, 420)
	check(policy.failures.is_empty(), "dead and absent units cannot accumulate retries")
	unit["diagnostic_reason"] = ""
	unit["pos"] = Vector2(2.5, 3.5)
	var other: Dictionary = unit.duplicate(true)
	other["id"] = 8
	other["pos"] = Vector2(30.5, 3.5)
	snapshot["units"] = [other, unit]
	snapshot["navigation"] = {"unit_regions": {7: "a", 8: "b"}, "frontier_by_region": {"a": [Vector2(6.5, 3.5)], "b": [Vector2(34.5, 3.5)]}}
	commands = Tactical.plan(snapshot, 440, 2, {"type": "explore", "positions_by_domain": {"land": Vector2(90, 90)}})
	check(commands.size() == 2 and commands[0].unit_ids == [7] and commands[1].unit_ids == [8], "same-domain islands receive separate commands")
	check(commands.size() == 2 and commands[0].params["target"] == Vector2(6.5, 3.5) and commands[1].params["target"] == Vector2(34.5, 3.5), "each group explores its own frontier")
	snapshot["navigation"]["frontier_by_region"] = {}
	check(Tactical.plan(snapshot, 460, 2, {"type": "explore"}).is_empty(), "exhausted regions receive no futile exploration orders")
	var frontier := [Vector2(3, 2), Vector2(2, 3), Vector2(4, 0), Vector2(0, 4), Vector2(1, 1), Vector2(8, 8)]
	var sorted := frontier.duplicate()
	sorted.sort_custom(func(a, b): return a.length_squared() > b.length_squared() if not is_equal_approx(a.length_squared(), b.length_squared()) else a.y < b.y if not is_equal_approx(a.y, b.y) else a.x < b.x)
	for decision in range(12): check(Strategic.exploration_target(frontier, Vector2.ZERO, decision) == sorted[decision % 4], "linear selection preserves sorted top-four behavior")
	var ai := Ai.new({"team": 2})
	var legacy := ai.canonical_state()
	legacy.erase("navigation_failures")
	check(ai.restore_state(legacy), "legacy AI state defaults to an empty failure policy")
	var worker := {"id": 42, "team": 2, "hp": 25, "pos": Vector2(8.5, 8.5), "task": "idle", "diagnostic_reason": "stuck_stopped_nearest_valid", "path_request_id": 10, "components": {"worker": {"enabled": true}}, "combat_enabled": false}
	var worker_snapshot := {"observer_team": 2, "units": [worker], "navigation": {"recovery_positions": {42: Vector2(9.5, 8.5)}}, "player_state": {"status": "active"}}
	var worker_ai := Ai.new({"team": 2, "ai": {"economic_interval_ticks": 20}})
	check(worker_ai.collect_commands(worker_snapshot, 0).all(func(command): return 42 not in command.unit_ids), "stuck workers wait for the bounded recovery deadline")
	var recovery: Array = worker_ai.collect_commands(worker_snapshot, 80).filter(func(command): return 42 in command.unit_ids)
	check(recovery.size() == 1 and recovery[0].command_type() == "move" and recovery[0].target == Vector2(9.5, 8.5), "worker recovery takes precedence over reassignment to the same blocked job")
	check(worker_ai.collect_commands(worker_snapshot, 81).all(func(command): return 42 not in command.unit_ids), "one pending recovery is not flooded with duplicate commands")
	for failure in failures: push_error(failure)
	print("AI navigation recovery: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
