extends SceneTree

const InputAdapter := preload("res://scripts/input_adapter.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_pointer_actions()
	test_keyboard_actions()
	test_outside_world_cancels_gesture()

	if failures.is_empty():
		print("I3-002 input adapter tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_pointer_actions() -> void:
	var adapter = InputAdapter.new()
	var left_down := mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(10, 10))
	assert_equal(adapter.translate(left_down)[0]["type"], "selection_started", "left press begins selection")
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(40, 30)
	adapter.translate(motion)
	assert_equal(adapter.selection_gesture()["is_box"], true, "motion exposes box preview")
	var selection := adapter.translate(mouse_button(MOUSE_BUTTON_LEFT, false, Vector2(40, 30)))[0]
	assert_equal(selection["type"], "selection_committed", "left release commits selection")
	assert_equal(selection["mode"], "select_box", "drag preserves semantic selection mode")

	adapter.translate(mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(70, 80)))
	motion.position = Vector2(100, 80)
	adapter.translate(motion)
	assert_true(not adapter.formation_gesture().is_empty(), "right drag exposes formation preview")
	var context := adapter.translate(mouse_button(MOUSE_BUTTON_RIGHT, false, Vector2(110, 80)))[0]
	assert_equal(context["type"], "context_committed", "right release commits context action")
	assert_equal(context["direction_end"], Vector2(110, 80), "direction endpoint retained")

	var zoom := adapter.translate(mouse_button(MOUSE_BUTTON_WHEEL_UP, true, Vector2(30, 40)))[0]
	assert_equal(zoom, {"type": "zoom", "position": Vector2(30, 40), "steps": 1}, "wheel maps to zoom intent")


func test_keyboard_actions() -> void:
	var adapter = InputAdapter.new()
	var formation := adapter.translate(key_event(KEY_F8))[0]
	assert_equal(formation, {"type": "set_formation", "formation": "WEDGE"}, "formation key is device mapping only")
	var group_event := key_event(KEY_4)
	group_event.ctrl_pressed = true
	var group := adapter.translate(group_event)[0]
	assert_equal(group, {"type": "control_group", "number": 4, "assign": true, "additive": false}, "control group modifiers retained")
	var resign_event := key_event(KEY_R)
	resign_event.shift_pressed = true
	assert_equal(adapter.translate(resign_event)[0], {"type": "resign"}, "Shift+R maps to explicit resign intent")
	assert_equal(adapter.translate(key_event(KEY_R))[0], {"type": "reset_game"}, "R keeps deterministic match restart")
	assert_equal(adapter.translate(key_event(KEY_DELETE))[0], {"type": "martyrdom"}, "Delete maps to the replayable Martyrdom intent")
	assert_equal(adapter.translate(key_event(KEY_U))[0].get("type"), "unload", "U maps to the replayable unload intent")
	assert_equal(adapter.translate(key_event(KEY_Q))[0], {"type": "attack_move_mode"}, "Q enters attack-move targeting")
	assert_equal(adapter.translate(key_event(KEY_X))[0], {"type": "stop"}, "X maps to the replayable stop intent")
	assert_equal(adapter.translate(key_event(KEY_H))[0], {"type": "hold"}, "H maps to hold-position intent")
	assert_equal(adapter.translate(key_event(KEY_V))[0], {"type": "cycle_stance"}, "V cycles the selected stance")


func test_outside_world_cancels_gesture() -> void:
	var adapter = InputAdapter.new()
	adapter.translate(mouse_button(MOUSE_BUTTON_LEFT, true, Vector2(10, 10)))
	var outside := adapter.translate(mouse_button(MOUSE_BUTTON_RIGHT, true, Vector2(2, 2)), false)
	assert_equal(outside[0]["type"], "consume_outside_world", "HUD press is consumed")
	assert_true(adapter.selection_gesture().is_empty(), "HUD press cancels pending world gesture")


func mouse_button(button: MouseButton, pressed: bool, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = position
	return event


func key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
