class_name RoRLauncherTheme
extends RefCounted

const AntiqueTheme := preload("res://scripts/antique_ui_theme.gd")
const Typography := preload("res://scripts/launcher_typography.gd")

const GOLD := Color("d5b96f")
const GOLD_BRIGHT := Color("ffe7a0")
const GOLD_DARK := Color("7b5a27")
const INK := Color("160f09")
const PARCHMENT := Color("c8a568")
const PANEL := Color(0.095, 0.065, 0.035, 0.95)
const PANEL_SOFT := Color(0.18, 0.115, 0.055, 0.94)
const MUTED := Color("918678")


static func apply_primary_button(button: Button, font_size: int = 18) -> void:
	button.custom_minimum_size = Vector2(300.0, 42.0)
	AntiqueTheme.apply_button(button, font_size)


static func apply_secondary_button(button: Button, font_size: int = 15) -> void:
	button.custom_minimum_size = Vector2(300.0, 42.0)
	AntiqueTheme.apply_button(button, font_size, true)


static func apply_option(option: OptionButton, minimum_width: float = 180.0) -> void:
	option.custom_minimum_size = Vector2(minimum_width, 34.0)
	option.fit_to_longest_item = false
	AntiqueTheme.apply_option(option)


static func apply_line_edit(line_edit: LineEdit, minimum_width: float = 180.0) -> void:
	line_edit.custom_minimum_size = Vector2(minimum_width, 34.0)
	AntiqueTheme.apply_line_edit(line_edit)


static func apply_spin_box(spin_box: SpinBox, minimum_width: float = 180.0) -> void:
	spin_box.custom_minimum_size = Vector2(minimum_width, 34.0)
	# The SpinBox owns the arrow gutter; its child must not impose the
	# same minimum width a second time and push the arrows outside the row.
	apply_line_edit(spin_box.get_line_edit(), 0.0)


static func panel_style(soft: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_SOFT if soft else PANEL
	style.border_color = GOLD_DARK
	style.set_border_width_all(2)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 8
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style


static func inset_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.037, 0.022, 0.92)
	style.border_color = Color("5f4524")
	style.set_border_width_all(1)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


static func progress_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("100b07")
	style.border_color = GOLD_DARK
	style.set_border_width_all(2)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style


static func progress_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("bd8f35")
	style.border_color = GOLD_BRIGHT
	style.set_border_width_all(1)
	style.corner_radius_top_left = 1
	style.corner_radius_top_right = 1
	style.corner_radius_bottom_left = 1
	style.corner_radius_bottom_right = 1
	return style


static func heading(label: Label, size: int = 24) -> void:
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_override("font", Typography.title_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("f3ecdc"))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)


static func caption(label: Label, size: int = 14) -> void:
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_override("font", Typography.body_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color("d3c9b3"))


static func body(label: Label, size: int = 14) -> void:
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_override("font", Typography.body_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", AntiqueTheme.LIGHT_TEXT)


static func field_style(background: Color = Color("24180d"), border: Color = GOLD_DARK) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


static func focus_style() -> StyleBoxFlat:
	return AntiqueTheme.focus_style()


static func _apply_button(button: Button, font_size: int, normal_color: Color, hover_color: Color, pressed_color: Color) -> void:
	button.custom_minimum_size = Vector2(300.0, 42.0)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", GOLD_BRIGHT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", GOLD_BRIGHT)
	button.add_theme_color_override("font_disabled_color", Color("766f65"))
	button.add_theme_stylebox_override("normal", _button_style(normal_color, GOLD_DARK))
	button.add_theme_stylebox_override("hover", _button_style(hover_color, GOLD_BRIGHT))
	button.add_theme_stylebox_override("pressed", _button_style(pressed_color, GOLD_BRIGHT, 2))
	button.add_theme_stylebox_override("focus", focus_style())
	button.add_theme_stylebox_override("disabled", _button_style(Color("24211d"), Color("514b43")))


static func _button_style(background: Color, border: Color, inset: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 12.0 + inset
	style.content_margin_right = 12.0 - inset
	style.content_margin_top = 6.0 + inset
	style.content_margin_bottom = 6.0 - inset
	return style
