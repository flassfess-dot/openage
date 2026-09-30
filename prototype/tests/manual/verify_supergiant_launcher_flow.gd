extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://launcher.tscn")
	var launcher = scene.instantiate()
	root.add_child(launcher)
	await process_frame

	launcher.screen_buttons["single_player"].pressed.emit()
	await process_frame
	launcher.screen_buttons["random_map"].pressed.emit()
	await process_frame

	var map_size: OptionButton = launcher.setting_controls["map_size_id"]
	var population: OptionButton = launcher.setting_controls["population_limit"]
	_assert_equal(map_size.get_item_metadata(map_size.selected), "supergiant", "supergiant map is selected")
	_assert_equal(population.get_item_metadata(population.selected), 500, "population limit 500 is selected")

	launcher.start_button.pressed.emit()
	var loading_was_drawn := false
	var maximum_progress := 0.0
	var last_reported_bucket := -1
	var deadline := Time.get_ticks_msec() + 600000
	while Time.get_ticks_msec() < deadline and is_instance_valid(launcher):
		await process_frame
		if not is_instance_valid(launcher):
			break
		if launcher.current_screen == "loading" and launcher.generation_progress_bar != null:
			loading_was_drawn = true
			maximum_progress = maxf(maximum_progress, float(launcher.generation_progress_bar.value))
			var bucket := floori(maximum_progress / 10.0)
			if bucket > last_reported_bucket:
				last_reported_bucket = bucket
				print("Supergiant launcher generation: %d%%" % roundi(maximum_progress))

	_assert_true(loading_was_drawn, "loading screen is rendered before generation finishes")
	_assert_true(maximum_progress > 0.0, "loading screen receives generation progress")
	_assert_true(current_scene != null, "generated match becomes the current scene")
	if current_scene != null:
		await process_frame
		await process_frame

	_finish()


func _assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func _assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish() -> void:
	if failures.is_empty():
		print("Supergiant launcher flow passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
