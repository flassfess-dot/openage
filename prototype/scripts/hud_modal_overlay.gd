class_name RoRHUDModalOverlay
extends Control

signal close_requested
signal save_requested
signal load_requested
signal named_save_requested(name: String)
signal named_load_requested(path: String)
signal resign_requested
signal launcher_requested
signal diplomacy_relation_requested(target_team: int, relation: String)
signal tribute_requested(target_team: int, resource_type_id: int, amount: int)

const MODE_NONE := ""
const MODE_MENU := "menu"
const MODE_DIPLOMACY := "diplomacy"
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

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
var save_button: Button
var load_button: Button
var named_save_button: Button
var named_load_button: Button
var named_save_input: LineEdit
var named_load_options: OptionButton
var named_saves: Array[Dictionary] = []
var resign_button: Button
var launcher_button: Button
var diplomacy_close_button: Button
var menu_status: Label
var instructions_label: Label
var match_status_label: Label
var diplomacy_relation_buttons: Dictionary = {}


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
	instructions_label.text = instruction_summary(match_definition)
	style_index = clampi(requested_style_index, 0, 4)
	for button in [resume_button, save_button, load_button, named_save_button, named_load_button, resign_button, launcher_button, diplomacy_close_button]:
		_apply_source_button_style(button)


static func instruction_summary(definition: Dictionary) -> String:
	var settings: Dictionary = definition.get("skirmish_settings", {})
	var map: Dictionary = definition.get("map", {})
	var size_value: Variant = map.get("size", Vector2i.ZERO)
	var size := Vector2i.ZERO
	if size_value is Vector2i:
		size = size_value
	elif size_value is Array and size_value.size() >= 2:
		size = Vector2i(int(size_value[0]), int(size_value[1]))
	var catalog: Dictionary = SkirmishSettings.catalog()
	var map_type_id := String(settings.get("map_type_id", map.get("type_id", "")))
	var map_fallback := String({"coastal_land": "Побережье", "fixed_source": "Заданная карта"}.get(String(map.get("generator", {}).get("type", "")), "Тип не указан"))
	var map_type := _catalog_name(catalog.get("map_types", []), map_type_id, map_fallback)
	var age_id := String(settings.get("starting_age_id", ""))
	if age_id.is_empty():
		for player_value in definition.get("players", []):
			var player: Dictionary = player_value
			if int(player.get("team", 0)) == int(definition.get("local_team", 1)):
				age_id = String({100: "stone", 101: "tool", 102: "bronze", 103: "iron"}.get(int(player.get("starting_age_technology_id", 100)), "stone"))
				break
	if age_id.is_empty():
		age_id = "stone"
	var age := _catalog_name(catalog.get("starting_ages", []), age_id, "Не указан")
	var population_limit := int(settings.get("population_limit", 0))
	if population_limit <= 0:
		for player_value in definition.get("players", []):
			var player: Dictionary = player_value
			if int(player.get("team", 0)) == int(definition.get("local_team", 1)):
				population_limit = int(player.get("population_limit", 0))
				break
	if population_limit <= 0:
		population_limit = 50
	var victory_id := String(settings.get("victory_mode_id", ""))
	if victory_id.is_empty():
		var rules: Array = definition.get("victory_rules", [])
		victory_id = String(rules[0].get("type", "")) if rules.size() == 1 else "standard" if rules.size() > 1 else ""
	var victory := _catalog_name(catalog.get("victory_modes", []), victory_id, "Не указана")
	var full_tech_tree := bool(settings.get("full_tech_tree", definition.get("full_tech_tree", false)))
	return "Карта: %s · %d×%d · Seed: %d\nСтарт: %s · Лимит: %d\nПобеда: %s · Full Tech Tree: %s" % [map_type, size.x, size.y, int(map.get("seed", settings.get("seed", 0))), age, population_limit, victory, "Вкл." if full_tech_tree else "Выкл."]


