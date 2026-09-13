extends SceneTree

const PerceptionService := preload("res://scripts/perception_service.gd")

var failures: Array[String] = []
var service := PerceptionService.new()


func _initialize() -> void:
	test_filters_ownership_visibility_range_and_reachability()
	test_ranking_is_stable_and_spreads_attackers()
	if failures.is_empty():
		print("I6-001 perception service tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_filters_ownership_visibility_range_and_reachability() -> void:
	var observer := entity(10, 1, Vector2.ZERO, ["combatant", "military"])
	observer["acquisition_range"] = 5.0
	var valid := entity(20, 2, Vector2(3.0, 0.0), ["combatant", "military"])
	var ally := entity(21, 3, Vector2(1.0, 0.0), ["combatant"])
	var hidden := entity(22, 2, Vector2(1.5, 0.0), ["combatant"])
	hidden["hidden"] = true
	var unreachable := entity(23, 2, Vector2(2.0, 0.0), ["combatant"])
	unreachable["unreachable"] = true
	var distant := entity(24, 2, Vector2(8.0, 0.0), ["combatant"])
	var results := service.query(observer, [valid, ally, hidden, unreachable, distant], {
		"range": 5.0,
		"visibility": func(_team: int, candidate: Dictionary): return not bool(candidate.get("hidden", false)),
		"alliance": func(_first: int, second: int): return second == 3,
		"reachability": func(_source: Dictionary, candidate: Dictionary): return not bool(candidate.get("unreachable", false)),
	})
	assert_equal(results.map(func(item): return int(item["entity_id"])), [20], "query keeps only visible hostile reachable targets in range")


func test_ranking_is_stable_and_spreads_attackers() -> void:
	var observer := entity(10, 1, Vector2.ZERO, ["combatant", "military"])
	var worker := entity(30, 2, Vector2(1.0, 0.0), ["worker", "combatant"])
	var threat := entity(31, 2, Vector2(3.0, 0.0), ["military", "combatant"])
	threat["task"] = "attack"
	threat["target_id"] = 10
	var other_military := entity(32, 2, Vector2(2.0, 0.0), ["military", "combatant"])
	var ranked := service.query(observer, [worker, other_military, threat], {"range": 6.0})
	assert_equal(ranked.map(func(item): return int(item["entity_id"])), [31, 32, 30], "active threat and combat class outrank raw proximity")
	threat["task"] = "idle"
	var spread := service.query(observer, [threat, other_military], {"range": 6.0, "assigned_attackers": {32: 2}})
	assert_equal(int(spread[0]["entity_id"]), 31, "assigned-attacker count spreads equal-class attackers")
	threat["pos"] = other_military["pos"]
	var stable := service.query(observer, [other_military, threat], {"range": 6.0})
	assert_equal(stable.map(func(item): return int(item["entity_id"])), [31, 32], "entity ID is the final deterministic tie break")


func entity(id: int, team: int, position: Vector2, tags: Array) -> Dictionary:
	return {"id": id, "team": team, "pos": position, "hp": 10.0, "footprint_radius": 0.3, "behavior_tags": tags, "task": "idle", "target_id": -1}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
