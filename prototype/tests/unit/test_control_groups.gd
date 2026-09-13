extends SceneTree

const ControlGroups := preload("res://scripts/control_groups.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_assign_recall_and_center()
	test_additive_and_dead_member_filter()

	if failures.is_empty():
		print("C-004 control group tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_assign_recall_and_center() -> void:
	var groups = ControlGroups.new()
	var source: Array[int] = [7, 2, 7, 4]
	groups.assign(1, source)
	source[0] = 99
	var first: Dictionary = groups.recall(1, [2, 4, 7], [], false)
	assert_equal(first["ids"], [2, 4, 7], "assigned IDs are copied, unique and sorted")
	assert_equal(first["center"], false, "first recall does not center")
	var second: Dictionary = groups.recall(1, [2, 4, 7], [2, 4, 7], false)
	assert_equal(second["center"], true, "repeated recall requests camera center")


func test_additive_and_dead_member_filter() -> void:
	var groups = ControlGroups.new()
	groups.assign(3, [2, 4, 7])
	var result: Dictionary = groups.recall(3, [2, 7, 9], [9], true)
	assert_equal(result["ids"], [2, 7, 9], "Shift recall adds living members")
	assert_equal(groups.groups[3], [2, 7], "missing member is removed from group")
	assert_equal(result["center"], false, "additive recall never centers")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
