extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load()
	assert_equal(catalog.interface_source_inventory_data.get("sourceArchives", []).size(), 3, "all layered Interfac archives are inventoried")
	for style_index in range(5):
		for width in [640, 800, 1024]:
			var shell: Dictionary = catalog.interface_skin.hud_shell(width, style_index)
			assert_equal(shell["asset_name"], "hud_shell_%d_%d" % [width, style_index], "%d style %d resolves its own HUD shell" % [width, style_index])
			assert_true(shell["top"] != null, "%d style %d top HUD frame loads" % [width, style_index])
			assert_true(shell["bottom"] != null, "%d style %d bottom HUD frame loads" % [width, style_index])
			assert_equal(shell["top"].get_height(), 20, "%d style %d top HUD frame height" % [width, style_index])
			assert_equal(shell["bottom"].get_height(), 126, "%d style %d bottom HUD frame height" % [width, style_index])
			assert_true(catalog.interface_skin.has_valid_provenance(String(shell["asset_name"]), 0), "%d style %d shell has exact archive/palette provenance" % [width, style_index])
			assert_true(catalog.interface_skin.has_valid_provenance(String(shell["asset_name"]), 1), "%d style %d bottom shell has exact archive/palette provenance" % [width, style_index])
		var panel: Texture2D = catalog.interface_skin.panel_texture(style_index)
		assert_true(panel != null, "style %d repeatable HUD panel loads" % style_index)
		assert_equal(panel.get_height(), 138, "style %d repeatable HUD panel keeps source height" % style_index)
		assert_true(catalog.interface_skin.has_valid_provenance(catalog.interface_skin.panel_asset_name(style_index), 0), "style %d panel has exact archive/palette provenance" % style_index)
	assert_true(catalog.interface_skin.has_valid_provenance("interface_panel", 0), "fallback panel has exact archive/palette provenance")
	assert_equal(catalog.interface_skin.panel_asset_name(4), "interface_panel_1", "Roman shell uses the compatible classical repeatable panel")
	assert_equal(catalog.interface_skin.text_color(0), Color("20180f"), "light HUD style keeps its dark text")
	assert_equal(catalog.interface_skin.text_color(4), Color("f4e6c7"), "Roman HUD style uses readable light text")
	var expected_styles := {1: 0, 2: 1, 3: 2, 4: 0, 5: 1, 6: 2, 7: 1, 8: 0, 9: 2, 10: 3, 11: 3, 12: 3, 13: 4, 14: 4, 15: 4, 16: 4}
	for civilization_id in expected_styles:
		assert_equal(catalog.interface_skin.style_index_for_civilization(civilization_id, catalog.object_catalog_data), expected_styles[civilization_id], "civilization %d follows its source icon set" % civilization_id)
	var roman_match := {"local_team": 2, "players": [{"team": 1, "civilization_id": 1}, {"team": 2, "civilization_id": 13}]}
	assert_equal(catalog.interface_skin.style_index_for_match(roman_match, catalog.object_catalog_data), 4, "local Roman player selects the Rise of Rome HUD style")
	var roman_small_button: Dictionary = catalog.interface_skin.menu_button(4, false)
	var roman_medium_button: Dictionary = catalog.interface_skin.menu_button(4, true)
	assert_equal(roman_small_button.get("source_id", -1), 53007, "Roman top menu uses the expansion source style")
	assert_equal(roman_small_button.get("size", Vector2.ZERO), Vector2(73, 19), "Roman top menu keeps its native source dimensions")
	assert_equal(roman_medium_button.get("source_id", -1), 53008, "Roman diplomacy button uses the expansion source style")
	assert_equal(roman_medium_button.get("size", Vector2.ZERO), Vector2(108, 19), "Roman diplomacy button keeps its native source dimensions")
	var roman_command_backplate := catalog.interface_skin.square_command_backplate(4)
	assert_true(roman_command_backplate != null, "Roman command backplate loads")
	assert_equal(Vector2i(roman_command_backplate.get_width(), roman_command_backplate.get_height()), Vector2i(54, 54), "Roman command backplate keeps native dimensions")
	var roman_arrows: Array = catalog.interface_skin.command_arrow_frames(4)
	assert_equal(roman_arrows.size(), 4, "Roman command arrows load")
	for arrow_value in roman_arrows:
		var arrow: Texture2D = arrow_value
		assert_equal(Vector2i(arrow.get_width(), arrow.get_height()), Vector2i(54, 31), "Roman command arrow keeps native dimensions")
	var inventory: Dictionary = catalog.interface_source_inventory_data
	assert_true(inventory.get("duplicateIds", {}).has("50103"), "duplicate source IDs remain visible instead of being flattened")
	if failures.is_empty():
		print("I12-020L source HUD skin tests passed")
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
