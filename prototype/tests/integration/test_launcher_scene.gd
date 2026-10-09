extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://launcher.tscn")
	var launcher = scene.instantiate()
	root.add_child(launcher)
	await process_frame

	assert_equal(launcher.current_screen, "main", "launcher starts at the original-style main menu")
	assert_true(not launcher.screen_buttons["single_player"].disabled, "single-player workflow is enabled")
	assert_true(launcher.screen_buttons["multiplayer"].disabled, "unfinished multiplayer workflow is visibly disabled")
	assert_true(launcher.screen_buttons["scenario_editor"].disabled, "unfinished scenario editor is visibly disabled")
	assert_true(launcher.screen_buttons["help"].disabled, "unfinished help workflow is visibly disabled")

	# Exercise the real signal path: screen replacement must not destroy the
	# button while its pressed signal is still being emitted.
	launcher.screen_buttons["single_player"].pressed.emit()
	await process_frame
	assert_equal(launcher.current_screen, "single_player", "single-player menu is a separate workflow step")
	assert_true(not launcher.screen_buttons["campaigns"].disabled, "campaign workflow is enabled")
	assert_true(not launcher.screen_buttons["random_map"].disabled, "random-map workflow is enabled")
	assert_true(not launcher.screen_buttons["saved_game"].disabled, "saved-game workflow is enabled")
	assert_true(launcher.screen_buttons["scenario"].disabled, "unfinished scenario workflow is disabled")

	launcher.screen_buttons["saved_game"].pressed.emit()
	await process_frame
	assert_equal(launcher.current_screen, launcher.SCREEN_SAVES, "saved games are accessible before starting a match")
	assert_true(launcher.save_list != null, "save browser shows its list")
	assert_equal(launcher.screen_buttons["load_save"].disabled, launcher.saved_games.is_empty(), "loading is available when a save exists")
	assert_true(launcher.screen_buttons["save_game"].disabled, "creating a save requires an active match")
	launcher.screen_buttons["back"].pressed.emit()
	await process_frame
	assert_equal(launcher.current_screen, "single_player", "leaving saved games returns to the menu that opened it")

	launcher._show_campaign_menu()
	assert_equal(launcher.campaign_selector.item_count, 10, "campaign screen lists the tutorial and nine campaign missions")
	launcher.campaign_selector.select(1)
	launcher._refresh_campaign_selection(1)
	assert_true(launcher.description_label.text.contains("Первая миссия"), "campaign selection exposes its launch description")
	assert_true(not launcher.start_button.disabled, "available campaign can be launched")

	launcher._show_random_map_menu()
	assert_equal(launcher.current_screen, "random_map", "random map has its own original-style setup screen")
	assert_equal(launcher.player_controls.size(), 8, "all eight player slots are configurable")
	assert_true(launcher.setting_controls.has("ai_difficulty_id"), "AI difficulty is configurable")
	assert_true(launcher.setting_controls.has("population_limit"), "population limit is configurable")

	var size_selector: OptionButton = launcher.setting_controls["map_size_id"]
	assert_true(_has_option(size_selector, "supergiant", "Сверхгигантская"), "400x400 supergiant size appears in the launcher")
	var population_selector: OptionButton = launcher.setting_controls["population_limit"]
	assert_true(_has_option(population_selector, 500, "500"), "population limit 500 appears in the launcher")
	assert_equal(size_selector.get_item_metadata(size_selector.selected), "supergiant", "supergiant is the visible default map size")
	assert_equal(population_selector.get_item_metadata(population_selector.selected), 500, "population limit 500 is the visible default")
	assert_equal(launcher._background_image.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED, "menu art covers the complete window")
	assert_equal(launcher._background_image.get_parent(), launcher, "menu art is independent of the 4:3 UI canvas")
	var first_civilization: OptionButton = launcher.player_controls[0]["civilization_id"]
	assert_true(_has_option(first_civilization, 0, "Случайная"), "random civilization appears in every player slot")
	assert_equal(first_civilization.get_item_metadata(first_civilization.selected), 0, "random civilization is the visible default")

	launcher._select_metadata(size_selector, "supergiant")
	launcher._select_metadata(population_selector, 500)
	var normalized := SkirmishSettings.normalize(launcher._settings_from_controls())
	assert_true(bool(normalized.get("valid", false)), "launcher settings satisfy the skirmish contract")
	assert_equal(normalized["settings"]["map_size_id"], "supergiant", "supergiant choice reaches generation settings")
	assert_equal(normalized["settings"]["population_limit"], 500, "population 500 reaches generation settings")
	assert_equal(normalized["settings"]["players"][0]["civilization_id"], 0, "random civilization reaches generation settings")

	launcher._show_loading_screen("СОЗДАНИЕ СЛУЧАЙНОЙ КАРТЫ", "Подготовка генератора")
	assert_equal(launcher.current_screen, "loading", "map generation has a dedicated loading screen")
	assert_true(launcher.generation_progress_bar != null, "loading screen exposes progress")
	assert_equal(launcher.generation_progress_bar.max_value, 100.0, "generation progress has a complete range")

	launcher.free()
	_finish("Launcher workflow tests passed")


func _has_option(option: OptionButton, metadata: Variant, title: String) -> bool:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == metadata and option.get_item_text(index) == title:
			return true
	return false


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
