class_name RoRHUDModalOverlay
extends Control

signal close_requested
signal save_requested
signal load_requested
signal named_save_requested(name: String)
signal named_load_requested(path: String)
signal resign_requested
signal launcher_requested
signal restart_requested
signal quit_requested
signal preferences_requested(values: Dictionary)
signal details_requested
signal diplomacy_relation_requested(target_team: int, relation: String)
signal tribute_requested(target_team: int, resource_type_id: int, amount: int)

const MODE_NONE := ""
const MODE_MENU := "menu"
const MODE_DIPLOMACY := "diplomacy"
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const Typography := preload("res://scripts/hud_typography.gd")
const Timeline := preload("res://scripts/match_timeline.gd")

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
var named_load_options: ItemList
var named_saves: Array[Dictionary] = []
var resign_button: Button
var launcher_button: Button
var diplomacy_close_button: Button
var menu_status: Label
var instructions_label: Label
var match_status_label: Label
var diplomacy_relation_buttons: Dictionary = {}
var active_section := "menu"
var pages: Dictionary = {}
var page_title: Label
var page_body: VBoxContainer
var body_scroll: ScrollContainer
var back_button: Button
var menu_buttons: Dictionary = {}
var section_heading: Label
var save_slots: ItemList
var stats_text: RichTextLabel
var instructions_text: RichTextLabel
var timeline: Timeline
var timeline_roster_button: Button
var timeline_roster_only := false
var timeline_content: BoxContainer
var timeline_side: VBoxContainer
var timeline_players: Tree
var timeline_readout: Label
var timeline_mode: OptionButton
var timeline_rows: Dictionary = {}
var timeline_event: Label
var stats_table: Tree
var statistic_tabs: Array[Button] = []
var root_groups: GridContainer
var exit_grid: GridContainer
var timeline_note: Label
var network_match := false
var preferences: Dictionary = {}
var preference_controls: Dictionary = {}
var pending_action: Dictionary = {}
var confirm_text: Label
var confirm_button: Button
var cancel_button: Button
var confirmation_return := "menu"
var network_note: Label
var statistics: Dictionary = {}
var stat_category: OptionButton
var settings_apply_button: Button
var layout_queued := false


func _init() -> void:
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(false)
	_build_interface()
	menu_panel.minimum_size_changed.connect(_queue_panel_layout)
	visible = false


func configure(skin, definition: Dictionary, requested_style_index: int = 0, localization_catalog = null) -> void:
	interface_skin = skin
	localization = localization_catalog
	match_definition = definition.duplicate(true)
	instructions_label.text = instruction_summary(match_definition)
	style_index = clampi(requested_style_index, 0, 4)
	for button in _all_buttons(self): _apply_menu_button_style(button)
	_refresh_capabilities()


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
	return "Карта: %s · %d×%d · Код карты: %d\nСтарт: %s · Лимит: %d\nПобеда: %s · Полное древо технологий: %s" % [map_type, size.x, size.y, int(map.get("seed", settings.get("seed", 0))), age, population_limit, victory, "Вкл." if full_tech_tree else "Выкл."]


static func _catalog_name(entries: Array, entry_id: String, fallback: String) -> String:
	for value in entries:
		var entry: Dictionary = value
		if String(entry.get("id", "")) == entry_id:
			return String(entry.get("name", fallback))
	return fallback


func set_viewport_size(viewport_size: Vector2) -> void:
	position = Vector2.ZERO
	size = viewport_size
	_layout_panels()
	_queue_panel_layout()


func set_snapshot(snapshot: Dictionary) -> void:
	# Presentation snapshots are immutable after publication and replaced as a
	# whole by the main scene. Keeping the published reference avoids a deep copy
	# of fog cells and every overview entity on every simulation tick while the
	# menu is closed.
	latest_snapshot = snapshot
	resign_button.disabled = String(snapshot.get("player_state", {}).get("status", "active")) != "active" or bool(snapshot.get("battle_over", false))
	if active_mode == MODE_MENU:
		match_status_label.text = _status_line()
	if active_mode == MODE_DIPLOMACY:
		_rebuild_diplomacy_rows()


func show_menu() -> void:
	active_mode = MODE_MENU
	match_status_label.text = _status_line()
	menu_panel.visible = true
	diplomacy_panel.visible = false
	visible = true
	set_process_unhandled_input(true)
	show_section("menu")
	if is_inside_tree():
		resume_button.grab_focus()


func set_save_available(available: bool) -> void:
	load_button.disabled = not available
	load_button.tooltip_text = "" if available else "Сохранённая игра не найдена"


func set_named_saves(entries: Array[Dictionary]) -> void:
	named_saves = entries.duplicate(true)
	named_load_options.clear()
	save_slots.clear()
	for entry in named_saves:
		var label := "%s · %s" % [String(entry.get("slot_name", "")), Timeline.time_label(int(entry.get("tick", 0)))]
		var saved_at := int(entry.get("saved_at_unix", 0))
		if saved_at > 0:
			var local_at := saved_at + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
			label += " · %s" % Time.get_datetime_string_from_unix_time(local_at, true)
		named_load_options.add_item(label)
		save_slots.add_item(label)
	named_load_button.disabled = named_saves.is_empty()
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
	pending_action.clear()
	active_mode = MODE_NONE
	visible = false
	set_process_unhandled_input(false)


