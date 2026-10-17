class_name RoRMatchMenuTheme
extends RefCounted

# Match menus reuse the launcher's artwork and typography. Their padding and
# checkbox fixes are isolated here; the launcher's shared theme stays intact.
const Antique := preload("res://scripts/antique_ui_theme.gd")
const Typography := preload("res://scripts/launcher_typography.gd")
const INK := Antique.INK
const BRONZE := Antique.BRONZE
const LIGHT_TEXT := Antique.LIGHT_TEXT
const CHECKED := preload("res://assets/ui/antique/checkbox_checked.svg")
const UNCHECKED := preload("res://assets/ui/antique/checkbox_unchecked.svg")
const OPTION_ARROW := preload("res://assets/ui/antique/option_arrow.svg")
static var _theme: Theme
static var _styles: Dictionary = {}

static func screen_panel_style() -> StyleBoxFlat:
	var style := preload("res://scripts/launcher_theme.gd").panel_style()
	style.bg_color = Color(0.065, 0.040, 0.020, 0.52)
	return style

static func button_style(state: String = "normal") -> StyleBoxTexture:
	if _styles.has(state): return _styles[state]
	var style: StyleBoxTexture = Antique.button_style(state, true).duplicate()
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	_styles[state] = style
	return style

static func shared_theme() -> Theme:
	if _theme != null: return _theme
	_theme = Antique.shared_theme().duplicate()
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			_theme.set_stylebox(state, type, button_style(state))
	_theme.set_icon("arrow", "OptionButton", OPTION_ARROW)
	_theme.set_constant("arrow_margin", "OptionButton", 14)
	_theme.set_constant("h_separation", "OptionButton", 8)
	_theme.set_constant("modulate_arrow", "OptionButton", 0)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		_theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	_theme.set_stylebox("focus", "CheckBox", Antique.focus_style())
	for type in ["CheckBox", "Tree"]:
		for icon in ["checked", "checked_disabled"]: _theme.set_icon(icon, type, CHECKED)
		for icon in ["unchecked", "unchecked_disabled"]: _theme.set_icon(icon, type, UNCHECKED)
	_theme.set_font("font", "CheckBox", Typography.body_font())
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_theme.set_color(key, "CheckBox", LIGHT_TEXT)
	_theme.set_color("font_disabled_color", "CheckBox", Antique.INK_MUTED)
	_theme.set_constant("h_separation", "CheckBox", 10)
	_theme.set_stylebox("normal", "LineEdit", button_style())
	_theme.set_stylebox("panel", "ItemList", button_style())
	_theme.set_stylebox("panel", "PopupMenu", button_style())
	_theme.set_stylebox("panel", "TooltipPanel", button_style())
	return _theme

static func apply_button(button: Button, font_size: int = 15, _compact: bool = true) -> void:
	Antique.apply_button(button, font_size, true)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, button_style(state))

static func apply_option(option: OptionButton, font_size: int = 15) -> void:
	apply_button(option, font_size)
	option.custom_minimum_size.x = maxf(150, option.custom_minimum_size.x)
	option.add_theme_font_override("font", Typography.body_font())
	option.fit_to_longest_item = false
	option.clip_text = true
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	option.add_theme_icon_override("arrow", OPTION_ARROW)
	option.add_theme_constant_override("arrow_margin", 14)
	option.add_theme_constant_override("h_separation", 8)
	option.add_theme_constant_override("modulate_arrow", 0)
	option.get_popup().theme = shared_theme()

static func apply_line_edit(field: LineEdit) -> void:
	Antique.apply_line_edit(field)
	field.add_theme_stylebox_override("normal", button_style())
	field.add_theme_stylebox_override("focus", button_style("hover"))

static func apply_checkbox(check_box: CheckBox, font_size: int = 15) -> void:
	check_box.theme = shared_theme()
	check_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	check_box.custom_minimum_size.y = 32
	check_box.add_theme_font_override("font", Typography.body_font())
	check_box.add_theme_font_size_override("font_size", font_size)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		check_box.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	check_box.add_theme_stylebox_override("focus", Antique.focus_style())
