class_name RoRLauncher
extends Control

const MatchRegistry := preload("res://scripts/match_registry.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const MultiplayerLobby := preload("res://scripts/multiplayer_lobby.gd")
const GAME_SCENE := preload("res://main.tscn")

var match_selector: OptionButton
var description_label: Label
var status_label: Label
var start_button: Button
var available_matches: Array = []
var skirmish_catalog: Dictionary = {}
var settings_panel: Control
var setting_controls: Dictionary = {}
var player_controls: Array = []
var last_generated_match: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	skirmish_catalog = SkirmishSettings.catalog()
	_build_interface()
	available_matches = MatchRegistry.entries()
	for entry_value in available_matches:
		var entry: Dictionary = entry_value
		match_selector.add_item(String(entry["title"]))
		match_selector.set_item_disabled(match_selector.item_count - 1, not bool(entry["available"]))
	_refresh_selection(0)
	var requested := MatchRegistry.requested_match(OS.get_cmdline_args())
	if requested.is_empty():
		requested = MatchRegistry.requested_match(OS.get_cmdline_user_args())
	if not requested.is_empty() and bool(requested.get("available", false)):
		if String(requested.get("kind", "")) == "custom_skirmish":
			_launch_custom_skirmish()
		else:
			_launch_entry(requested)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("101820")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-450, -350)
	panel.size = Vector2(900, 700)
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = "RISE OF ROME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("f1d890"))
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Новый движок"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("c6a866"))
	column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	column.add_child(spacer)

	var prompt := Label.new()
	prompt.text = "Выберите игру"
	prompt.add_theme_font_size_override("font_size", 17)
	prompt.add_theme_color_override("font_color", Color("fff2c1"))
	column.add_child(prompt)

	match_selector = OptionButton.new()
	match_selector.custom_minimum_size.y = 42
	match_selector.item_selected.connect(_refresh_selection)
	column.add_child(match_selector)

	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size.y = 60
	description_label.add_theme_font_size_override("font_size", 15)
	description_label.add_theme_color_override("font_color", Color("e6d6ae"))
	column.add_child(description_label)

	settings_panel = _build_skirmish_settings_panel()
	settings_panel.visible = false
	column.add_child(settings_panel)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("b8df8c"))
	column.add_child(status_label)

	start_button = Button.new()
	start_button.text = "НАЧАТЬ"
	start_button.custom_minimum_size.y = 48
	start_button.pressed.connect(_launch_selected)
	column.add_child(start_button)


func _refresh_selection(index: int) -> void:
	if available_matches.is_empty() or index < 0 or index >= available_matches.size():
		return
	var entry: Dictionary = available_matches[index]
	description_label.text = String(entry["subtitle"])
	var is_custom := String(entry.get("kind", "")) == "custom_skirmish"
	settings_panel.visible = is_custom
	start_button.disabled = not bool(entry["available"]) or (is_custom and not bool(skirmish_catalog.get("valid", false)))
	status_label.text = "Готово к запуску" if bool(entry["available"]) else "Данные матча отсутствуют — выполните импорт ресурсов"
	if is_custom and not bool(skirmish_catalog.get("valid", false)):
		status_label.text = "Каталог настроек случайной игры повреждён"


func _launch_selected() -> void:
	var index := match_selector.selected
	if index < 0 or index >= available_matches.size():
		return
	var entry: Dictionary = available_matches[index]
	if String(entry.get("kind", "")) == "custom_skirmish":
		_launch_custom_skirmish()
		return
	_launch_entry(entry)


func _launch_custom_skirmish() -> void:
	var network_mode: OptionButton = setting_controls["network_mode"]
	var role := String(network_mode.get_item_metadata(network_mode.selected))
	var local_team := 1
	if role == "offline":
		last_generated_match = SkirmishSettings.build(_settings_from_controls())
	else:
		var invite: LineEdit = setting_controls["network_invite"]
		var lobby = MultiplayerLobby.new()
		if role == "host" and invite.text.strip_edges().is_empty():
			_prepare_network_invite()
			return
		var invite_error: String = lobby.load_invite(invite.text.strip_edges())
		if not invite_error.is_empty():
			status_label.text = "Код лобби не принят: %s" % invite_error
			return
		local_team = 1 if role == "host" else roundi(float(setting_controls["network_team"].value))
		if local_team not in lobby.participant_teams():
			status_label.text = "Выберите свободное место игрока из кода лобби"
			return
		last_generated_match = lobby.build_match()
	if not bool(last_generated_match.get("valid", false)):
		status_label.text = "Настройки не приняты: %s" % ", ".join(last_generated_match.get("errors", []))
		return
	start_button.disabled = true
	status_label.text = "Создание случайной игры…"
	await get_tree().process_frame
	var game = GAME_SCENE.instantiate()
	game.match_path = String(last_generated_match["identity"])
	game.match_definition_override = last_generated_match["definition"].duplicate(true)
	game.map_definition_override = last_generated_match["map_data"].duplicate(true)
	if role != "offline":
		game.network_role = role
		game.local_player_team = local_team
		game.network_port = roundi(float(setting_controls["network_port"].value))
		game.network_address = String(setting_controls["network_address"].text).strip_edges()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	queue_free()


