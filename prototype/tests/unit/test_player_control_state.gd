extends SceneTree

const PlayerControlState := preload("res://scripts/player_control_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_selection_lives_outside_entities()
	if failures.is_empty():
		print("I1-004 player control state tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_selection_lives_outside_entities() -> void:
	var state = PlayerControlState.new(1)
	state.apply_selection([1, 2, 3], [1, 2], false)
	assert_equal(state.selected_ids(), [1, 2], "plain selection replaces IDs")
	state.apply_selection([1, 2, 3], [2, 3], true)
	assert_equal(state.selected_ids(), [1, 3], "additive selection toggles IDs")
	state.replace_or_add([2], false)
	assert_equal(state.selected_ids(), [2], "control group replaces selection")
	state.replace_or_add([3], true)
	assert_equal(state.selected_ids(), [2, 3], "additive control group keeps selection")
	state.prune([3])
	assert_equal(state.selected_ids(), [3], "dead or unavailable IDs are pruned")
	assert_true(state.is_selected(3), "selection query uses player control state")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
