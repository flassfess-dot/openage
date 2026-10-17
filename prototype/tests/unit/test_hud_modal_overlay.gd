extends SceneTree

const HUDModalOverlay := preload("res://scripts/hud_modal_overlay.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	root.add_child(viewport)
	var overlay := HUDModalOverlay.new()
	viewport.add_child(overlay)
	overlay.configure(catalog.interface_skin, {
		"local_team": 1,
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13},
			{"team": 2, "controller": "ai", "civilization_id": 1},
			{"team": 3, "controller": "ai", "civilization_id": 4},
		],
	}, 4, catalog.localization)
	overlay.set_viewport_size(Vector2(800, 600))
	overlay.set_snapshot({"player_state": {
		"team": 1,
		"allies": [1, 3],
		"relations": {1: "ally", 2: "enemy", 3: "ally"},
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13, "status": "active"},
			{"team": 2, "controller": "ai", "civilization_id": 1, "status": "active"},
			{"team": 3, "controller": "ai", "civilization_id": 4, "status": "defeated"},
		],
	}})

	overlay.show_menu()
	assert_true(overlay.is_blocking(), "menu blocks world input")
	assert_true(overlay.menu_panel.visible and not overlay.diplomacy_panel.visible, "menu owns the visible modal panel")
	assert_equal(overlay.resume_button.get_theme_color("font_color"), Color("383a35"), "Match menus use the main menu marble plaques and dark lettering")
	assert_true(overlay.resume_button.custom_minimum_size.y >= 32, "menu actions have readable click targets")
	overlay.set_save_available(false)
	assert_true(overlay.load_button.disabled, "load action reports an absent quick save")
	overlay.set_save_available(true)
	assert_true(not overlay.load_button.disabled, "load action becomes available for an existing quick save")
	var save_requested := [false]
	overlay.save_requested.connect(func(): save_requested[0] = true)
	overlay.save_button.emit_signal("pressed")
	assert_true(not save_requested[0] and overlay.active_section == "confirm", "existing quick save requires overwrite confirmation")
	overlay._confirm_action()
	assert_true(save_requested[0], "confirmed quick save delegates ownership to the game scene")
	overlay.close()
	assert_true(not overlay.visible and not overlay.is_blocking(), "close releases the modal layer")

	overlay.show_diplomacy()
	await process_frame
	assert_true(overlay.diplomacy_panel.visible and not overlay.menu_panel.visible, "diplomacy owns the visible modal panel")
	assert_equal(overlay.diplomacy_rows.get_child_count(), 3, "diplomacy lists every public player exactly once")
	var text := collect_text(overlay.diplomacy_rows)
	assert_true(text.contains("ВЫ"), "local player is identified")
	assert_true(text.contains("ВРАГ"), "enemy relation control is visible")
	assert_true(text.contains("СОЮЗ"), "ally relation control is visible")
	assert_true(text.contains("НЕЙТР."), "neutral relation control is visible")
	assert_true(text.contains("ПОБЕЖДЁН"), "public player status is visible")
	assert_true(text.contains("Римляне"), "civilization uses the imported source localization")
	assert_true(overlay.diplomacy_relation_buttons.has(2), "active foreign player owns diplomacy controls")
	assert_true(overlay.diplomacy_relation_buttons[3]["enemy"].disabled, "defeated player relation cannot be changed")
	var requested := []
	overlay.diplomacy_relation_requested.connect(func(team: int, relation: String): requested.append([team, relation]))
	overlay.diplomacy_relation_buttons[2]["neutral"].emit_signal("pressed")
	assert_equal(requested, [[2, "neutral"]], "relation control emits a directed user request")
	assert_true(overlay.diplomacy_relation_buttons[2]["neutral"].button_pressed, "pending relation is reflected without mutating simulation state")
	var eight_players: Array = []
	for team in range(1, 9):
		eight_players.append({"team": team, "controller": "human" if team == 1 else "ai", "civilization_id": team, "status": "active"})
	viewport.size = Vector2i(640, 480)
	overlay.set_viewport_size(Vector2(640, 480))
	overlay.set_snapshot({"player_state": {"team": 1, "allies": [1, 3], "players": eight_players}})
	overlay.show_diplomacy()
	for _frame in range(5): await process_frame
	assert_equal(overlay.diplomacy_relation_buttons.size(), 7, "compact diplomacy retains all seven foreign participants")
	assert_equal(overlay.diplomacy_rows.get_child_count(), 9, "eight player rows and one allied tribute row remain available")
	assert_inside(overlay.diplomacy_panel, viewport.size, "compact diplomacy frame")
	assert_inside(overlay.diplomacy_close_button, viewport.size, "compact diplomacy close action")
	var diplomacy_column := overlay.diplomacy_rows.get_parent().get_parent()
	assert_inside(diplomacy_column.get_child(0), viewport.size, "compact diplomacy heading")
	var diplomacy_scroll: ScrollContainer = overlay.diplomacy_rows.get_parent()
	assert_true(diplomacy_scroll.get_v_scroll_bar().max_value > diplomacy_scroll.size.y, "eight player list scrolls separately from heading and close action")
	diplomacy_scroll.scroll_vertical = int(diplomacy_scroll.get_v_scroll_bar().max_value)
	await process_frame
	var final_row: Control = overlay.diplomacy_rows.get_child(overlay.diplomacy_rows.get_child_count() - 1)
	assert_true(final_row.get_global_rect().intersects(diplomacy_scroll.get_global_rect()), "last player remains reachable by scrolling")
	viewport.free()

	if failures.is_empty():
		print("E2 HUD modal overlay tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func collect_text(node: Node) -> String:
	var result := ""
	if node is Label:
		result += node.text + "\n"
	elif node is Button:
		result += node.text + "\n"
	for child in node.get_children():
		result += collect_text(child)
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_inside(control: Control, viewport_size: Vector2, context: String) -> void:
	var rect := control.get_global_rect()
	assert_true(rect.position.x >= 0 and rect.position.y >= 0 and rect.end.x <= viewport_size.x + 1 and rect.end.y <= viewport_size.y + 1, context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