static func _catalog_name(entries: Array, entry_id: String, fallback: String) -> String:
	for value in entries:
		var entry: Dictionary = value
		if String(entry.get("id", "")) == entry_id:
			return String(entry.get("name", fallback))
	return fallback


func set_viewport_size(viewport_size: Vector2) -> void:
	position = Vector2.ZERO
	size = viewport_size


func set_snapshot(snapshot: Dictionary) -> void:
	# Presentation snapshots are immutable after publication and replaced as a
	# whole by the main scene. Keeping the published reference avoids a deep copy
	# of fog cells and every overview entity on every simulation tick while the
	# menu is closed.
	latest_snapshot = snapshot
	resign_button.disabled = String(snapshot.get("player_state", {}).get("status", "active")) != "active" or bool(snapshot.get("battle_over", false))
	if active_mode == MODE_MENU:
		match_status_label.text = match_status_summary(snapshot)
	if active_mode == MODE_DIPLOMACY:
		_rebuild_diplomacy_rows()


func show_menu() -> void:
	active_mode = MODE_MENU
	match_status_label.text = match_status_summary(latest_snapshot)
	menu_panel.visible = true
	diplomacy_panel.visible = false
	visible = true
	set_process_unhandled_input(true)
	if is_inside_tree():
		resume_button.grab_focus()


func set_save_available(available: bool) -> void:
	load_button.disabled = not available
	load_button.tooltip_text = "" if available else "Сохранённая игра не найдена"


func set_named_saves(entries: Array[Dictionary]) -> void:
	named_saves = entries.duplicate(true)
	named_load_options.clear()
	for entry in named_saves:
		var label := "%s · такт %d" % [String(entry.get("slot_name", "")), int(entry.get("tick", 0))]
		var saved_at := int(entry.get("saved_at_unix", 0))
		if saved_at > 0:
			label += " · %s" % Time.get_datetime_string_from_unix_time(saved_at, true)
		named_load_options.add_item(label)
	named_load_button.disabled = named_saves.is_empty()
	named_load_options.disabled = named_saves.is_empty()
	if not named_saves.is_empty():
		named_load_options.select(0)


static func match_status_summary(snapshot: Dictionary) -> String:
	var result: Dictionary = snapshot.get("match_result", {})
	if bool(snapshot.get("battle_over", false)) or bool(result.get("over", false)):
		var winner := int(result.get("winner_team", -1))
		return "Матч завершён · победила команда %d" % winner if winner > 0 else "Матч завершён · ничья"
	var status := String(snapshot.get("player_state", {}).get("status", "active"))
	return "Режим наблюдателя · управление недоступно" if status in ["resigned", "defeated"] else "Матч продолжается"


