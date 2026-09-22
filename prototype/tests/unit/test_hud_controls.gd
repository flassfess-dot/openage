extends SceneTree

const HUDControls := preload("res://scripts/hud_controls.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_buttons_and_signals()

	if failures.is_empty():
		print("C-006 HUD control tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_buttons_and_signals() -> void:
	var hud = HUDControls.new()
	assert_equal(hud.formation_buttons.size(), 5, "formation button count")
	for formation_name in ["LINE", "RECTANGLE", "COLUMN", "WEDGE", "STAGGERED"]:
		var icon: Texture2D = hud.formation_buttons[formation_name].icon
		assert_true(icon != null, "%s formation has a dedicated icon" % formation_name)
		if icon != null:
			assert_equal(Vector2i(icon.get_width(), icon.get_height()), Vector2i(50, 50), "%s formation icon uses the source command size" % formation_name)
		assert_equal(hud.formation_buttons[formation_name].text, "", "%s formation uses icon-only presentation" % formation_name)
	assert_equal(hud.train_button.tooltip_text.is_empty(), false, "train tooltip")
	hud.set_state("WEDGE", false)
	assert_equal(hud.formation_buttons["WEDGE"].button_pressed, true, "pressed formation state")
	assert_equal(hud.formation_buttons["LINE"].button_pressed, false, "inactive formation state")
	assert_equal(hud.train_button.disabled, true, "disabled train state")

	var requested := [""]
	hud.formation_requested.connect(func(value: String): requested[0] = value)
	for formation_name in ["LINE", "RECTANGLE", "COLUMN", "WEDGE", "STAGGERED"]:
		hud.formation_buttons[formation_name].emit_signal("pressed")
		assert_equal(requested[0], formation_name, "%s button emits immediate reform action" % formation_name)
	hud.set_view_model({"commands": [
		{"type": "formation", "id": "LINE", "label": "Линия", "hotkey": "F5", "enabled": true, "active": false, "reason": ""},
		{"type": "formation", "id": "RECTANGLE", "label": "Каре", "hotkey": "F6", "enabled": true, "active": false, "reason": ""},
		{"type": "formation", "id": "COLUMN", "label": "Колонна", "hotkey": "F7", "enabled": true, "active": false, "reason": ""},
		{"type": "formation", "id": "WEDGE", "label": "Клин", "hotkey": "F8", "enabled": true, "active": true, "reason": ""},
		{"type": "formation", "id": "STAGGERED", "label": "Шахматный", "hotkey": "F9", "enabled": true, "active": false, "reason": ""},
	]})
	assert_true(hud.formation_buttons["LINE"].tooltip_text.contains("Линия") and hud.formation_buttons["LINE"].tooltip_text.contains("F5"), "formation tooltip preserves its localized name and hotkey")
	assert_true(hud.formation_buttons["WEDGE"].button_pressed, "formation icon preserves active state")

	var train_request := ["", -1]
	hud.train_requested.connect(func(kind: String, building_id: int):
		train_request[0] = kind
		train_request[1] = building_id
	)
	hud.set_view_model({"commands": [
		{"type": "train", "id": "clubman", "building_id": 80, "label": "Воин с палицей", "cost_text": "50 FOOD", "duration": 26.0, "enabled": true, "reason": ""},
	]})
	assert_equal(hud.train_button.visible, true, "data-driven training command is visible")
	assert_equal(hud.train_button.disabled, false, "available training command is enabled")
	hud.train_button.emit_signal("pressed")
	assert_equal(train_request, ["clubman", 80], "training signal preserves unit and producer IDs")
	var research_request := [-1, -1]
	hud.research_requested.connect(func(technology_id: int, building_id: int):
		research_request[0] = technology_id
		research_request[1] = building_id
	)
	hud.set_view_model({"commands": [
		{"type": "research", "id": "101", "technology_id": 101, "building_id": 81, "label": "Век орудий", "cost_text": "500 FOOD", "duration": 120.0, "enabled": true, "reason": ""},
	]})
	hud.train_button.emit_signal("pressed")
	assert_equal(research_request, [101, 81], "research signal preserves technology and producer IDs")
	var build_request := [""]
	hud.build_requested.connect(func(kind: String): build_request[0] = kind)
	hud.set_view_model({"commands": [
		{"type": "formation", "id": "LINE", "label": "Линия", "hotkey": "F5", "enabled": true, "active": true, "reason": ""},
		{"type": "build", "id": "house", "label": "Дом", "cost_text": "30 WOOD", "duration": 20.0, "enabled": true, "reason": ""},
		{"type": "unit_action", "id": "stop", "label": "Остановиться", "short_label": "СТОП", "hotkey": "X", "enabled": true, "reason": ""},
	]})
	assert_equal(hud.active_train_commands[0].get("type"), "open_build_menu", "worker first exposes the source build-menu command")
	assert_equal(hud.active_train_commands[1].get("id"), "stop", "worker retains common unit orders beside the closed build root")
	hud.train_button.emit_signal("pressed")
	assert_equal(hud.active_train_commands[0].get("type"), "build", "build-menu command opens the building choices")
	assert_equal(hud.active_train_commands.size(), 2, "open build submenu replaces common orders with build choices and back")
	assert_true(not hud.formation_buttons["LINE"].visible, "open build submenu owns the command grid and hides formations")
	hud.train_button.emit_signal("pressed")
	assert_equal(build_request[0], "house", "build signal preserves selected building kind")
	assert_equal(hud.build_menu_open, false, "choosing a building closes the presentation submenu")
	var trade_resource_request := [-1]
	hud.trade_resource_requested.connect(func(resource_type_id: int): trade_resource_request[0] = resource_type_id)
	hud.set_view_model({"commands": [
		{"type": "trade_resource", "id": "2", "resource_type_id": 2, "label": "Обменивать камень", "cost_text": "20 STONE", "duration": 0.0, "enabled": true, "active": true, "reason": ""},
	]})
	hud.train_button.emit_signal("pressed")
	assert_equal(trade_resource_request[0], 2, "trade resource signal preserves selected resource ID")
	var unit_action_request := [""]
	hud.unit_action_requested.connect(func(action_name: String): unit_action_request[0] = action_name)
	hud.set_view_model({"commands": [
		{"type": "unit_action", "id": "hold", "label": "Держать позицию", "short_label": "ДЕРЖ", "hotkey": "H", "enabled": true, "reason": ""},
	]})
	hud.train_button.emit_signal("pressed")
	assert_equal(unit_action_request[0], "hold", "unit-order button preserves its semantic action")
	assert_true(hud.train_button.text.contains("H") and hud.train_button.text.contains("ДЕРЖ"), "an unconfigured icon registry keeps the readable text fallback")

	var dense_commands: Array = []
	for index in range(22):
		dense_commands.append({"type": "build", "id": "building_%d" % index, "label": "Здание %d" % index, "enabled": true, "reason": ""})
	dense_commands.append({"type": "formation", "id": "LINE", "label": "Линия", "enabled": true, "active": true, "reason": ""})
	hud.set_view_model({"selection": {"category": "unit", "leader": {"id": 77, "kind": "villager"}}, "commands": dense_commands})
	hud.train_button.emit_signal("pressed")
	hud.size = Vector2(640, 126)
	hud.set_layout({"command": Rect2(4, 8, 270, 118)})
	assert_equal(hud.active_train_commands.size(), 23, "dense build palette retains every command plus Back")
	assert_true(hud.train_buttons.size() >= 23, "action button pool grows with the data-driven command set")
	var grid: Dictionary = HUDControls.adaptive_grid(Vector2(270, 118), hud.active_train_commands.size())
	assert_true(float(grid["cell_size"].x) > 0.0, "adaptive grid keeps dense commands usable")
	assert_true(int(grid["columns"]) * float(grid["cell_size"].x) <= 270.0, "adaptive grid fits the command width")
	assert_true(int(grid["rows"]) * float(grid["cell_size"].y) <= 118.0, "adaptive grid fits the command height")
	for index in range(hud.active_train_commands.size()):
		var button: Button = hud.train_buttons[index]
		assert_true(button.offset_left >= 4.0 and button.offset_right <= 274.0, "dense command %d remains inside the HUD command width" % index)
		assert_true(126.0 + button.offset_top >= 8.0 and 126.0 + button.offset_bottom <= 126.0, "dense command %d remains inside the HUD command height" % index)
	var sparse_grid: Dictionary = HUDControls.adaptive_grid(Vector2(270, 118), 4)
	assert_equal(sparse_grid["columns"], 4, "small command sets preserve the familiar single-row layout")
	hud.free()


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