func is_blocking() -> bool:
	return visible and active_mode != MODE_NONE


func _unhandled_input(event: InputEvent) -> void:
	if not is_blocking():
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		show_section("help")
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		close_requested.emit()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if not is_blocking() or not event is InputEventKey or not event.pressed or event.keycode != KEY_TAB: return
	var controls: Array[Control] = []
	_collect_focus(menu_panel if active_mode == MODE_MENU else diplomacy_panel, controls)
	if controls.is_empty(): return
	var current := controls.find(get_viewport().gui_get_focus_owner())
	controls[posmod(current + (-1 if event.shift_pressed else 1), controls.size())].grab_focus()
	get_viewport().set_input_as_handled()

func _collect_focus(node: Node, controls: Array[Control]) -> void:
	if node is Control and node.is_visible_in_tree() and node.focus_mode == Control.FOCUS_ALL:
		if not node is BaseButton or not node.disabled: controls.append(node)
	for child in node.get_children(): _collect_focus(child, controls)

func _build_interface() -> void:
	shade = ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.0, 0.0, 0.0, 0.66)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_build_menu_pages()

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


func _build_menu_pages() -> void:
	var theme := Theme.new()
	theme.default_font = Typography.body_font()
	theme.default_font_size = 15
	theme.set_color("font_color", "Label", Color("e9e1ce"))
	theme.set_color("font_color", "Tree", Color("e9e1ce"))
	theme.set_color("title_button_color", "Tree", Color("d8bd83"))
	theme.set_constant("v_separation", "Tree", 4)
	theme.set_stylebox("panel", "Tree", _surface_style(Color("181d1e"), Color("5b5547")))
	theme.set_stylebox("selected", "Tree", _surface_style(Color("343d3e"), Color("b3945d")))
	theme.set_stylebox("selected_focus", "Tree", _surface_style(Color("343d3e"), Color("dab978")))
	set_theme(theme)
	menu_panel = _center_panel(Vector2(560, 430))
	menu_panel.set_meta("preferred_size", Vector2(800, 650))
	var column := _panel_column(menu_panel)
	page_title = _heading("МЕНЮ ИГРЫ")
	column.add_child(page_title)
	match_status_label = _row_label("", Color("cbbb96"))
	match_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	match_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(match_status_label)
	body_scroll = ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body_scroll)
	page_body = VBoxContainer.new()
	page_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_body.add_theme_constant_override("separation", 10)
	body_scroll.add_child(page_body)
	for key in ["menu", "save", "load", "settings", "achievements", "timeline", "instructions", "help", "confirm"]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 9)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pages[key] = page
		page_body.add_child(page)
	root_groups = GridContainer.new()
	root_groups.columns = 2
	root_groups.add_theme_constant_override("h_separation", 18)
	pages["menu"].add_child(root_groups)
	var match_group := _menu_group("ИГРА")
	var information_group := _menu_group("СВЕДЕНИЯ О МАТЧЕ")
	root_groups.add_child(match_group)
	root_groups.add_child(information_group)
	exit_grid = GridContainer.new()
	exit_grid.columns = 2
	exit_grid.add_theme_constant_override("h_separation", 10)
	exit_grid.add_theme_constant_override("v_separation", 6)
	var actions := [["save", "Сохранить игру…", func(): show_section("save")], ["load", "Загрузить игру…", func(): show_section("load")], ["settings", "Настройки…", func(): show_section("settings")], ["help", "Помощь · F1", func(): show_section("help")], ["achievements", "Статистика…", func(): show_section("achievements")], ["timeline", "Ход матча · TimeLine", func(): show_section("timeline")], ["instructions", "Цели и условия…", func(): show_section("instructions")], ["restart", "Начать заново…", func(): request_confirmation("restart")], ["resign", "Сдаться…", func(): request_confirmation("resign")], ["launcher", "Главное меню…", func(): request_confirmation("launcher")], ["quit", "Выйти из игры…", func(): request_confirmation("quit")]]
	for action in actions:
		var button := _action_button(String(action[1]))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.x = 0
		button.pressed.connect(action[2])
		menu_buttons[action[0]] = button
		if action[0] in ["restart", "resign", "launcher", "quit"]:
			button.set_meta("danger", true)
			exit_grid.add_child(button)
		elif action[0] in ["save", "load", "settings", "help"]: match_group.add_child(button)
		else: information_group.add_child(button)
	pages["menu"].add_child(_group_heading("ЗАВЕРШЕНИЕ И ВЫХОД"))
	pages["menu"].add_child(exit_grid)
	resign_button = menu_buttons["resign"]
	launcher_button = menu_buttons["launcher"]
	network_note = _wrapping_label("")
	pages["menu"].add_child(network_note)
	pages["save"].add_child(_wrapping_label("Выберите существующее сохранение для перезаписи или введите новое имя."))
	save_slots = _save_list()
	pages["save"].add_child(save_slots)
	save_slots.item_selected.connect(func(index: int): named_save_input.text = String(named_saves[index].get("slot_name", "")))
	named_save_input = LineEdit.new()
	named_save_input.placeholder_text = "Имя сохранения"
	named_save_input.max_length = 64
	named_save_input.custom_minimum_size.y = 34
	named_save_input.text_submitted.connect(func(_text: String): _request_save())
	pages["save"].add_child(named_save_input)
	named_save_button = _action_button("Сохранить")
	named_save_button.pressed.connect(_request_save)
	pages["save"].add_child(named_save_button)
	save_button = _action_button("Быстрое сохранение")
	save_button.pressed.connect(func(): request_confirmation("quicksave") if _has_quicksave() else save_requested.emit())
	pages["save"].add_child(save_button)
	pages["load"].add_child(_wrapping_label("Выберите игру. Несохранённый прогресс текущего матча будет потерян."))
	named_load_options = _save_list()
	pages["load"].add_child(named_load_options)
	named_load_button = _action_button("Загрузить выбранную игру…")
	named_load_button.pressed.connect(_request_load)
	named_load_options.item_activated.connect(func(_index: int): _request_load())
	pages["load"].add_child(named_load_button)
	# Kept as the public quick-load capability indicator used by the scene.
	load_button = _action_button("Загрузить быстрое сохранение…")
	load_button.pressed.connect(func(): request_confirmation("quickload"))
	pages["load"].add_child(load_button)
	_build_settings_page()
	stats_text = _rich_text()
	stat_category = OptionButton.new()
	stat_category.visible = false
	pages["achievements"].add_child(stat_category)
	for title in ["Обзор", "Войска", "Экономика", "Религия", "Технологии"]: stat_category.add_item(title)
	stat_category.item_selected.connect(func(_index: int): _render_statistics())
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	for index in range(stat_category.item_count):
		var tab := _action_button(stat_category.get_item_text(index))
		tab.custom_minimum_size.x = 120
		tab.toggle_mode = true
		tab.pressed.connect(func(): stat_category.select(index); _render_statistics())
		statistic_tabs.append(tab)
		tabs.add_child(tab)
	pages["achievements"].add_child(tabs)
	pages["achievements"].add_child(stats_text)
	stats_table = _statistics_table()
	pages["achievements"].add_child(stats_table)
	var timeline_link := _action_button("Ход матча · TimeLine →")
	timeline_link.pressed.connect(func(): show_section("timeline"))
	pages["achievements"].add_child(timeline_link)
	var timeline_toolbar := HFlowContainer.new()
	timeline_mode = OptionButton.new()
	for title in ["Доля населения · %", "Численность · люди"]: timeline_mode.add_item(title)
	timeline_mode.custom_minimum_size.y = 34
	timeline_toolbar.add_child(timeline_mode)
	var table_link := _action_button("← Статистика")
	table_link.custom_minimum_size.x = 140
	table_link.pressed.connect(func(): show_section("achievements"))
	timeline_toolbar.add_child(table_link)
	timeline_roster_button = _action_button("Игроки и события")
	timeline_roster_button.custom_minimum_size.x = 170
	timeline_roster_button.pressed.connect(func():
		timeline_roster_only = not timeline_roster_only
		body_scroll.scroll_vertical = 0
		_layout_panels()
	)
	timeline_toolbar.add_child(timeline_roster_button)
	pages["timeline"].add_child(timeline_toolbar)
	timeline_note = _wrapping_label("")
	pages["timeline"].add_child(timeline_note)
	timeline = Timeline.new()
	timeline_mode.item_selected.connect(func(index: int): timeline.proportional = index == 0; timeline.queue_redraw(); _update_timeline_readout())
	timeline.selection_changed.connect(_update_timeline_readout)
	timeline_readout = _wrapping_label("")
	timeline_readout.add_theme_font_size_override("font_size", 17)
	pages["timeline"].add_child(timeline_readout)
	timeline_content = BoxContainer.new()
	timeline_content.add_theme_constant_override("separation", 16)
	pages["timeline"].add_child(timeline_content)
	timeline_content.add_child(timeline)
	timeline_side = VBoxContainer.new()
	timeline_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_side.add_theme_constant_override("separation", 10)
	timeline_content.add_child(timeline_side)
	timeline_players = _statistics_table()
	_setup_table(timeline_players, ["Игрок", "Люди", "Доля", "Эпоха"], [170, 55, 60, 125])
	timeline_players.item_edited.connect(_timeline_player_toggled)
	timeline_players.item_selected.connect(_show_timeline_events)
	timeline_side.add_child(timeline_players)
	timeline_event = _wrapping_label("Выберите игрока в таблице, чтобы увидеть времена смены эпох и выхода из матча.")
	timeline_side.add_child(timeline_event)
	instructions_label = _wrapping_label("")
	pages["instructions"].add_child(instructions_label)
	instructions_text = _rich_text()
	pages["instructions"].add_child(instructions_text)
	var help := _rich_text()
	help.text = "УПРАВЛЕНИЕ\n\nEsc — отменить выбранную команду; затем открыть меню.\nF10 — открыть или закрыть меню. F1 — помощь.\nЛевая кнопка мыши — выделение; правая — приказ.\nShift + приказ — добавить в очередь.\nB — строительство; R с рабочим — ремонт.\nCtrl + 1–9 — запомнить группу; 1–9 — выбрать её.\nWASD / стрелки / край экрана — камера; колесо — масштаб.\nПробел — пауза; запятая и точка — скорость одиночной игры.\nF5–F9 — формации; Shift + F9 — фланги.\nDel — удалить выбранные свои объекты.\n\nСОХРАНЕНИЯ\n\nСохраняйте матч в отдельном разделе меню. Загрузка, перезапуск и выход требуют подтверждения. Esc отменяет подтверждение и возвращает назад.\n\nTIME LINE\n\nЦветная область показывает долю населения игрока; режим «Численность» показывает количество людей. Числа над графиком — общее население отмеченных игроков. II — эпоха орудий, III — бронзовый век, IV — железный век, × — выход из матча. Наведение или стрелки меняют выбранный момент; таблица показывает точные записанные значения. Выберите строку игрока для просмотра событий. История сохраняется вместе с матчем.\n\nВ сетевом матче меню не останавливает игру. Пауза, изменение скорости и локальное сохранение/загрузка недоступны."
	pages["help"].add_child(help)
	confirm_text = _wrapping_label("")
	pages["confirm"].add_child(confirm_text)
	var confirmation_actions := HBoxContainer.new()
	pages["confirm"].add_child(confirmation_actions)
	cancel_button = _action_button("Отмена")
	confirm_button = _action_button("Подтвердить")
	confirm_button.set_meta("danger", true)
	for button in [cancel_button, confirm_button]:
		button.custom_minimum_size.x = 0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		confirmation_actions.add_child(button)
	cancel_button.pressed.connect(go_back)
	confirm_button.pressed.connect(_confirm_action)
	menu_status = _wrapping_label("")
	column.add_child(menu_status)
	back_button = _action_button("Продолжить игру · Esc")
	back_button.set_meta("primary", true)
	resume_button = back_button
	menu_buttons["resume"] = resume_button
	back_button.pressed.connect(go_back)
	var footer := HBoxContainer.new()
	for button in [back_button, settings_apply_button]:
		button.custom_minimum_size.x = 0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(button)
	column.add_child(footer)
	add_child(menu_panel)
	show_section("menu")