func set_menu_status(text: String, failed: bool = false) -> void:
	menu_status.text = text
	menu_status.add_theme_color_override("font_color", Color("e57b68") if failed else Color("85cf80"))


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

	menu_panel = _center_panel(Vector2(500, 570))
	var menu_column := _panel_column(menu_panel)
	menu_column.add_child(_heading("МЕНЮ"))
	instructions_label = Label.new()
	instructions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions_label.add_theme_font_size_override("font_size", 11)
	instructions_label.add_theme_color_override("font_color", Color("d7c49b"))
	instructions_label.custom_minimum_size = Vector2(420, 52)
	menu_column.add_child(instructions_label)
	match_status_label = Label.new()
	match_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_status_label.add_theme_font_size_override("font_size", 12)
	match_status_label.add_theme_color_override("font_color", Color("d7c49b"))
	menu_column.add_child(match_status_label)
	resume_button = _action_button("ПРОДОЛЖИТЬ")
	resume_button.pressed.connect(func(): close_requested.emit())
	menu_column.add_child(_centered(resume_button))
	save_button = _action_button("СОХРАНИТЬ")
	save_button.pressed.connect(func(): save_requested.emit())
	menu_column.add_child(_centered(save_button))
	load_button = _action_button("ЗАГРУЗИТЬ")
	load_button.pressed.connect(func(): load_requested.emit())
	menu_column.add_child(_centered(load_button))
	var named_heading := _row_label("Именованные сохранения", Color("d7c49b"))
	named_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_column.add_child(named_heading)
	named_save_input = LineEdit.new()
	named_save_input.placeholder_text = "Имя сохранения (до 64 символов)"
	named_save_input.max_length = 64
	menu_column.add_child(named_save_input)
	named_save_button = _action_button("СОХРАНИТЬ КАК")
	named_save_button.pressed.connect(func(): named_save_requested.emit(named_save_input.text))
	menu_column.add_child(_centered(named_save_button))
	named_load_options = OptionButton.new()
	named_load_options.disabled = true
	menu_column.add_child(named_load_options)
	named_load_button = _action_button("ЗАГРУЗИТЬ ВЫБРАННОЕ")
	named_load_button.disabled = true
	named_load_button.pressed.connect(func():
		var selected := named_load_options.get_selected_id()
		if selected >= 0 and selected < named_saves.size():
			named_load_requested.emit(String(named_saves[selected].get("path", "")))
	)
	menu_column.add_child(_centered(named_load_button))
	resign_button = _action_button("СДАТЬСЯ")
	resign_button.pressed.connect(func(): resign_requested.emit())
	menu_column.add_child(_centered(resign_button))
	launcher_button = _action_button("ВЫБОР ИГРЫ")
	launcher_button.pressed.connect(func(): launcher_requested.emit())
	menu_column.add_child(_centered(launcher_button))
	menu_status = Label.new()
	menu_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_status.add_theme_font_size_override("font_size", 12)
	menu_status.add_theme_color_override("font_color", Color("85cf80"))
	menu_column.add_child(menu_status)
	add_child(menu_panel)

	diplomacy_panel = _center_panel(Vector2(610, 410))
	var diplomacy_column := _panel_column(diplomacy_panel)
	diplomacy_column.add_child(_heading("ДИПЛОМАТИЯ"))
	var note := Label.new()
	note.text = "Выберите отношение к каждому игроку"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color("c9b98e"))
	diplomacy_column.add_child(note)
	diplomacy_rows = VBoxContainer.new()
	diplomacy_rows.custom_minimum_size = Vector2(540, 220)
	diplomacy_rows.add_theme_constant_override("separation", 4)
	var diplomacy_scroll := ScrollContainer.new()
	diplomacy_scroll.custom_minimum_size = Vector2(540, 250)
	diplomacy_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	diplomacy_scroll.add_child(diplomacy_rows)
	diplomacy_column.add_child(diplomacy_scroll)
	diplomacy_close_button = _action_button("ЗАКРЫТЬ")
	diplomacy_close_button.pressed.connect(func(): close_requested.emit())
	diplomacy_column.add_child(_centered(diplomacy_close_button))
	add_child(diplomacy_panel)


