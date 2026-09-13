extends SceneTree

const PlayerRegistry := preload("res://scripts/player_registry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var registry = PlayerRegistry.new()
	registry.configure([
		{"team": 1, "controller": "human", "civilization_id": 13},
		{"team": 2, "controller": "ai", "civilization_id": 4},
		{"team": 3, "controller": "ai", "civilization_id": 7},
	])
	registry.set_relation(1, 3, "ally")
	assert_true(registry.are_allied(1, 3), "alliance is symmetric")
	assert_true(registry.are_allied(3, 1), "reverse alliance is visible")
	assert_true(not registry.are_allied(1, 2), "undeclared players are enemies")
	assert_equal(registry.allied_teams(1), [1, 3], "allied team list is stable and sorted")
	assert_true(registry.resign(2), "active player may resign once")
	assert_true(not registry.resign(2), "resignation is idempotently rejected")
	assert_equal(registry.status(2), PlayerRegistry.RESIGNED, "resigned status is authoritative")
	assert_equal(registry.active_teams(), [1, 3], "resigned player leaves active set")
	registry.finalize(1, [2, 3])
	assert_equal(registry.status(1), PlayerRegistry.VICTORIOUS, "winner receives terminal state")
	assert_equal(registry.status(3), PlayerRegistry.DEFEATED, "active loser receives defeated state")
	assert_equal(registry.status(2), PlayerRegistry.RESIGNED, "resigned state is not overwritten")

	if failures.is_empty():
		print("I11-006 player registry and diplomacy tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