func _save_list() -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 140)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return list

func _rich_text() -> RichTextLabel:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.scroll_active = false
	label.selection_enabled = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _wrapping_label(text: String) -> Label:
	var label := _row_label(text, Color("dfd0ad"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func show_section(section: String) -> void:
	if not pages.has(section): return
	active_section = section
	for key in pages: pages[key].visible = key == section
	page_title.text = {"menu": "МЕНЮ ИГРЫ", "save": "СОХРАНИТЬ ИГРУ", "load": "ЗАГРУЗИТЬ ИГРУ", "settings": "НАСТРОЙКИ", "achievements": "СТАТИСТИКА МАТЧА", "timeline": "ХОД МАТЧА · TIMELINE", "instructions": "ЦЕЛИ И УСЛОВИЯ", "help": "ПОМОЩЬ", "confirm": "ПОДТВЕРЖДЕНИЕ"}.get(section, section)
	back_button.text = "Продолжить игру · Esc" if section == "menu" else "Назад · Esc"
	back_button.tooltip_text = back_button.text
	settings_apply_button.visible = section == "settings"
	body_scroll.scroll_vertical = 0
	menu_status.text = ""
	_refresh_capabilities()
	_layout_panels()
	_queue_panel_layout()
	if section in ["achievements", "timeline", "instructions", "settings"]: details_requested.emit()
	if is_inside_tree():
		var focus: Control = cancel_button if section == "confirm" else named_save_input if section == "save" else named_load_options if section == "load" else resume_button if section == "menu" else back_button
		focus.grab_focus()

func go_back() -> void:
	if active_mode == MODE_DIPLOMACY or active_section == "menu":
		close_requested.emit()
	elif active_section == "confirm":
		pending_action.clear()
		show_section(confirmation_return)
	else:
		show_section("menu")

func request_confirmation(action: String, value: String = "") -> void:
	confirmation_return = active_section if active_section != "confirm" else "menu"
	pending_action = {"type": action, "value": value}
	confirm_text.text = {"restart": "Начать этот матч заново с теми же настройками и картой? Несохранённый прогресс будет потерян.", "resign": "Сдаться и перейти к наблюдению? Продолжить управление этой цивилизацией будет нельзя.", "quit": "Закрыть игру? Несохранённый прогресс будет потерян.", "launcher": "Покинуть сетевой матч и отключиться от остальных игроков?" if network_match else "Вернуться в главное меню? Текущий матч останется на паузе; его можно будет продолжить.", "load": "Загрузить выбранную игру? Несохранённый прогресс текущего матча будет потерян.", "quickload": "Загрузить быстрое сохранение? Несохранённый прогресс текущего матча будет потерян.", "overwrite": "Перезаписать сохранение «%s»? Предыдущая версия будет заменена." % value, "quicksave": "Перезаписать быстрое сохранение?"}.get(action, "Подтвердить действие?")
	show_section("confirm")
	confirm_button.text = {"restart":"Начать заново", "resign":"Сдаться", "quit":"Выйти из игры", "launcher":"В главное меню", "load":"Загрузить", "quickload":"Загрузить", "overwrite":"Перезаписать", "quicksave":"Перезаписать"}.get(action, "Подтвердить")

	confirm_button.tooltip_text = confirm_button.text

func _confirm_action() -> void:
	var action := String(pending_action.get("type", ""))
	var value := String(pending_action.get("value", ""))
	pending_action.clear()
	match action:
		"restart": restart_requested.emit()
		"resign": resign_requested.emit()
		"quit": quit_requested.emit()
		"launcher": launcher_requested.emit()
		"load": named_load_requested.emit(value)
		"quickload": load_requested.emit()
		"overwrite":
			show_section("save")
			named_save_requested.emit(value)
		"quicksave":
			show_section("save")
			save_requested.emit()

func _request_save() -> void:
	var name := named_save_input.text.strip_edges()
	if name.is_empty():
		set_menu_status("Введите имя сохранения", true)
		return
	for entry in named_saves:
		if String(entry.get("slot_name", "")) == name:
			request_confirmation("quicksave" if bool(entry.get("quicksave", false)) else "overwrite", name)
			return
	named_save_requested.emit(name)

func _request_load() -> void:
	var selected := named_load_options.get_selected_items()
	if not selected.is_empty() and selected[0] < named_saves.size(): request_confirmation("load", String(named_saves[selected[0]]["path"]))

func _has_quicksave() -> bool:
	return not load_button.disabled

func set_capabilities(is_network_match: bool) -> void:
	network_match = is_network_match
	_refresh_capabilities()

func _refresh_capabilities() -> void:
	if menu_buttons.is_empty(): return
	for key in ["save", "load", "restart"]:
		menu_buttons[key].disabled = network_match
		menu_buttons[key].tooltip_text = "Недоступно в сетевом матче" if network_match else ""
	network_note.visible = false
	network_note.text = "Сетевой матч продолжается, пока открыто меню." if network_match else "Esc или F10 — вернуться в игру."
	match_status_label.text = _status_line()
	for button in [save_button, named_save_button, named_load_button]:
		if button != null and network_match: button.disabled = true

func _status_line() -> String:
	var status := match_status_summary(latest_snapshot)
	if status == "Матч продолжается": return "Сетевой матч · игра продолжается" if network_match else "Пауза · одиночная игра"
	return status

func _queue_panel_layout() -> void:
	if layout_queued: return
	layout_queued = true
	_apply_queued_panel_layout.call_deferred()

func _apply_queued_panel_layout() -> void:
	layout_queued = false
	_layout_panels()

func _layout_panels() -> void:
	if menu_panel == null or size.x <= 0 or size.y <= 0: return
	var available := Vector2(maxf(160, size.x - 24), maxf(120, size.y - 24))
	var desired := Vector2(640, 450) if active_section == "menu" else Vector2(1040, 720)
	if active_section == "timeline": desired = Vector2(1280, 820)
	if active_section == "achievements": desired.y = clampf(320 + statistics.get("teams", {}).size() * 34, 400, 650)
	if active_section == "confirm": desired = Vector2(560, 300)
	menu_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	menu_panel.size = desired.min(available)
	menu_panel.position = ((size - menu_panel.size) * 0.5).floor()
	if pages.has("menu"):
		var grid: GridContainer = pages["menu"].get_child(0)
		grid.columns = 1 if menu_panel.size.x < 430 else 2
		exit_grid.columns = grid.columns
	if timeline != null:
		var wide := menu_panel.size.x >= 950
		timeline_content.vertical = not wide
		var compact := not wide and menu_panel.size.y < 600
		timeline_note.visible = not compact
		timeline_roster_button.visible = compact
		timeline_roster_button.text = "Показать график" if timeline_roster_only else "Игроки и события"
		timeline_roster_button.tooltip_text = timeline_roster_button.text
		timeline.visible = not compact or not timeline_roster_only
		timeline_side.visible = not compact or timeline_roster_only
		timeline_side.custom_minimum_size.x = 440 if wide else 0
		timeline.custom_minimum_size.y = clampf(menu_panel.size.y - 350, 300, 430) if wide else clampf(menu_panel.size.y * 0.36, 205, 300)
	for row in pages["settings"].get_children():
		if row is BoxContainer:
			row.vertical = menu_panel.size.x < 430
			row.get_child(0).custom_minimum_size.x = 0 if row.vertical else 175
	if diplomacy_panel != null:
		diplomacy_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		diplomacy_panel.size = Vector2(800, 500).min(available)
		diplomacy_panel.position = ((size - diplomacy_panel.size) * 0.5).floor()

func _all_buttons(node: Node) -> Array[Button]:
	var result: Array[Button] = []
	for child in node.get_children():
		if child is Button: result.append(child)
		result.append_array(_all_buttons(child))
	return result

func _build_settings_page() -> void:
	var page: VBoxContainer = pages["settings"]
	page.add_child(_group_heading("ЗВУК"))
	for definition in [["music", "Громкость музыки", 0.0, 1.0, 0.05], ["sound", "Громкость звуков", 0.0, 1.0, 0.05], ["scroll", "Скорость прокрутки камеры", 0.25, 3.0, 0.25]]:
		if definition[0] == "scroll": page.add_child(_group_heading("ИГРА И УПРАВЛЕНИЕ"))
		var slider := HSlider.new()
		slider.min_value = definition[2]
		slider.max_value = definition[3]
		slider.step = definition[4]
		slider.custom_minimum_size.y = 32
		var value_label := _row_label("100%", Color("d6bd8a"))
		value_label.custom_minimum_size.x = 52
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var controls := HBoxContainer.new()
		controls.add_child(slider)
		controls.add_child(value_label)
		slider.value_changed.connect(func(value: float): value_label.text = "%d%%" % roundi(value * 100))
		preference_controls[definition[0]] = slider
		_settings_row(page, String(definition[1]), controls)
	var speed := OptionButton.new()
	for title in ["Нормально · 1×", "Быстро · 1,5×", "Очень быстро · 2×"]: speed.add_item(title)
	preference_controls["speed"] = speed
	_settings_row(page, "Скорость игры", speed)
	page.add_child(_group_heading("ЭКРАН"))
	var resolution := OptionButton.new()
	preference_controls["screen_size"] = resolution
	_settings_row(page, "Размер окна", resolution)
	var fullscreen := CheckBox.new()
	fullscreen.text = "Полный экран"
	preference_controls["fullscreen"] = fullscreen
	fullscreen.custom_minimum_size.y = 32
	page.add_child(fullscreen)
	page.add_child(_wrapping_label("Звук и прокрутка сохраняются между запусками. Скорость относится к текущему одиночному матчу. Изменения вступят в силу после нажатия «Применить»."))
	settings_apply_button = _action_button("Применить")
	settings_apply_button.pressed.connect(func():
		var values := {}
		for key in ["music", "sound", "scroll"]: values[key] = float(preference_controls[key].value)
		values["fullscreen"] = bool(preference_controls["fullscreen"].button_pressed)
		var screen: OptionButton = preference_controls["screen_size"]
		values["screen_size"] = screen.get_item_metadata(screen.selected)
		values["speed"] = [1.0, 1.5, 2.0][preference_controls["speed"].selected]
		preferences_requested.emit(values)
	)

func _settings_row(page: VBoxContainer, text: String, control: Control) -> void:
	var row := BoxContainer.new()
	var label := _wrapping_label(text)
	label.custom_minimum_size.x = 175
	label.size_flags_horizontal = 0
	control.custom_minimum_size.y = 32
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	page.add_child(row)

func set_preferences(values: Dictionary, speed: float) -> void:
	preferences = values.duplicate(true)
	for key in ["music", "sound", "scroll"]: preference_controls[key].value = float(values.get(key, 1.0))
	preference_controls["fullscreen"].button_pressed = bool(values.get("fullscreen", false))
	var speed_control: OptionButton = preference_controls["speed"]
	speed_control.select(0 if speed < 1.25 else 1 if speed < 1.75 else 2)
	speed_control.disabled = network_match
	speed_control.tooltip_text = "Скорость сетевого матча фиксирована" if network_match else ""
	var screen: OptionButton = preference_controls["screen_size"]
	screen.clear()
	var sizes := [Vector2i(640, 480), Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080)]
	var current: Vector2i = values.get("screen_size", Vector2i(1280, 720))
	if current not in sizes: sizes.append(current)
	for viewport in sizes:
		screen.add_item("%d × %d" % [viewport.x, viewport.y])
		screen.set_item_metadata(screen.item_count - 1, viewport)
		if viewport == current: screen.select(screen.item_count - 1)

func set_statistics(data: Dictionary) -> void:
	statistics = data
	_render_statistics()
	# Preserve the cursor across refreshes; a new player set gets a readable default.
	if timeline.history.get("teams", {}).size() != data.get("teams", {}).size():
		timeline.proportional = data.get("teams", {}).size() > 1
		timeline_mode.select(0 if timeline.proportional else 1)
	timeline.configure(data)
	var selected_team := int(timeline_players.get_selected().get_metadata(0)) if timeline_players.get_selected() != null else -1
	timeline_players.clear()
	timeline_rows.clear()
	var root_item := timeline_players.create_item()
	var ids: Array = data.get("teams", {}).keys()
	ids.sort()
	for team in ids:
		var item := timeline_players.create_item(root_item)
		item.set_metadata(0, team)
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_editable(0, true)
		item.set_checked(0, not timeline.hidden_teams.has(team))
		var name := String(data["teams"][team].get("name", "Игрок %d" % team))
		item.set_text(0, name if name.begins_with("Игрок %d" % team) else "%d · %s" % [team, name])
		item.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
		item.set_tooltip_text(0, item.get_text(0))
		item.set_custom_color(0, timeline.team_color(int(team)).lightened(0.25))
		timeline_rows[team] = item
		if int(team) == selected_team: item.select(0)
	if selected_team == -1 and not ids.is_empty(): timeline_rows[ids[0]].select(0)
	timeline_players.custom_minimum_size.y = 42 + ids.size() * 28
	timeline_note.text = "Цвет — игрок, высота области — его население. Метки эпох II–IV — для выбранного игрока; × — выход. Сумма населения — над графиком."
	if bool(data.get("partial", false)): timeline_note.text += " История начинается с загрузки старого сохранения."
	if not bool(data.get("reveal_all", false)): timeline_note.text += " Данные соперников откроются после матча."
	_update_timeline_readout()
	_show_timeline_events()

func _timeline_player_toggled() -> void:
	var item := timeline_players.get_edited()
	if item == null: return
	var team := int(item.get_metadata(0))
	if item.is_checked(0): timeline.hidden_teams.erase(team)
	else: timeline.hidden_teams[team] = true
	timeline.queue_redraw()
	_update_timeline_readout()

func _update_timeline_readout() -> void:
	if timeline_readout == null or timeline_players == null: return
	var sample := timeline.selected_sample()
	var tick := int(sample.get("tick", 0))
	var total := timeline._total(sample, timeline.visible_teams())
	timeline_readout.text = "%s   ·   Население: %d" % [Timeline.time_label(tick), total]
	for team in timeline_rows:
		var item: TreeItem = timeline_rows[team]
		var row: Dictionary = sample.get("teams", {}).get(team, {})
		var population := int(row.get("population", 0))
		var age := timeline.age_at(int(team), tick, int(row.get("age", 100)))
		item.set_text(1, str(population))
		item.set_text(2, "%.1f%%" % (100.0 * population / total) if total > 0 and not timeline.hidden_teams.has(team) else "—")
		item.set_text(3, Timeline.AGE_NAMES[clampi(age - 100, 0, 3)])
		for column in range(1, 4):
			item.set_text_overrun_behavior(column, TextServer.OVERRUN_TRIM_ELLIPSIS)
			item.set_text_alignment(column, HORIZONTAL_ALIGNMENT_CENTER)
			item.set_custom_color(column, Color("e9e1ce") if not timeline.hidden_teams.has(team) else Color("797c76"))

func _show_timeline_events() -> void:
	if timeline_event == null: return
	var item := timeline_players.get_selected()
	if item == null:
		timeline_event.text = "Наведите на график или используйте ← → / Home / End. Выберите игрока в таблице для просмотра событий. Галочки фильтруют график."
		return
	var team := int(item.get_metadata(0))
	timeline.highlighted_team = team
	timeline.queue_redraw()
	var events: Array[String] = []
	for marker in statistics.get("markers", []):
		if int(marker.get("team", 0)) != team: continue
		var kind := String(marker.get("kind", ""))
		var title := ""
		if kind == "age": title = Timeline.AGE_NAMES[clampi(int(marker.get("value", 100)) - 100, 0, 3)]
		elif kind == "player_resigned": title = "Сдался"
		elif kind == "player_defeated": title = "Поражение"
		if not title.is_empty(): events.append("%s — %s" % [Timeline.time_label(int(marker["tick"])), title])
	timeline_event.text = "%s: %s" % [String(statistics["teams"][team].get("name", "Игрок %d" % team)), " · ".join(events) if not events.is_empty() else "Смена эпох и выход из матча пока не записаны."]

func _statistics_table() -> Tree:
	var table := Tree.new()
	table.hide_root = true
	table.column_titles_visible = true
	table.select_mode = Tree.SELECT_ROW
	table.allow_reselect = true
	table.custom_minimum_size = Vector2(0, 100)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return table

func _setup_table(table: Tree, titles: Array, widths: Array) -> void:
	table.clear()
	table.columns = titles.size()
	for column in range(titles.size()):
		table.set_column_title(column, titles[column])
		table.set_column_custom_minimum_width(column, widths[column])
		table.set_column_expand(column, true)
		table.set_column_expand_ratio(column, 2 if column == 0 else 1)

func _age_time(team: int, age: int) -> String:
	for marker in statistics.get("markers", []):
		if int(marker.get("team", 0)) == team and marker.get("kind", "") == "age" and int(marker.get("value", 0)) == age:
			return Timeline.time_label(int(marker["tick"]))
	return "—"

func _render_statistics() -> void:
	if stats_table == null: return
	for index in range(statistic_tabs.size()): statistic_tabs[index].set_pressed_no_signal(index == stat_category.selected)
	var titles: Array = ["Игрок", "Состояние", "Люди", "Пик", "Эпоха"]
	var widths: Array = [170, 95, 55, 55, 140]
	match stat_category.selected:
		1:
			titles = ["Игрок", "Обучено", "Убито", "Потери", "Зданий разрушено", "Зданий потеряно"]
			widths = [220, 90, 80, 80, 150, 145]
		2:
			titles = ["Игрок", "Еда", "Дерево", "Камень", "Золото", "Дань отдана", "Дань получена"]
			widths = [220, 90, 90, 90, 90, 110, 130]
		3:
			titles = ["Игрок", "Обращено", "Храмы", "Руины", "Артефакты"]
			widths = [220, 110, 90, 90, 120]
		4:
			titles = ["Игрок", "Исследования", "Эпоха орудий", "Бронзовый век", "Железный век"]
			widths = [220, 130, 130, 130, 130]
	_setup_table(stats_table, titles, widths)
	var root_item := stats_table.create_item()
	var ids: Array = statistics.get("teams", {}).keys()
	ids.sort()
	for team in ids:
		var row: Dictionary = statistics["teams"][team]
		var values: Array = [_status_label(String(row.get("status", "active"))), row.get("population", 0), row.get("peak_population", 0), Timeline.AGE_NAMES[clampi(int(row.get("age", 100)) - 100, 0, 3)]]
		match stat_category.selected:
			1: values = [row.get("produced", 0), row.get("kills", 0), row.get("lost", 0), row.get("razed", 0), row.get("buildings_lost", 0)]
			2:
				var gathered: Array = row.get("gathered", [0, 0, 0, 0])
				values = [int(gathered[0]), int(gathered[1]), int(gathered[2]), int(gathered[3]), row.get("tribute_sent", 0), row.get("tribute_received", 0)]
			3: values = [row.get("converted", 0), row.get("temples", 0), row.get("ruins", 0), row.get("artifacts", 0)]
			4: values = [row.get("research", 0), _age_time(int(team), 101), _age_time(int(team), 102), _age_time(int(team), 103)]
		var item := stats_table.create_item(root_item)
		item.set_text(0, String(row.get("name", "Игрок %d" % team)))
		item.set_text_overrun_behavior(0, TextServer.OVERRUN_TRIM_ELLIPSIS)
		item.set_tooltip_text(0, item.get_text(0))
		item.set_custom_color(0, Timeline.player_color(int(row.get("color_index", team))).lightened(0.25))
		for column in range(values.size()):
			item.set_text(column + 1, str(values[column]))
			item.set_text_alignment(column + 1, HORIZONTAL_ALIGNMENT_CENTER)
	stats_table.custom_minimum_size.y = 42 + ids.size() * 28
	stats_text.text = "Игровое время: %s" % Timeline.time_label(int(statistics.get("current_tick", 0)))
	if stat_category.selected == 2: stats_text.text += " · Ресурсы, собранные за матч"
	if stat_category.selected in [1, 2, 4]: stats_text.text += "\nШирокая таблица прокручивается по горизонтали."
	if bool(statistics.get("partial", false)): stats_text.text += "\nИстория старого сохранения начинается с загрузки."
	if not bool(statistics.get("reveal_all", false)): stats_text.text += "\nДанные соперников откроются после матча."

func set_instructions(model: Dictionary) -> void:
	var lines: Array[String] = []
	for key in ["title", "briefing", "start_message", "hints", "history"]:
		var text := String(model.get(key, "")).strip_edges()
		if not text.is_empty(): lines.append(("ПОДСКАЗКИ\n" if key == "hints" else "ИСТОРИЯ\n" if key == "history" else "") + text)
	var objectives: Array = model.get("objectives", [])
	if not objectives.is_empty():
		lines.append("ЦЕЛИ")
		for objective in objectives: lines.append("%s %s" % ["✓" if bool(objective.get("achieved", false)) else "•", objective.get("label", "")])
	else:
		var settings: Dictionary = match_definition.get("skirmish_settings", {})
		var victory := String(settings.get("victory_mode_id", ""))
		lines.append("ЦЕЛЬ МАТЧА\n" + String({"conquest": "Уничтожьте войска и постройки всех противников.", "standard": "Победите завоеванием либо удержанием чуда света, всех руин или артефактов.", "score": "Достигните заданного количества очков.", "time_limit": "Наберите больше очков к завершению отведённого времени."}.get(victory, "Выполните условия победы, указанные в параметрах матча.")))
	instructions_text.text = "\n\n".join(lines)

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
	_apply_menu_button_style(button)
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
	column.add_theme_constant_override("separation", 10)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 14)
	margin.add_child(column)
	panel.add_child(margin)
	return column


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color("ecd28b"))
	return label