func _launch_entry(entry: Dictionary) -> void:
	if not bool(entry.get("available", false)):
		return
	start_button.disabled = true
	status_label.text = "Загрузка…"
	await get_tree().process_frame
	var game = GAME_SCENE.instantiate()
	game.match_path = String(entry["path"])
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	queue_free()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.08, 0.055, 0.97)
	style.border_color = Color("c6a866")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


func _build_skirmish_settings_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	var general := GridContainer.new()
	general.columns = 4
	general.add_theme_constant_override("h_separation", 12)
	general.add_theme_constant_override("v_separation", 6)
	content.add_child(general)
	setting_controls["map_size_id"] = _add_catalog_option(general, "Размер", skirmish_catalog.get("map_sizes", []), "standard")
	setting_controls["map_type_id"] = _add_catalog_option(general, "Тип карты", skirmish_catalog.get("map_types", []), "grasslands")
	setting_controls["resource_preset_id"] = _add_catalog_option(general, "Ресурсы", skirmish_catalog.get("resource_presets", []), "standard")
	setting_controls["starting_age_id"] = _add_catalog_option(general, "Начальная эпоха", skirmish_catalog.get("starting_ages", []), "stone")
	setting_controls["ai_difficulty_id"] = _add_catalog_option(general, "Сложность AI", skirmish_catalog.get("ai_difficulties", []), "standard")
	setting_controls["victory_mode_id"] = _add_catalog_option(general, "Победа", skirmish_catalog.get("victory_modes", []), "conquest")
	var allied_victory_label := Label.new()
	allied_victory_label.text = "Победа союзников"
	general.add_child(allied_victory_label)
	var allied_victory_checkbox := CheckBox.new()
	allied_victory_checkbox.button_pressed = false
	general.add_child(allied_victory_checkbox)
	setting_controls["allied_victory_enabled"] = allied_victory_checkbox
	var full_tech_label := Label.new()
	full_tech_label.text = "Полное дерево технологий"
	general.add_child(full_tech_label)
	var full_tech_checkbox := CheckBox.new()
	general.add_child(full_tech_checkbox)
	setting_controls["full_tech_tree"] = full_tech_checkbox
	setting_controls["population_limit"] = _add_value_option(general, "Лимит населения", skirmish_catalog.get("population_limits", []), 50)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	general.add_child(seed_label)
	var seed_control := SpinBox.new()
	seed_control.min_value = 1
	seed_control.max_value = 2147483647
	seed_control.value = 41721
	seed_control.custom_minimum_size.x = 150
	general.add_child(seed_control)
	setting_controls["seed"] = seed_control
	var count_label := Label.new()
	count_label.text = "Игроки"
	general.add_child(count_label)
	var count_control := SpinBox.new()
	count_control.min_value = 2
	count_control.max_value = 8
	count_control.value = 2
	count_control.value_changed.connect(_on_player_count_changed)
	general.add_child(count_control)
	setting_controls["player_count"] = count_control
	var network_heading := Label.new()
	network_heading.text = "Сетевая игра (LAN)"
	network_heading.add_theme_color_override("font_color", Color("f1d890"))
	content.add_child(network_heading)
	var network_row := HBoxContainer.new()
	network_row.add_theme_constant_override("separation", 8)
	content.add_child(network_row)
	var network_mode := OptionButton.new()
	_add_option_item(network_mode, "Одиночная", "offline")
	_add_option_item(network_mode, "Создать", "host")
	_add_option_item(network_mode, "Подключиться", "join")
	network_mode.custom_minimum_size.x = 145
	network_row.add_child(network_mode)
	setting_controls["network_mode"] = network_mode
	var address := LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Адрес сервера"
	address.custom_minimum_size.x = 170
	network_row.add_child(address)
	setting_controls["network_address"] = address
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 39741
	port.custom_minimum_size.x = 105
	network_row.add_child(port)
	setting_controls["network_port"] = port
	var team := SpinBox.new()
	team.min_value = 2
	team.max_value = 8
	team.value = 2
	team.custom_minimum_size.x = 85
	network_row.add_child(team)
	setting_controls["network_team"] = team
	var invite_row := HBoxContainer.new()
	invite_row.add_theme_constant_override("separation", 8)
	content.add_child(invite_row)
	var prepare_button := Button.new()
	prepare_button.text = "Создать код"
	prepare_button.pressed.connect(_prepare_network_invite)
	invite_row.add_child(prepare_button)
	var invite := LineEdit.new()
	invite.placeholder_text = "Код лобби: скопируйте хосту или вставьте при подключении"
	invite.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	invite_row.add_child(invite)
	setting_controls["network_invite"] = invite

	var heading := Label.new()
	heading.text = "Слот     Управление        Цивилизация          Цвет      Союз"
	heading.add_theme_color_override("font_color", Color("f1d890"))
	content.add_child(heading)
	for slot in range(1, 9):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		content.add_child(row)
		var slot_label := Label.new()
		slot_label.text = "%d" % slot
		slot_label.custom_minimum_size.x = 52
		row.add_child(slot_label)
		var controller := OptionButton.new()
		controller.custom_minimum_size.x = 130
		_add_option_item(controller, "Игрок", "human")
		_add_option_item(controller, "Компьютер", "ai")
		_add_option_item(controller, "Закрыт", "closed")
		controller.select(0 if slot == 1 else 1 if slot == 2 else 2)
		row.add_child(controller)
		var civilization := OptionButton.new()
		civilization.custom_minimum_size.x = 190
		for civilization_value in skirmish_catalog.get("civilizations", []):
			var civilization_entry: Dictionary = civilization_value
			_add_option_item(civilization, String(civilization_entry.get("name", "?")), int(civilization_entry.get("id", 0)))
		_select_metadata(civilization, 13 if slot == 1 else 8 if slot == 2 else ((slot - 1) % 16) + 1)
		row.add_child(civilization)
		var color := OptionButton.new()
		color.custom_minimum_size.x = 90
		for color_index in range(1, 9):
			_add_option_item(color, "%d" % color_index, color_index)
		_select_metadata(color, slot)
		row.add_child(color)
		var alliance := OptionButton.new()
		alliance.custom_minimum_size.x = 90
		for alliance_index in range(1, 9):
			_add_option_item(alliance, "%d" % alliance_index, alliance_index)
		_select_metadata(alliance, slot)
		row.add_child(alliance)
		player_controls.append({"row": row, "controller": controller, "civilization_id": civilization, "color_index": color, "alliance_id": alliance})
	_on_player_count_changed(2.0)
	return scroll


