class_name RoRTopBarControls
extends Control

signal diplomacy_requested
signal menu_requested

var diplomacy_button: Button
var menu_button: Button
var interface_skin
var style_index := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	diplomacy_button = create_button("Дипломатия")
	menu_button = create_button("Меню")
	diplomacy_button.pressed.connect(func(): diplomacy_requested.emit())
	menu_button.pressed.connect(func(): menu_requested.emit())
	add_child(diplomacy_button)
	add_child(menu_button)


func configure(skin, requested_style_index: int = 0) -> void:
	interface_skin = skin
	style_index = clampi(requested_style_index, 0, 4)
	apply_text_colors()
	apply_source_style(diplomacy_button, true)
	apply_source_style(menu_button, false)
	layout_controls()


func set_viewport_size(viewport_size: Vector2) -> void:
	position = Vector2.ZERO
	size = viewport_size
	layout_controls()


func layout_controls() -> void:
	if diplomacy_button == null or menu_button == null:
		return
	var small_size := Vector2(72, 20)
	var medium_size := Vector2(108, 20)
	if interface_skin != null:
		var small: Dictionary = interface_skin.menu_button(style_index, false)
		var medium: Dictionary = interface_skin.menu_button(style_index, true)
		small_size = small.get("size", small_size)
		medium_size = medium.get("size", medium_size)
	set_control_rect(menu_button, Rect2(Vector2(size.x - small_size.x, 0), small_size))
	set_control_rect(diplomacy_button, Rect2(Vector2(size.x - small_size.x - medium_size.x, 0), medium_size))


func create_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color("20180f"))
	button.add_theme_color_override("font_hover_color", Color("20180f"))
	button.add_theme_color_override("font_pressed_color", Color("20180f"))
	return button


func apply_text_colors() -> void:
	if interface_skin == null:
		return
	var text_color: Color = interface_skin.text_color(style_index)
	var hover_color := text_color.lightened(0.12)
	var pressed_color := text_color.darkened(0.08)
	for button in [diplomacy_button, menu_button]:
		button.add_theme_color_override("font_color", text_color)
		button.add_theme_color_override("font_hover_color", hover_color)
		button.add_theme_color_override("font_pressed_color", pressed_color)


func apply_source_style(button: Button, medium: bool) -> void:
	if interface_skin == null:
		return
	var source: Dictionary = interface_skin.menu_button(style_index, medium)
	if source.is_empty():
		return
	button.add_theme_stylebox_override("normal", texture_style(source["normal"]))
	button.add_theme_stylebox_override("hover", texture_style(source["normal"]))
	button.add_theme_stylebox_override("pressed", texture_style(source["pressed"]))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	return style


func set_control_rect(control: Control, rectangle: Rect2) -> void:
	control.position = rectangle.position
	control.size = rectangle.size