func _action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.custom_minimum_size = Vector2(180, 34)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_override("font", Typography.title_font())
	button.add_theme_font_size_override("font_size", 15)
	_apply_menu_button_style(button)
	return button


func _centered(child: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.add_child(child)
	return center


func _row_label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", color)
	return label


func _surface_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style

func _apply_menu_button_style(button: Button) -> void:
	var background := Color("343c3e")
	var border := Color("777464")
	if button.get_meta("danger", false):
		background = Color("352c29")
		border = Color("786050")
	if button.get_meta("primary", false):
		background = Color("695334")
		border = Color("c2a36a")
	button.add_theme_stylebox_override("normal", _surface_style(background, border))
	button.add_theme_stylebox_override("hover", _surface_style(background.lightened(0.12), Color("dfc18a")))
	button.add_theme_stylebox_override("pressed", _surface_style(Color("695334"), Color("e2c080")))
	button.add_theme_stylebox_override("disabled", _surface_style(background.darkened(0.25), border.darkened(0.35)))
	var focus := _surface_style(Color.TRANSPARENT, Color("ffe2a0"))
	focus.set_border_width_all(2)
	button.add_theme_stylebox_override("focus", focus)
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(key, Color("f0e7d3"))
	button.add_theme_color_override("font_disabled_color", Color("8b887e"))

func _group_heading(text: String) -> Label:
	var label := _row_label(text, Color("d6b77a"))
	label.add_theme_font_size_override("font_size", 13)
	return label

func _menu_group(title: String) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 6)
	group.add_child(_group_heading(title))
	return group

func _panel_style() -> StyleBoxFlat:
	var style := _surface_style(Color("222727"), Color("b3935b"))
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.55)
	style.shadow_size = 12
	return style
