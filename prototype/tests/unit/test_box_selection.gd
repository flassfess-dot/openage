extends SceneTree

const SelectionResolver := preload("res://scripts/selection_resolver.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_shift_add_and_remove()
	test_unit_priority()

	if failures.is_empty():
		print("C-003 box selection tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_shift_add_and_remove() -> void:
	var first := {"id": 1, "selected": false}
	var second := {"id": 2, "selected": false}
	var third := {"id": 3, "selected": true}
	var eligible := [first, second, third]

	SelectionResolver.apply_selection(eligible, [first, second], false)
	assert_equal([first["selected"], second["selected"], third["selected"]], [true, true, false], "plain box replaces selection")

	SelectionResolver.apply_selection(eligible, [third], true)
	assert_equal(third["selected"], true, "Shift box adds unselected entity")
	SelectionResolver.apply_selection(eligible, [second], true)
	assert_equal(second["selected"], false, "Shift box removes selected entity")

	SelectionResolver.apply_selection(eligible, [], false)
	assert_equal([first["selected"], second["selected"], third["selected"]], [false, false, false], "empty plain box clears selection")


func test_unit_priority() -> void:
	var units := [{"id": 1}]
	var buildings := [{"id": 2}]
	assert_equal(SelectionResolver.prioritized_box_hits(units, buildings), units, "units win mixed box priority")
	assert_equal(SelectionResolver.prioritized_box_hits([], buildings), buildings, "buildings used without units")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