func _prepare_network_invite() -> void:
	var lobby = MultiplayerLobby.new()
	var error: String = lobby.configure_from_skirmish(_settings_from_controls())
	if not error.is_empty():
		status_label.text = "Настройки лобби не приняты: %s" % error
		return
	var invite: LineEdit = setting_controls["network_invite"]
	invite.text = lobby.invite_code()
	invite.select_all()
	invite.grab_focus()
	status_label.text = "Скопируйте код другим игрокам, затем нажмите НАЧАТЬ"


func _add_catalog_option(parent: Control, title: String, entries: Array, default_id: String) -> OptionButton:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 190
	for entry_value in entries:
		var entry: Dictionary = entry_value
		_add_option_item(option, String(entry.get("name", entry.get("id", "?"))), String(entry.get("id", "")))
	_select_metadata(option, default_id)
	parent.add_child(option)
	return option


func _add_value_option(parent: Control, title: String, entries: Array, default_value: int) -> OptionButton:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size.x = 190
	for value in entries:
		_add_option_item(option, str(value), int(value))
	_select_metadata(option, default_value)
	parent.add_child(option)
	return option


func _add_option_item(option: OptionButton, title: String, metadata: Variant) -> void:
	option.add_item(title)
	option.set_item_metadata(option.item_count - 1, metadata)


func _select_metadata(option: OptionButton, expected: Variant) -> void:
	for index in range(option.item_count):
		if option.get_item_metadata(index) == expected:
			option.select(index)
			return


func _on_player_count_changed(value: float) -> void:
	var active_count := clampi(roundi(value), 2, 8)
	for index in range(player_controls.size()):
		var controls: Dictionary = player_controls[index]
		var active := index < active_count
		var controller: OptionButton = controls["controller"]
		if not active:
			_select_metadata(controller, "closed")
		elif String(controller.get_item_metadata(controller.selected)) == "closed":
			_select_metadata(controller, "human" if index == 0 else "ai")
		for key in ["controller", "civilization_id", "color_index", "alliance_id"]:
			var control = controls[key]
			control.disabled = not active


func _settings_from_controls() -> Dictionary:
	var result := SkirmishSettings.default_settings()
	for key in ["map_size_id", "map_type_id", "resource_preset_id", "starting_age_id", "ai_difficulty_id", "victory_mode_id", "population_limit"]:
		var option: OptionButton = setting_controls[key]
		result[key] = option.get_item_metadata(option.selected)
	result["seed"] = roundi(float(setting_controls["seed"].value))
	result["allied_victory_enabled"] = bool(setting_controls["allied_victory_enabled"].button_pressed)
	result["full_tech_tree"] = bool(setting_controls["full_tech_tree"].button_pressed)
	var active_count := roundi(float(setting_controls["player_count"].value))
	var players: Array = []
	for index in range(player_controls.size()):
		var controls: Dictionary = player_controls[index]
		var controller: OptionButton = controls["controller"]
		var controller_id := String(controller.get_item_metadata(controller.selected))
		players.append({
			"enabled": index < active_count and controller_id != "closed",
			"team": index + 1,
			"controller": controller_id,
			"civilization_id": _selected_int(controls["civilization_id"]),
			"color_index": _selected_int(controls["color_index"]),
			"alliance_id": _selected_int(controls["alliance_id"]),
		})
	result["players"] = players
	return result


func _selected_int(option: OptionButton) -> int:
	return int(option.get_item_metadata(option.selected))
