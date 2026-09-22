class_name RoRHUDControls
extends Control

const InterfaceLayout := preload("res://scripts/interface_layout.gd")

signal formation_requested(formation_name: String)
signal build_requested(building_kind: String)
signal train_requested(unit_kind: String, building_id: int)
signal research_requested(technology_id: int, building_id: int)
signal cancel_production_requested(building_id: int, queue_index: int)
signal trade_resource_requested(resource_type_id: int)
signal unit_action_requested(action_name: String)

const HUD_HEIGHT: float = InterfaceLayout.BOTTOM_HEIGHT
const FORMATIONS := [
	["LINE", "F5 LINE", "Line formation"],
	["RECTANGLE", "F6 BLOCK", "Compact block formation"],
	["COLUMN", "F7 COLUMN", "Narrow column formation"],
	["WEDGE", "F8 WEDGE", "Wedge formation"],
	["STAGGERED", "F9 STAGGER", "Staggered formation"],
]
const FORMATION_SHORT_LABELS := {
	"LINE": "ЛИН",
	"RECTANGLE": "КАРЕ",
	"COLUMN": "КОЛ",
	"WEDGE": "КЛИН",
	"STAGGERED": "ШАХ",
}

var formation_buttons: Dictionary = {}
var train_button: Button
var train_buttons: Array[Button] = []
var active_train_commands: Array = []
var formation_group := ButtonGroup.new()
var icon_registry
var interface_skin
var interface_style_index := 0
var current_layout: Dictionary = {}
var current_model: Dictionary = {}
var selection_context := ""
var build_menu_open := false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_controls()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and not formation_buttons.is_empty():
		current_layout = InterfaceLayout.for_viewport(size)
		layout_controls()

func build_controls() -> void:
	for index in range(FORMATIONS.size()):
		var definition: Array = FORMATIONS[index]
		var formation_name: String = definition[0]
		var button := Button.new()
		button.text = definition[1]
		button.tooltip_text = definition[2]
		button.toggle_mode = true
		button.button_group = formation_group
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		apply_button_theme(button)
		button.add_theme_font_size_override("font_size", 9)
		button.clip_text = true
		set_bottom_rect(button, Rect2(4, 4, 41, 31))
		button.pressed.connect(_on_formation_pressed.bind(formation_name))
		formation_buttons[formation_name] = button
		add_child(button)

	for index in range(18):
		var button := Button.new()
		button.visible = false
		button.tooltip_text = "Команда производства"
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		apply_button_theme(button)
		button.pressed.connect(_on_action_pressed.bind(index))
		train_buttons.append(button)
		add_child(button)
	train_button = train_buttons[0]


func configure_icons(registry) -> void:
	icon_registry = registry


func configure_interface_skin(skin, style_index: int = 0) -> void:
	interface_skin = skin
	interface_style_index = clampi(style_index, 0, 3)
	for button_value in formation_buttons.values() + train_buttons:
		apply_source_command_theme(button_value)


func set_layout(layout: Dictionary) -> void:
	current_layout = layout.duplicate(true)
	layout_controls()

func set_state(formation_name: String, can_train: bool) -> void:
	for key in formation_buttons:
		formation_buttons[key].visible = true
		formation_buttons[key].set_pressed_no_signal(key == formation_name)
	train_button.visible = true
	train_button.text = "[T] TRAIN CLUBMAN — 50 FOOD"
	layout_controls()
	train_button.disabled = not can_train


