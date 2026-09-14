class_name RoRHUDModalOverlay
extends Control

signal close_requested
signal resign_requested
signal launcher_requested

const MODE_NONE := ""
const MODE_MENU := "menu"
const MODE_DIPLOMACY := "diplomacy"

var interface_skin
var localization
var style_index := 0
var active_mode := MODE_NONE
var latest_snapshot: Dictionary = {}
var match_definition: Dictionary = {}

var shade: ColorRect
var menu_panel: PanelContainer
var diplomacy_panel: PanelContainer
var diplomacy_rows: VBoxContainer
var resume_button: Button
var resign_button: Button
var launcher_button: Button
var diplomacy_close_button: Button


func _init() -> void:
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(false)
	_build_interface()
	visible = false


func configure(skin, definition: Dictionary, requested_style_index: int = 0, localization_catalog = null) -> void:
	interface_skin = skin
	localization = localization_catalog
	match_definition = definition.duplicate(true)
	style_index = clampi(requested_style_index, 0, 3)
	for button in [resume_button, resign_button, launcher_button, diplomacy_close_button]:
		_apply_source_button_style(button)


func set_viewport_size(viewport_size: Vector2) -> void:
	position = Vector2.ZERO
	size = viewport_size


func set_snapshot(snapshot: Dictionary) -> void:
	latest_snapshot = snapshot.duplicate(true)
	if active_mode == MODE_DIPLOMACY:
		_rebuild_diplomacy_rows()


func show_menu() -> void:
	active_mode = MODE_MENU
	menu_panel.visible = true
	diplomacy_panel.visible = false
	visible = true
	set_process_unhandled_input(true)
	if is_inside_tree():
		resume_button.grab_focus()


func show_diplomacy() -> void:
	active_mode = MODE_DIPLOMACY
	menu_panel.visible = false
	diplomacy_panel.visible = true
	_rebuild_diplomacy_rows()
	visible = true
	set_process_unhandled_input(true)
	if is_inside_tree():
		diplomacy_close_button.grab_focus()


func close() -> void:
	active_mode = MODE_NONE
	visible = false
	set_process_unhandled_input(false)


func is_blocking() -> bool:
	return visible and active_mode != MODE_NONE


func _unhandled_input(event: InputEvent) -> void:
	if not is_blocking():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_requested.emit()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.66)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	menu_panel = _center_panel(Vector2(360, 260))
	var menu_column := _panel_column(menu_panel)
	menu_column.add_child(_heading("МЕНЮ"))
	resume_button = _action_button("ПРОДОЛЖИТЬ")
	resume_button.pressed.connect(func(): close_requested.emit())
	menu_column.add_child(_centered(resume_button))
	resign_button = _action_button("СДАТЬСЯ")
	resign_button.pressed.connect(func(): resign_requested.emit())
	menu_column.add_child(_centered(resign_button))
	launcher_button = _action_button("ВЫБОР ИГРЫ")
	launcher_button.pressed.connect(func(): launcher_requested.emit())
	menu_column.add_child(_centered(launcher_button))
	add_child(menu_panel)

	diplomacy_panel = _center_panel(Vector2(610, 410))
	var diplomacy_column := _panel_column(diplomacy_panel)
	diplomacy_column.add_child(_heading("ДИПЛОМАТИЯ"))
	var note := Label.new()
	note.text = "Текущие отношения игроков"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("c9b98e"))
	diplomacy_column.add_child(note)
	diplomacy_rows = VBoxContainer.new()
	diplomacy_rows.custom_minimum_size = Vector2(540, 220)
	diplomacy_rows.add_theme_constant_override("separation", 4)
	diplomacy_column.add_child(diplomacy_rows)
	diplomacy_close_button = _action_button("ЗАКРЫТЬ")
	diplomacy_close_button.pressed.connect(func(): close_requested.emit())
	diplomacy_column.add_child(_centered(diplomacy_close_button))
	add_child(diplomacy_panel)


func _rebuild_diplomacy_rows() -> void:
	for child in diplomacy_rows.get_children():
		child.queue_free()
	var state: Dictionary = latest_snapshot.get("player_state", {})
	var own_team := int(state.get("team", match_definition.get("local_team", 1)))
	var allies: Array = state.get("allies", [own_team])
	var players: Array = state.get("players", match_definition.get("players", []))
	if players.is_empty():
		diplomacy_rows.add_child(_row_label("Нет других активных игроков", Color("dfd0aa")))
		return
	for player_value in players:
		var player: Dictionary = player_value
		var team := int(player.get("team", 0))
		if team <= 0:
			continue
		var relation := "ВЫ" if team == own_team else ("СОЮЗНИК" if team in allies else "ПРОТИВНИК")
		var relation_color := Color("f0d782") if team == own_team else (Color("85cf80") if team in allies else Color("e57b68"))
		var definition := _player_definition(team)
		var civilization_id := int(player.get("civilization_id", definition.get("civilization_id", -1)))
		var controller := String(player.get("controller", definition.get("controller", "ai")))
		var status := _status_label(String(player.get("status", "active")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var identity := _row_label("Игрок %d   ·   %s" % [team, _civilization_name(civilization_id)], Color("efe2c0"))
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(identity)
		var control_label := _row_label("ЧЕЛОВЕК" if controller == "human" else "КОМПЬЮТЕР", Color("b9aa85"))
		control_label.custom_minimum_size.x = 105
		row.add_child(control_label)
		var status_label := _row_label(status, Color("b9aa85"))
		status_label.custom_minimum_size.x = 85
		row.add_child(status_label)
		var relation_label := _row_label(relation, relation_color)
		relation_label.custom_minimum_size.x = 105
		relation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(relation_label)
		diplomacy_rows.add_child(row)


func _player_definition(team: int) -> Dictionary:
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if int(player.get("team", 0)) == team:
			return player
	return {}


func _status_label(status: String) -> String:
	return {
		"active": "В ИГРЕ",
		"resigned": "СДАЛСЯ",
		"defeated": "ПОБЕЖДЁН",
		"victorious": "ПОБЕДИТЕЛЬ",
	}.get(status, status.to_upper())


func _civilization_name(civilization_id: int) -> String:
	# The Genie language table uses 10231..10242 for AoE civilizations and
	# 10246..10249 for the four Rise of Rome additions.
	var name_id := 10230 + civilization_id if civilization_id <= 12 else 10233 + civilization_id
	if localization != null and civilization_id > 0:
		var translated := String(localization.text(name_id, "ru"))
		if not translated.begins_with("["):
			return translated
	return "Цивилизация %d" % civilization_id


func _center_panel(panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", _panel_style())
	return panel


func _panel_column(panel: PanelContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 13)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	margin.add_child(column)
	panel.add_child(margin)
	return column


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("ecd28b"))
	return label


func _action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(108, 20)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", Color("20180f"))
	button.add_theme_color_override("font_hover_color", Color("20180f"))
	button.add_theme_color_override("font_pressed_color", Color("20180f"))
	return button


func _centered(child: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(child)
	return center


func _row_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", color)
	return label


func _apply_source_button_style(button: Button) -> void:
	if interface_skin == null:
		return
	var source: Dictionary = interface_skin.menu_button(style_index, true)
	if source.is_empty():
		return
	button.add_theme_stylebox_override("normal", _texture_style(source["normal"]))
	button.add_theme_stylebox_override("hover", _texture_style(source["normal"]))
	button.add_theme_stylebox_override("pressed", _texture_style(source["pressed"]))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _texture_style(texture: Texture2D) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("160f09")
	style.border_color = Color("b99859")
	style.set_border_width_all(2)
	return style
