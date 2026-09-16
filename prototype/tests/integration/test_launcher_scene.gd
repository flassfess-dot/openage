extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://launcher.tscn")
	var launcher = scene.instantiate()
	root.add_child(launcher)
	await process_frame
	assert_equal(launcher.match_selector.item_count, 11, "launcher lists the prototype, nine frozen campaign verticals, and custom skirmish")
	assert_true(not launcher.match_selector.is_item_disabled(0), "prototype match is available")
	assert_true(not launcher.match_selector.is_item_disabled(1), "first imported campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(2), "Pyrrhus campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(3), "Syracuse campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(4), "Metaurus campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(5), "Zama campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(6), "Mithridates campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(7), "Sicily campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(8), "Mylae campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(9), "Tunes campaign match is available")
	assert_true(not launcher.match_selector.is_item_disabled(10), "custom skirmish is available without a prebuilt match file")
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
	launcher.match_selector.select(8)
	launcher._refresh_selection(8)
	assert_true(launcher.description_label.text.contains("артефактов"), "Mylae selection exposes its artifact objective")
	assert_true(not launcher.start_button.disabled, "Mylae can be launched through the ordinary UI")
	launcher.match_selector.select(10)
	launcher._refresh_selection(10)
	assert_true(launcher.settings_panel.visible, "custom skirmish exposes declarative settings")
	assert_equal(launcher.player_controls.size(), 8, "all eight player slots are configurable")
	assert_true(launcher.setting_controls.has("ai_difficulty_id"), "custom skirmish exposes the policy-owned AI difficulty selector")
	var generated = SkirmishSettings.build(launcher._settings_from_controls())
	assert_true(bool(generated.get("valid", false)), "launcher defaults produce a valid generated match")
	assert_equal(String(generated.get("definition", {}).get("players", [])[1].get("ai", {}).get("difficulty_id", "")), "standard", "launcher difficulty reaches the generated AI player")
	launcher.free()
	_finish("E5-002 launcher scene tests passed")


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
