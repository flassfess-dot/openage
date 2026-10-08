extends SceneTree
const Data := preload("res://scripts/isolated_task_data.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Ai := preload("res://scripts/ai_player.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var points: Array[Vector2] = []
	for index in range(50000):
		points.append(Vector2(index % 400, index / 400))
	check(Data.freeze_detached(points), "typed point bucket is validated and frozen")
	var navigation := {"land": points, "reachable": {"land": points}, "unit_regions": {7: 3}}
	check(Data.freeze_detached(navigation), "navigation publication freezes all nested containers")
	var snapshot := {"navigation": navigation, "player_state": {"resources": {0: 250}}, "units": [{"id": 7, "pos": Vector2(2.5, 3.5)}]}
	var ai := Ai.new({"team": 2})
	var input := Task.capture(ai, snapshot, 20)
	check(is_same(input["snapshot"]["navigation"], navigation) and is_same(input["snapshot"]["navigation"]["land"], points), "large navigation is shared by identity instead of duplicated")
	snapshot["player_state"]["resources"][0] = 999
	snapshot["units"][0]["pos"] = Vector2.ZERO
	check(input["snapshot"]["player_state"]["resources"][0] == 250 and input["snapshot"]["units"][0]["pos"] == Vector2(2.5, 3.5), "mutable facts are detached from their owner")
	var sealed := Data.seal(input)
	check(sealed["snapshot"].is_read_only() and is_same(sealed["snapshot"]["navigation"], navigation), "dispatch freezes only the owned input and retains immutable map identity")
	check(Data.is_detached(sealed) and is_same(Data.seal(sealed), sealed), "validated input can be resubmitted without copying")
	var next_points: Array[Vector2] = points.duplicate()
	next_points.append(Vector2(399.5, 399.5))
	var next_navigation := {"land": next_points}
	check(Data.freeze_detached(next_navigation), "a new navigation revision is independently immutable")
	check(points.size() == 50000 and sealed["snapshot"]["navigation"]["land"].size() == 50000, "later revisions preserve an in-flight decision's map")
	var forged := {Data.SEAL_KEY: sealed[Data.SEAL_KEY], "object": RefCounted.new()}
	forged.make_read_only()
	check(not Data.is_detached(forged) and Data.seal(forged).is_empty(), "a copied token cannot hide a live object")
	var unsafe := {"nested": [Callable(self, "_initialize")]}
	check(not Data.freeze_detached(unsafe), "recursive immutable registration rejects callables")
	for index in range(Data.MAX_IMMUTABLE_ROOTS + 1):
		check(Data.freeze_detached({"id": index}), "small immutable roots register safely")
	check(Data.immutable_roots.size() <= Data.MAX_IMMUTABLE_ROOTS, "immutable publication registry is bounded")
	check(Data.is_detached(navigation) and navigation["land"].size() == 50000, "evicted publications remain safely verifiable without point traversal")
	var evicted_capture: Dictionary = Data.capture(navigation)
	check(is_same(evicted_capture["land"], points), "typed readonly buckets stay shared after wrapper-registry eviction")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
