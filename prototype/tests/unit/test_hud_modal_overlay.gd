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
	}, 0, catalog.localization)
	overlay.set_viewport_size(Vector2(800, 600))
	overlay.set_snapshot({"player_state": {
		"team": 1,
		"allies": [1, 3],
		"players": [
			{"team": 1, "controller": "human", "civilization_id": 13, "status": "active"},
			{"team": 2, "controller": "ai", "civilization_id": 1, "status": "active"},
			{"team": 3, "controller": "ai", "civilization_id": 4, "status": "defeated"},
		],
	}})

	overlay.show_menu()
	assert_true(overlay.is_blocking(), "menu blocks world input")
	assert_true(overlay.menu_panel.visible and not overlay.diplomacy_panel.visible, "menu owns the visible modal panel")
	assert_equal(overlay.resume_button.custom_minimum_size, Vector2(108, 20), "modal action keeps native wide source-button dimensions")
	overlay.close()
	assert_true(not overlay.visible and not overlay.is_blocking(), "close releases the modal layer")

	overlay.show_diplomacy()
	await process_frame
	assert_true(overlay.diplomacy_panel.visible and not overlay.menu_panel.visible, "diplomacy owns the visible modal panel")
	assert_equal(overlay.diplomacy_rows.get_child_count(), 3, "diplomacy lists every public player exactly once")
	var text := collect_text(overlay.diplomacy_rows)
	assert_true(text.contains("ВЫ"), "local player is identified")
	assert_true(text.contains("ПРОТИВНИК"), "enemy relation is visible")
	assert_true(text.contains("СОЮЗНИК"), "ally relation is visible")
	assert_true(text.contains("ПОБЕЖДЁН"), "public player status is visible")
	assert_true(text.contains("Римляне"), "civilization uses the imported source localization")
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
	for child in node.get_children():
		result += collect_text(child)
	return result


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
