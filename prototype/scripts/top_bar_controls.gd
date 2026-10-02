class_name RoRTopBarControls
extends Control

const InterfaceLayout := preload("res://scripts/interface_layout.gd")
const Typography := preload("res://scripts/hud_typography.gd")
const POPULATION_ICON := preload("res://assets/ui/hud/population.png")
const POPULATION_SHADER := preload("res://assets/ui/hud/population.gdshader")

signal diplomacy_requested
signal menu_requested

var diplomacy_button: Button
var menu_button: Button
var age_label: Label
var population_well: Control
var population_glyph: TextureRect
var interface_skin
var style_index := 0
var current_model: Dictionary = {}
var resource_rects: Dictionary = {}
var population_rectangle := Rect2()
var top_texture: Texture2D
var command_texture: Texture2D
var resource_textures: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	diplomacy_button = create_button("Дипломатия")
	menu_button = create_button("Меню")
	diplomacy_button.pressed.connect(func(): diplomacy_requested.emit())
	menu_button.pressed.connect(func(): menu_requested.emit())
	add_child(diplomacy_button)
	add_child(menu_button)
	age_label = Label.new()
	age_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	age_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	age_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	age_label.add_theme_font_override("font", Typography.title_font())
	age_label.add_theme_font_size_override("font_size", 15)
	add_child(age_label)
	population_well = Control.new()
	population_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	population_well.clip_contents = true
	add_child(population_well)
	population_glyph = TextureRect.new()
	population_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	population_glyph.texture = POPULATION_ICON
	population_glyph.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	population_glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	population_glyph.position = Vector2(-1, -1)
	population_glyph.size = Vector2(23, 23)
	var mask := ShaderMaterial.new()
	mask.shader = POPULATION_SHADER
	population_glyph.material = mask
	population_well.add_child(population_glyph)


func configure(skin, requested_style_index: int = 0) -> void:
	interface_skin = skin
	style_index = clampi(requested_style_index, 0, 4)
	top_texture = skin.flat_top_texture(style_index)
	command_texture = skin.square_command_backplate(style_index)
	for key in ["wood", "food", "gold", "stone"]:
		resource_textures[key] = skin.resource_icon(key, style_index)
	apply_text_colors()
	apply_source_style(diplomacy_button, true)
	apply_source_style(menu_button, false)
	layout_controls()


func set_view_model(model: Dictionary) -> void:
	current_model = model
	age_label.text = String(model.get("age", {}).get("label", ""))
	layout_controls()
	queue_redraw()


func set_viewport_size(viewport_size: Vector2) -> void:
	position = Vector2.ZERO
	size = viewport_size
	layout_controls()


func layout_controls() -> void:
	if menu_button == null:
		return
	var narrow := size.x < 720.0
	var button_y := 36.0 if narrow else 6.0
	set_control_rect(menu_button, Rect2(size.x - 80, button_y, 72, 20 if not narrow else 24))
	set_control_rect(diplomacy_button, Rect2(8 if narrow else size.x - 192, button_y, 108, 20 if not narrow else 24))
	set_control_rect(age_label, Rect2(size.x * 0.5 - 100, 38 if narrow else 6, 200, 20))
	var font_size := resource_font_size()
	var gap := 3.0 if narrow else 4.0 if size.x < 840.0 else 8.0 if size.x < 960.0 else 12.0
	var x := 8.0
	resource_rects.clear()
	for key in ["wood", "food", "gold", "stone"]:
		var text := amount_text(int(current_model.get("resources", {}).get(key, 0)))
		var measured := Typography.body_font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var width := 70.0 if size.x >= 960 else 27.0 + measured
		resource_rects[key] = Rect2(x, 4, width, 24)
		x += width + gap
	var counter_text := population_text()
	var population_width := Typography.body_font().get_string_size(counter_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	population_rectangle = Rect2(x, 4, 27 + population_width, 24)
	population_well.position = Vector2(x, 6)
	population_well.size = Vector2(21, 21)
	queue_redraw()


func resource_font_size() -> int:
	return 13 if size.x < 840 else 14 if size.x < 960 else 16


func amount_text(amount: int) -> String:
	var compact_threshold := 1000 if size.x < 430 else 10000 if size.x < 960 else 100000
	if amount >= 1000000:
		return ("%.1fM" % (float(amount) / 1000000.0)).replace(".0M", "M")
	if amount >= compact_threshold:
		return "%dK" % int(amount / 1000.0)
	return String.num_int64(amount)


func population_text() -> String:
	var population: Dictionary = current_model.get("population", {})
	return "%d/%d" % [int(population.get("current", 0)), int(population.get("cap", 0))]


func _draw() -> void:
	var height := 64.0 if size.x < 720 else 32.0
	var top_rect := Rect2(0, 0, size.x, height)
	draw_rect(top_rect, Color("393833"))
	if top_texture != null:
		draw_texture_rect(top_texture, top_rect, true)
	var text_color := Color("f4e6c7")
	var rim: Array[Color] = [Color("9b9b8c"), Color("35382f")]
	if interface_skin != null:
		text_color = interface_skin.text_color(style_index)
		rim = interface_skin.rim_colors(style_index)
	draw_line(Vector2.ZERO, Vector2(size.x, 0), rim[0])
	draw_line(Vector2(0, height - 1), Vector2(size.x, height - 1), rim[1])
	draw_line(Vector2(0, height - 2), Vector2(size.x, height - 2), rim[0])
	var body := Typography.body_font()
	for key in resource_rects:
		var rect: Rect2 = resource_rects[key]
		var icon: Texture2D = resource_textures.get(key)
		if icon != null:
			draw_texture_rect(icon, Rect2(rect.position + Vector2(0, 4), Vector2(22, 16)), false)
		draw_string(body, rect.position + Vector2(27, 17), amount_text(int(current_model.get("resources", {}).get(key, 0))), HORIZONTAL_ALIGNMENT_LEFT, -1, resource_font_size(), text_color)
	var well := Rect2(population_well.position, population_well.size)
	if command_texture != null:
		draw_texture_rect(command_texture, well, false)
	else:
		draw_rect(well, Color("191c17"))
	draw_rect(well, rim[0], false, 1)
	var indicators: Dictionary = current_model.get("status_indicators", {})
	var population_color := Color("dc815c") if bool(indicators.get("blocked", false)) else text_color
	draw_string(body, population_rectangle.position + Vector2(27, 17), population_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, resource_font_size(), population_color)


func create_button(label: String) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Typography.title_font())
	button.add_theme_font_size_override("font_size", 13)
	return button


func apply_text_colors() -> void:
	var text_color: Color = interface_skin.text_color(style_index) if interface_skin != null else Color("20180f")
	age_label.add_theme_color_override("font_color", text_color)
	for button in [diplomacy_button, menu_button]:
		button.add_theme_color_override("font_color", text_color)
		button.add_theme_color_override("font_hover_color", text_color.lightened(0.12))
		button.add_theme_color_override("font_pressed_color", text_color.darkened(0.08))


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
	style.content_margin_left = 3
	style.content_margin_right = 3
	return style


func set_control_rect(control: Control, rectangle: Rect2) -> void:
	control.position = rectangle.position
	control.size = rectangle.size