func set_view_model(model: Dictionary) -> void:
	current_model = model.duplicate(true)
	var selection: Dictionary = model.get("selection", {})
	var leader: Dictionary = selection.get("leader", {})
	var new_context := "%s:%d:%s" % [String(selection.get("category", "none")), int(leader.get("id", -1)), String(leader.get("kind", ""))]
	if new_context != selection_context:
		selection_context = new_context
		build_menu_open = false
	var formation_commands: Dictionary = {}
	active_train_commands.clear()
	var build_commands: Array = []
	for command_value in model.get("commands", []):
		var command: Dictionary = command_value
		match String(command.get("type", "")):
			"formation": formation_commands[String(command.get("id", ""))] = command
			"build": build_commands.append(command)
			"train", "research", "cancel_production", "trade_resource", "unit_action": active_train_commands.append(command)
	if not build_commands.is_empty():
		var unit_actions := active_train_commands.filter(func(command): return String(command.get("type", "")) == "unit_action")
		active_train_commands.clear()
		if build_menu_open:
			active_train_commands.append_array(build_commands)
			active_train_commands.append({"type": "close_build_menu", "id": "close_build_menu", "label": "Назад", "enabled": true, "reason": ""})
		else:
			active_train_commands.append({"type": "open_build_menu", "id": "open_build_menu", "label": "Строить", "enabled": true, "reason": ""})
			active_train_commands.append_array(unit_actions)
	for formation_name in formation_buttons:
		var button: Button = formation_buttons[formation_name]
		var command: Dictionary = formation_commands.get(formation_name, {})
		button.visible = not command.is_empty()
		if command.is_empty():
			continue
		button.text = "%s\n%s" % [String(command.get("hotkey", "")), String(FORMATION_SHORT_LABELS.get(formation_name, formation_name))]
		button.disabled = not bool(command.get("enabled", false))
		button.set_pressed_no_signal(bool(command.get("active", false)))
		button.tooltip_text = reason_text(String(command.get("reason", ""))) if button.disabled else String(command.get("label", formation_name))
	for index in range(train_buttons.size()):
		var button: Button = train_buttons[index]
		button.visible = index < active_train_commands.size()
		if not button.visible:
			continue
		var command: Dictionary = active_train_commands[index]
		var cost_text := String(command.get("cost_text", ""))
		var label := String(command.get("label", command.get("id", "")))
		var icon := command_icon(command)
		button.icon = icon
		button.expand_icon = false
		var hotkey := String(command.get("hotkey", ""))
		var short_label := String(command.get("short_label", label))
		button.text = "" if icon != null else "%s%s" % ["%s\n" % hotkey if not hotkey.is_empty() else "", short_label]
		button.disabled = not bool(command.get("enabled", false))
		var description := "%s%s" % [label, " — %s" % cost_text if not cost_text.is_empty() else ""]
		if float(command.get("duration", 0.0)) > 0.0:
			description += " · %.0f сек." % float(command.get("duration", 0.0))
		button.tooltip_text = reason_text(String(command.get("reason", ""))) if button.disabled else description
	layout_controls()


func layout_controls() -> void:
	if current_layout.is_empty():
		current_layout = InterfaceLayout.for_viewport(size)
	var command_rect: Rect2 = current_layout.get("command", Rect2(4, size.y - HUD_HEIGHT + 4, 300, HUD_HEIGHT - 8))
	var local_rect := Rect2(command_rect.position - Vector2(0, size.y - HUD_HEIGHT), command_rect.size)
	var cell_size := Vector2(54, 54)
	var columns := 5
	var slot := 0
	for button in train_buttons:
		if not button.visible:
			continue
		var column := slot % columns
		var row := slot / columns
		set_bottom_rect(button, Rect2(local_rect.position + Vector2(column * cell_size.x, row * cell_size.y), cell_size))
		slot += 1
	for formation_name in formation_buttons:
		var button: Button = formation_buttons[formation_name]
		if not button.visible:
			continue
		var column := slot % columns
		var row := slot / columns
		set_bottom_rect(button, Rect2(local_rect.position + Vector2(column * cell_size.x, row * cell_size.y), cell_size))
		slot += 1

func set_bottom_rect(control: Control, rectangle: Rect2) -> void:
	control.anchor_left = 0.0
	control.anchor_right = 0.0
	control.anchor_top = 1.0
	control.anchor_bottom = 1.0
	control.offset_left = rectangle.position.x
	control.offset_right = rectangle.end.x
	control.offset_top = -HUD_HEIGHT + rectangle.position.y
	control.offset_bottom = -HUD_HEIGHT + rectangle.end.y

