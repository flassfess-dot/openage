extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var modes = root.get_node("WindowMode")
	modes.persist_changes = false
	modes.apply_settings(false, Vector2i(900, 650))
	for _frame in range(3): await process_frame
	var previous_position := root.position
	var previous_size := root.size
	var field := LineEdit.new()
	field.size = Vector2(260,40)
	field.text = "Горячая клавиша работает с фокусом в поле"
	root.add_child(field)
	field.grab_focus()
	var submitted: Array = []
	field.text_submitted.connect(func(text: String): submitted.append(text))
	root.push_input(_key(), true)
	for _frame in range(3): await process_frame
	check(root.mode == Window.MODE_FULLSCREEN, "Alt+Enter enters borderless fullscreen with a focused text field")
	check(root.size == DisplayServer.screen_get_size(root.current_screen), "fullscreen covers the monitor")
	check(root.get_size_with_decorations() == root.size, "fullscreen has no native frame")
	check(submitted.is_empty(), "Alt+Enter cannot submit the focused field")
	var repeated := _key()
	repeated.echo = true
	root.push_input(repeated, true)
	check(root.mode == Window.MODE_FULLSCREEN, "key repeat cannot toggle twice")
	root.push_input(_key(), true)
	for _frame in range(3): await process_frame
	check(root.mode == Window.MODE_WINDOWED and root.size == previous_size, "second Alt+Enter restores the previous window size")
	check(root.position == previous_position, "second Alt+Enter restores the previous window position")
	var popup := PopupMenu.new()
	root.add_child(popup)
	popup.add_item("Открытый список")
	popup.popup(Rect2i(root.position + Vector2i(80,80), Vector2i(240,80)))
	await process_frame
	popup.window_input.emit(_key())
	for _frame in range(3): await process_frame
	check(root.mode == Window.MODE_FULLSCREEN and not popup.visible, "Alt+Enter in a popup closes it and toggles the application window")
	root.push_input(_key(), true)
	for _frame in range(3): await process_frame
	check(root.mode == Window.MODE_WINDOWED, "returning from popup fullscreen restores windowed mode")
	popup.free()
	field.free()
	for failure in failures: push_error(failure)
	print("Native window/Alt+Enter: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.alt_pressed = true
	event.pressed = true
	return event

func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
