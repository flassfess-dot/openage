extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	viewport.add_child(game)
	await process_frame
	await process_frame
	var hud = game.hud_controls
	assert_true(hud != null and hud.is_visible_in_tree(), "HUD control layer is visible")
	assert_equal(game.interface_style_index, 4, "default Roman player selects the Rise of Rome HUD background")
	assert_equal(hud.interface_style_index, 4, "command controls use the Roman HUD style")
	var top_bar = game.top_bar_controls
	assert_true(top_bar != null and top_bar.is_visible_in_tree(), "source top-bar control layer is visible")
	assert_equal(top_bar.style_index, 4, "top bar uses the Roman HUD style")
	assert_equal(top_bar.menu_button.get_theme_color("font_color"), Color("f4e6c7"), "Roman menu label remains readable on the dark source button")
	assert_equal(top_bar.diplomacy_button.get_theme_color("font_color"), Color("f4e6c7"), "Roman diplomacy label remains readable on the dark source button")
	assert_equal(game.hud_modal_overlay.style_index, 4, "modal controls use the Roman HUD style")
	assert_equal(top_bar.menu_button.get_global_rect(), Rect2(1207, 0, 73, 19), "menu uses exact right-aligned Roman 53007 geometry")
	assert_equal(top_bar.diplomacy_button.get_global_rect(), Rect2(1099, 0, 108, 19), "diplomacy uses exact Roman 53008 geometry")
	assert_equal(game.health_status_frames.size(), 26, "main scene enables every source health-strip frame")
	assert_true(hud.formation_buttons["RECTANGLE"].is_visible_in_tree(), "selected mobile group exposes formation controls")
	var button_rect: Rect2 = hud.formation_buttons["RECTANGLE"].get_global_rect()
	assert_true(button_rect.size.x > 1.0, "formation button owns a drawable rectangle")
	assert_true(button_rect.position.y >= 594.0 and button_rect.end.y <= 720.0, "formation button is laid out inside exact 126px bottom HUD: %s" % button_rect)
	assert_true(button_rect.position.x >= 136.0 and button_rect.end.x <= 406.0, "formation button stays inside the source command grid: %s" % button_rect)
	assert_true(String(hud.formation_buttons["RECTANGLE"].text).is_empty() and hud.formation_buttons["RECTANGLE"].icon != null, "formation command uses its dedicated icon")
	assert_equal(game.hud_model.get("selection", {}).get("count", 0), 7, "main scene selection reaches HudViewModel")
	assert_equal(game.hud_model.get("commands", []).filter(func(command): return command["type"] == "formation").size(), 5, "main scene exposes all formation actions")

	game._toggle_game_menu()
	assert_true(game.hud_modal_overlay.is_blocking(), "menu opens a modal input layer")
	assert_equal(game.hud_modal_overlay.active_mode, "menu", "top Menu button opens the game menu")
	assert_true(game.game_controller.paused, "menu pauses deterministic simulation")
	game._close_hud_modal()
	assert_true(not game.hud_modal_overlay.is_blocking(), "continue closes the menu")
	assert_true(not game.game_controller.paused, "closing the menu restores a running match")
	game.game_controller.set_paused(true)
	game._show_diplomacy_summary()
	assert_equal(game.hud_modal_overlay.active_mode, "diplomacy", "top Diplomacy button opens the player table")
	game._close_hud_modal()
	assert_true(game.game_controller.paused, "closing a modal preserves an existing manual pause")
	game.game_controller.set_paused(false)
	game.game_controller.set_paused(true)
	game.sync_world_state()
	var retained_revision: int = game.presentation_revision
	game.sync_world_state(false)
	assert_equal(game.presentation_revision, retained_revision, "presentation cadence reuses an unchanged fixed-tick snapshot")
	game.sync_world_state()
	assert_equal(game.presentation_revision, retained_revision + 1, "explicit synchronization still forces a fresh presentation boundary")
	game.game_controller.set_paused(false)

	var target_world := Vector2(5.0, 6.0)
	var geometry: Dictionary = game.minimap_geometry()
	assert_equal(geometry["rectangle"].size, Vector2(220, 114), "main scene uses the source minimap aperture instead of the entire right HUD region")
	var map_polygon: PackedVector2Array = game.MinimapProjection.map_polygon(game.map_size, geometry["center"], geometry["scale"])
	assert_true(map_polygon[0].y >= geometry["rectangle"].position.y and map_polygon[2].y <= geometry["rectangle"].end.y, "minimap fills but does not escape the source aperture")
	var minimap_point: Vector2 = game.MinimapProjection.world_to_minimap(target_world, geometry["center"], geometry["scale"])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = minimap_point
	assert_true(game.handle_minimap_input(click), "left click inside minimap is consumed")
	var viewport_size: Vector2 = game.get_viewport_rect().size
	var visible_center := Vector2(viewport_size.x * 0.5, (game.HUD_TOP + viewport_size.y - game.HUD_BOTTOM) * 0.5)
	assert_vector_close(game.view_offset, visible_center - game.iso_raw(target_world) * game.view_zoom, 0.01, "minimap click centers camera on exact world coordinate")

	viewport.size = Vector2i(1024, 600)
	await process_frame
	await process_frame
	assert_vector_close(hud.size, Vector2(1024, 600), 0.01, "HUD follows real viewport resize")
	assert_equal(top_bar.menu_button.get_global_rect(), Rect2(951, 0, 73, 19), "menu remains pinned to resized Roman top bar")
	assert_equal(top_bar.diplomacy_button.get_global_rect(), Rect2(843, 0, 108, 19), "diplomacy remains adjacent after resize")
	assert_vector_close(game.hud_modal_overlay.size, Vector2(1024, 600), 0.01, "modal input layer follows real viewport resize")
	button_rect = hud.formation_buttons["RECTANGLE"].get_global_rect()
	assert_true(button_rect.position.y >= 474.0 and button_rect.end.y <= 600.0, "formation controls remain inside resized source bottom panel: %s" % button_rect)
	viewport.free()

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
