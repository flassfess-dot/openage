extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var hud = game.hud_controls
	assert_true(hud != null and hud.is_visible_in_tree(), "HUD control layer is visible")
	assert_true(hud.formation_buttons["RECTANGLE"].is_visible_in_tree(), "selected mobile group exposes formation controls")
	var button_rect: Rect2 = hud.formation_buttons["RECTANGLE"].get_global_rect()
	assert_true(button_rect.size.x > 1.0, "formation button owns a drawable rectangle")
	assert_true(button_rect.position.y >= 594.0 and button_rect.end.y <= 720.0, "formation button is laid out inside exact 126px bottom HUD: %s" % button_rect)
	assert_equal(game.hud_model.get("selection", {}).get("count", 0), 7, "main scene selection reaches HudViewModel")
	assert_equal(game.hud_model.get("commands", []).filter(func(command): return command["type"] == "formation").size(), 5, "main scene exposes all formation actions")

	var target_world := Vector2(5.0, 6.0)
	var geometry: Dictionary = game.minimap_geometry()
	var minimap_point: Vector2 = game.MinimapProjection.world_to_minimap(target_world, geometry["center"], geometry["scale"])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = minimap_point
	assert_true(game.handle_minimap_input(click), "left click inside minimap is consumed")
	var viewport_size: Vector2 = game.get_viewport_rect().size
	var visible_center := Vector2(viewport_size.x * 0.5, (game.HUD_TOP + viewport_size.y - game.HUD_BOTTOM) * 0.5)
	assert_vector_close(game.view_offset, visible_center - game.iso_raw(target_world) * game.view_zoom, 0.01, "minimap click centers camera on exact world coordinate")

	hud.size = Vector2(1024, 600)
	await process_frame
	assert_vector_close(hud.size, Vector2(1024, 600), 0.01, "HUD follows viewport resize")
	button_rect = hud.formation_buttons["RECTANGLE"].get_global_rect()
	assert_true(button_rect.position.y >= 474.0 and button_rect.end.y <= 600.0, "formation controls remain inside resized source bottom panel: %s" % button_rect)
	game.free()

	if failures.is_empty():
		print("I10-003 main HUD scene integration tests passed")
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


func assert_vector_close(actual: Vector2, expected: Vector2, tolerance: float, context: String) -> void:
	if actual.distance_to(expected) > tolerance:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