func apply_button_theme(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("fff1bd"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_pressed_color", Color("fff5c9"))
	button.add_theme_color_override("font_disabled_color", Color("8c826d"))
	button.add_theme_stylebox_override("normal", make_style(Color("725b37"), Color("d7bd7c")))
	button.add_theme_stylebox_override("hover", make_style(Color("8a7044"), Color("f1d890")))
	button.add_theme_stylebox_override("pressed", make_style(Color("9b7c42"), Color("fff1bd")))
	button.add_theme_stylebox_override("disabled", make_style(Color("443b2d"), Color("746850")))


func apply_source_command_theme(button: Button) -> void:
	if interface_skin == null:
		return
	var backplate: Texture2D = interface_skin.square_command_backplate(interface_style_index)
	if backplate == null:
		return
	button.add_theme_stylebox_override("normal", texture_style(backplate, Color.WHITE))
	button.add_theme_stylebox_override("hover", texture_style(backplate, Color(1.08, 1.08, 1.08, 1.0)))
	button.add_theme_stylebox_override("pressed", texture_style(backplate, Color(0.78, 0.78, 0.78, 1.0)))
	button.add_theme_stylebox_override("disabled", texture_style(backplate, Color(0.48, 0.48, 0.48, 1.0)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func texture_style(texture: Texture2D, modulation: Color) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = modulation
	return style


func command_icon(command: Dictionary) -> Texture2D:
	var command_type := String(command.get("type", ""))
	if interface_skin != null and command_type == "open_build_menu":
		var glyphs: Array = interface_skin.source_candidate(50721).get("frames", [])
		return glyphs[0] if not glyphs.is_empty() else null
	if interface_skin != null and command_type == "cancel_production":
		var glyphs: Array = interface_skin.source_candidate(50721).get("frames", [])
		return glyphs[10] if glyphs.size() > 10 else null
	if interface_skin != null and command_type == "close_build_menu":
		var arrows: Array = interface_skin.command_arrow_frames(interface_style_index)
		return arrows[2] if arrows.size() > 2 else null
	return icon_registry.texture(String(command.get("icon_kind", "")), int(command.get("icon_id", -1))) if icon_registry != null else null

func make_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	return style

func _on_formation_pressed(formation_name: String) -> void:
	formation_requested.emit(formation_name)


func _on_action_pressed(index: int) -> void:
	if index < 0 or index >= active_train_commands.size():
		return
	var command: Dictionary = active_train_commands[index]
	match String(command.get("type", "")):
		"open_build_menu":
			build_menu_open = true
			set_view_model(current_model)
		"close_build_menu":
			build_menu_open = false
			set_view_model(current_model)
		"build":
			build_menu_open = false
			build_requested.emit(String(command.get("id", "")))
		"train": train_requested.emit(String(command.get("id", "")), int(command.get("building_id", -1)))
		"research": research_requested.emit(int(command.get("technology_id", -1)), int(command.get("building_id", -1)))
		"cancel_production": cancel_production_requested.emit(int(command.get("building_id", -1)), int(command.get("queue_index", 0)))
		"trade_resource": trade_resource_requested.emit(int(command.get("resource_type_id", -1)))
		"unit_action": unit_action_requested.emit(String(command.get("id", "")))


static func reason_text(reason: String) -> String:
	return String({
		"single_unit": "Для строя выберите несколько юнитов",
		"battle_over": "Матч завершён",
		"insufficient_resources": "Недостаточно ресурсов",
		"population_cap": "Достигнут предел населения",
		"queue_full": "Очередь заполнена",
		"unit_unavailable": "Юнит ещё не открыт",
		"building_unavailable": "Здание ещё не открыто",
		"invalid_production_building": "Здание не может производить этот юнит",
	}.get(reason, reason))
