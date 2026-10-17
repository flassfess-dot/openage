extends Node

signal mode_changed(fullscreen: bool)

const Preferences := preload("res://scripts/match_preferences.gd")
var windowed_size := Vector2i(1280, 720)
var windowed_position := Vector2i.ZERO
var windowed_mode := Window.MODE_WINDOWED
var persist_changes := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var preferences := Preferences.new()
	preferences.load_settings()
	windowed_size = preferences.values["screen_size"]
	windowed_position = get_window().position
	if DisplayServer.get_name() != "headless":
		apply_settings(bool(preferences.values["fullscreen"]), windowed_size)
	get_tree().node_added.connect(_watch_window)

func _watch_window(node: Node) -> void:
	if node is Window and node != get_window():
		node.window_input.connect(_popup_input.bind(node))

func _popup_input(event: InputEvent, window: Window) -> void:
	if not _is_toggle(event): return
	window.set_input_as_handled()
	if window is Popup: window.hide()
	toggle_fullscreen()

func is_fullscreen() -> bool:
	return get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]

func _input(event: InputEvent) -> void:
	if not _is_toggle(event): return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()

func _is_toggle(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and not event.ctrl_pressed and not event.meta_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]

func toggle_fullscreen() -> void:
	apply_settings(not is_fullscreen())
	if persist_changes:
		var preferences := Preferences.new()
		preferences.load_settings()
		preferences.save_settings({"fullscreen": is_fullscreen(), "screen_size": windowed_size})

func apply_settings(fullscreen: bool, requested_size: Vector2i = Vector2i.ZERO) -> void:
	var window := get_window()
	var was_fullscreen := is_fullscreen()
	if fullscreen and not was_fullscreen:
		windowed_position = window.position
		windowed_size = window.size
		windowed_mode = Window.MODE_MAXIMIZED if window.mode == Window.MODE_MAXIMIZED else Window.MODE_WINDOWED
	if requested_size != Vector2i.ZERO:
		windowed_size = Vector2i(maxi(640, requested_size.x), maxi(480, requested_size.y))
		windowed_mode = Window.MODE_WINDOWED
	if fullscreen:
		# MODE_FULLSCREEN is borderless, compositor-friendly fullscreen. It does
		# not use exclusive fullscreen or change the monitor's video mode.
		window.mode = Window.MODE_FULLSCREEN
	else:
		window.mode = Window.MODE_WINDOWED
		window.size = windowed_size
		if was_fullscreen:
			window.position = windowed_position
		else:
			window.move_to_center()
		if windowed_mode == Window.MODE_MAXIMIZED: window.mode = Window.MODE_MAXIMIZED
	mode_changed.emit(is_fullscreen())
