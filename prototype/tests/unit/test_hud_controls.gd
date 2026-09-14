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
		{"type": "build", "id": "house", "label": "Дом", "cost_text": "30 WOOD", "duration": 20.0, "enabled": true, "reason": ""},
	]})
	assert_equal(hud.active_train_commands[0].get("type"), "open_build_menu", "worker first exposes the source build-menu command")
	hud.train_button.emit_signal("pressed")
	assert_equal(hud.active_train_commands[0].get("type"), "build", "build-menu command opens the building choices")
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
	hud.free()


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
