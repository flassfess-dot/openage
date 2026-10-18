extends SceneTree
const Task := preload("res://scripts/ai_planning_task.gd")
const Legacy := preload("res://scripts/ai_economic_planner.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var executor := Task.Executor.new()
	var points: Array[Vector2] = [Vector2(1.5,2.5),Vector2(-1.9,3.1)]
	points.make_read_only()
	var water: Array[Vector2i] = [Vector2i(7,8)]
	water.make_read_only()
	var navigation := {"reachable":{"land":points,"water":water}}
	var first := executor.reachable_lookup(navigation)
	check(first == Legacy._reachable_cells_by_domain(navigation),"cached membership matches the reference")
	var second := executor.reachable_lookup(navigation)
	check(is_same(first["land"],second["land"]) and is_same(first["water"],second["water"]),"immutable publications reuse exact private indexes")
	check(first["land"].is_read_only(),"shared membership cannot be modified")
	var changed: Array[Vector2] = [Vector2(4.5,5.5)]
	changed.make_read_only()
	navigation["reachable"]["land"] = changed
	var third := executor.reachable_lookup(navigation)
	check(third == Legacy._reachable_cells_by_domain(navigation) and not third["land"].has(Vector2i(1,2)),"a replacement publication removes stale cells")
	var mutable: Array = [Vector2(10,11)]
	navigation["reachable"]["land"] = mutable
	executor.reachable_lookup(navigation)
	mutable[0] = Vector2(12,13)
	check(executor.reachable_lookup(navigation)["land"].has(Vector2i(12,13)),"mutable arrays never acquire an identity cache")
	check(executor.reachable_lookup({}).is_empty() and executor.reachable_cache.is_empty(),"empty domains release their retained data")
	for failure in failures: push_error(failure)
	print("AI reachability cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
