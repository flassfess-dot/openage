extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://launcher.tscn")
	var launcher = scene.instantiate()
	root.add_child(launcher)
	await process_frame
	assert_equal(launcher.match_selector.item_count, 7, "launcher lists the prototype and all six campaign verticals")
	assert_true(not launcher.match_selector.is_item_disabled(0), "prototype match is available")
	assert_true(not launcher.match_selector.is_item_disabled(1), "first imported campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(2), "Pyrrhus campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(3), "Syracuse campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(4), "Metaurus campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(5), "Zama campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(6), "Mithridates campaign match is available")
	launcher.match_selector.select(1)
	launcher._refresh_selection(1)
	assert_true(launcher.description_label.text.contains("Первая миссия"), "campaign selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "campaign can be launched through the ordinary UI")
	launcher.match_selector.select(2)
	launcher._refresh_selection(2)
	assert_true(launcher.description_label.text.contains("Вторая миссия"), "Pyrrhus selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "Pyrrhus can be launched through the ordinary UI")
	launcher.match_selector.select(3)
	launcher._refresh_selection(3)
	assert_true(launcher.description_label.text.contains("Третья миссия"), "Syracuse selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "Syracuse can be launched through the ordinary UI")
	launcher.match_selector.select(4)
	launcher._refresh_selection(4)
	assert_true(launcher.description_label.text.contains("Четвёртая миссия"), "Metaurus selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "Metaurus can be launched through the ordinary UI")
	launcher.match_selector.select(5)
	launcher._refresh_selection(5)
	assert_true(launcher.description_label.text.contains("Пятая миссия"), "Zama selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "Zama can be launched through the ordinary UI")
	launcher.match_selector.select(6)
	launcher._refresh_selection(6)
	assert_true(launcher.description_label.text.contains("Шестая миссия"), "Mithridates selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "Mithridates can be launched through the ordinary UI")
	launcher.free()
	_finish("I12-020G launcher scene tests passed")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