func _rebuild_diplomacy_rows() -> void:
	for child in diplomacy_rows.get_children():
		child.queue_free()
	diplomacy_relation_buttons.clear()
	var state: Dictionary = latest_snapshot.get("player_state", {})
	var own_team := int(state.get("team", match_definition.get("local_team", 1)))
	var allies: Array = state.get("allies", [own_team])
	var relations: Dictionary = state.get("relations", {})
	var players: Array = state.get("players", match_definition.get("players", []))
	if players.is_empty():
		diplomacy_rows.add_child(_row_label("Нет других активных игроков", Color("dfd0aa")))
		return
	for player_value in players:
		var player: Dictionary = player_value
		var team := int(player.get("team", 0))
		if team <= 0:
			continue
		var relation := "ally" if team in allies else "enemy"
		if relations.has(team):
			relation = String(relations[team])
		var definition := _player_definition(team)
		var civilization_id := int(player.get("civilization_id", definition.get("civilization_id", -1)))
		var controller := String(player.get("controller", definition.get("controller", "ai")))
		var status := _status_label(String(player.get("status", "active")))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		var identity := _row_label("Игрок %d   ·   %s" % [team, _civilization_name(civilization_id)], Color("efe2c0"))
		identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(identity)
		var control_label := _row_label("ЧЕЛОВЕК" if controller == "human" else "КОМПЬЮТЕР", Color("b9aa85"))
		control_label.custom_minimum_size.x = 82
		row.add_child(control_label)
		var status_label := _row_label(status, Color("b9aa85"))
		status_label.custom_minimum_size.x = 72
		row.add_child(status_label)
		if team == own_team:
			var own_label := _row_label("ВЫ", Color("f0d782"))
			own_label.custom_minimum_size.x = 170
			own_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(own_label)
		else:
			var controls := HBoxContainer.new()
			controls.add_theme_constant_override("separation", 2)
			var team_buttons: Dictionary = {}
			for relation_name in ["ally", "neutral", "enemy"]:
				var button := _relation_button(team, relation_name, relation == relation_name)
				button.disabled = String(player.get("status", "active")) != "active"
				team_buttons[relation_name] = button
				controls.add_child(button)
			diplomacy_relation_buttons[team] = team_buttons
			row.add_child(controls)
		diplomacy_rows.add_child(row)
		if team != own_team and relation == "ally" and String(player.get("status", "active")) == "active":
			var tribute_row := HBoxContainer.new()
			tribute_row.add_theme_constant_override("separation", 6)
			tribute_row.add_child(_row_label("Дань игроку %d" % team, Color("dfd0aa")))
			var resource_choice := OptionButton.new()
			var resource_names := ["Еда", "Дерево", "Камень", "Золото"]
			for resource_id in range(4):
				resource_choice.add_item(resource_names[resource_id], resource_id)
			tribute_row.add_child(resource_choice)
			var tribute_amount := SpinBox.new()
			tribute_amount.min_value = 1
			tribute_amount.max_value = 100000
			tribute_amount.value = 100
			tribute_amount.step = 1
			tribute_amount.rounded = true
			tribute_amount.custom_minimum_size.x = 90
			tribute_row.add_child(tribute_amount)
			var pay_button := _action_button("ОТПРАВИТЬ")
			pay_button.pressed.connect(func(): tribute_requested.emit(team, resource_choice.get_selected_id(), int(tribute_amount.value)))
			tribute_row.add_child(pay_button)
			diplomacy_rows.add_child(tribute_row)


func _relation_button(team: int, relation: String, selected: bool) -> Button:
	var button := _action_button({"ally": "СОЮЗ", "neutral": "НЕЙТР.", "enemy": "ВРАГ"}.get(relation, relation.to_upper()))
	button.custom_minimum_size = Vector2(55, 20)
	button.toggle_mode = true
	button.button_pressed = selected
	button.tooltip_text = {"ally": "Не атаковать; обмен обзором после Writing", "neutral": "Автоматически атаковать войска и здания, но не рабочих", "enemy": "Атаковать все допустимые цели"}.get(relation, "")
	_apply_source_button_style(button)
	button.pressed.connect(func():
		_set_pending_relation(team, relation)
		diplomacy_relation_requested.emit(team, relation)
	)
	return button


func _set_pending_relation(team: int, relation: String) -> void:
	var state: Dictionary = latest_snapshot.get("player_state", {})
	var relations: Dictionary = state.get("relations", {}).duplicate(true)
	relations[team] = relation
	state["relations"] = relations
	latest_snapshot["player_state"] = state
	var team_buttons: Dictionary = diplomacy_relation_buttons.get(team, {})
	for relation_name in team_buttons:
		var button: Button = team_buttons[relation_name]
		button.button_pressed = String(relation_name) == relation


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
	var text_color: Color = interface_skin.text_color(style_index)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color.lightened(0.12))
	button.add_theme_color_override("font_pressed_color", text_color.darkened(0.08))
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
