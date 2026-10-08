class_name RoRAntiqueUITheme
extends RefCounted

const Typography := preload("res://scripts/launcher_typography.gd")
const PLAQUE := preload("res://assets/ui/antique/marble_plaque.svg")
const TILE := preload("res://assets/ui/antique/marble_tile.svg")
const INK := Color("383a35")
const INK_MUTED := Color("75756a")
const BRONZE := Color("94733f")
const LIGHT_TEXT := Color("ede7d7")
static var _shared_theme: Theme
static var _styles: Dictionary = {}


static func shared_theme() -> Theme:
	if _shared_theme != null:
		return _shared_theme
	_shared_theme = Theme.new()
	_shared_theme.default_font = Typography.body_font()
	_shared_theme.default_font_size = 15
	for type in ["Button", "OptionButton"]:
		_shared_theme.set_font("font", type, Typography.title_font())
		_shared_theme.set_font_size("font_size", type, 14)
		for state in ["normal", "hover", "pressed", "disabled"]:
			_shared_theme.set_stylebox(state, type, button_style(state, true))
		_shared_theme.set_stylebox("focus", type, focus_style())
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_shared_theme.set_color(key, type, INK)
		_shared_theme.set_color("font_disabled_color", type, INK_MUTED)
	for type in ["LineEdit", "ItemList"]:
		_shared_theme.set_stylebox("normal" if type == "LineEdit" else "panel", type, card_style())
		_shared_theme.set_stylebox("focus", type, focus_style())
		_shared_theme.set_color("font_color", type, INK)
	_shared_theme.set_color("font_placeholder_color", "LineEdit", INK_MUTED)
	_shared_theme.set_color("caret_color", "LineEdit", INK)
	_shared_theme.set_color("font_selected_color", "LineEdit", Color.WHITE)
	_shared_theme.set_color("selection_color", "LineEdit", Color("8b795b"))
	_shared_theme.set_color("font_selected_color", "ItemList", INK)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color("d6ccb6")
	selected.border_color = BRONZE
	selected.set_border_width_all(1)
	selected.content_margin_left = 8
	selected.content_margin_right = 8
	selected.content_margin_top = 6
	selected.content_margin_bottom = 6
	_shared_theme.set_stylebox("selected", "ItemList", selected)
	_shared_theme.set_stylebox("selected_focus", "ItemList", selected)
	_shared_theme.set_constant("v_separation", "ItemList", 8)
	_shared_theme.set_font("font", "PopupMenu", Typography.body_font())
	_shared_theme.set_font_size("font_size", "PopupMenu", 15)
	_shared_theme.set_stylebox("panel", "PopupMenu", card_style())
	_shared_theme.set_stylebox("hover", "PopupMenu", selected)
	_shared_theme.set_color("font_color", "PopupMenu", INK)
	_shared_theme.set_color("font_hover_color", "PopupMenu", INK)
	_shared_theme.set_color("font_disabled_color", "PopupMenu", INK_MUTED)
	_shared_theme.set_font("font", "TooltipLabel", Typography.body_font())
	_shared_theme.set_font_size("font_size", "TooltipLabel", 15)
	_shared_theme.set_color("font_color", "TooltipLabel", INK)
	_shared_theme.set_stylebox("panel", "TooltipPanel", card_style())
	return _shared_theme


static func apply_button(button: Button, font_size: int = 14, compact: bool = false, square: bool = false) -> void:
	button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Typography.title_font())
	button.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, INK)
	button.add_theme_color_override("font_disabled_color", INK_MUTED)
	button.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.75))
	button.add_theme_constant_override("shadow_offset_x", 0)
	button.add_theme_constant_override("shadow_offset_y", 1)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, button_style(state, compact, square))
	button.add_theme_stylebox_override("focus", focus_style())


static func apply_option(option: OptionButton, font_size: int = 14) -> void:
	apply_button(option, font_size, true)
	option.add_theme_font_override("font", Typography.body_font())
	option.get_popup().theme = shared_theme()


static func apply_line_edit(field: LineEdit, font_size: int = 15) -> void:
	field.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	field.add_theme_font_override("font", Typography.body_font())
	field.add_theme_font_size_override("font_size", font_size)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", INK_MUTED)
	field.add_theme_color_override("caret_color", INK)
	field.add_theme_color_override("selection_color", Color("8b795b"))
	field.add_theme_color_override("font_selected_color", Color.WHITE)
	field.add_theme_stylebox_override("normal", card_style())
	field.add_theme_stylebox_override("focus", field_focus_style())
	field.add_theme_stylebox_override("read_only", button_style("disabled", true))


static func button_style(state: String = "normal", compact: bool = false, square: bool = false) -> StyleBoxTexture:
	var key := "%s:%s:%s" % [state, compact, square]
	if _styles.has(key):
		return _styles[key]
	var style := StyleBoxTexture.new()
	style.texture = TILE if square else PLAQUE
	style.set_texture_margin_all(7.0)
	style.modulate_color = Color("fff7e1") if state == "hover" else Color("c5bcaa") if state == "pressed" else Color("b5b3a9") if state == "disabled" else Color.WHITE
	style.content_margin_left = 4.0 if square else 7.0 if compact else 16.0
	style.content_margin_right = style.content_margin_left
	style.content_margin_top = 2.0 if compact else 7.0
	style.content_margin_bottom = style.content_margin_top
	_styles[key] = style
	return style


static func card_style() -> StyleBoxTexture:
	return button_style("normal", true)


static func focus_style() -> StyleBoxFlat:
	if _styles.has("focus"):
		return _styles["focus"]
	var style := StyleBoxFlat.new()
	style.bg_color = Color.TRANSPARENT
	style.border_color = BRONZE
	style.set_border_width_all(2)
	style.set_expand_margin_all(1.0)
	_styles["focus"] = style
	return style


static func field_focus_style() -> StyleBoxTexture:
	return button_style("hover", true)


static func engraved_label(label: Label, title: bool = false, font_size: int = 14) -> void:
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_override("font", Typography.title_font() if title else Typography.body_font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.65))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 1)
