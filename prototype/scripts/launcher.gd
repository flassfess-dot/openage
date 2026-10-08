class_name RoRLauncher
extends Control

const MatchRegistry := preload("res://scripts/match_registry.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const GenerationJob := preload("res://scripts/skirmish_generation_job.gd")
const LauncherTheme := preload("res://scripts/launcher_theme.gd")
const AntiqueTheme := preload("res://scripts/antique_ui_theme.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const MatchDefinition := preload("res://scripts/match_definition.gd")
const GAME_SCENE := preload("res://main.tscn")

const SCREEN_MAIN := "main"
const SCREEN_SINGLE_PLAYER := "single_player"
const SCREEN_CAMPAIGNS := "campaigns"
const SCREEN_RANDOM_MAP := "random_map"
const SCREEN_LOADING := "loading"
const SCREEN_SAVES := "saves"

const BACKGROUND_MAIN := "res://assets/menu/main-menu.png"
const BACKGROUND_SINGLE_PLAYER := "res://assets/menu/single-player.png"
const BACKGROUND_BATTLE := "res://assets/menu/single-player.png"
const BACKGROUND_PARCHMENT := "res://assets/menu/random-map.png"
const DEFAULT_MAP_SIZE_ID := "supergiant"
const DEFAULT_POPULATION_LIMIT := 500

# Keep the paused single-player match in the scene tree while the launcher is
# open, making both saving and returning to that match available here.
var active_game
var save_list: ItemList
var save_name_input: LineEdit
var save_details_label: Label
var saved_games: Array[Dictionary] = []
var _save_menu_parent := SCREEN_MAIN
var _saving_current_game := false
var _save_overwrite_dialog: ConfirmationDialog
var _pending_save_name := ""
var current_screen := ""
var screen_buttons: Dictionary = {}
var available_matches: Array = []
var campaign_matches: Array = []
var skirmish_catalog: Dictionary = {}
var setting_controls: Dictionary = {}
var player_controls: Array = []
var last_generated_match: Dictionary = {}

# Public references intentionally stay stable for integration tests and future
# accessibility automation.
var match_selector: OptionButton
var campaign_selector: OptionButton
var description_label: Label
var status_label: Label
var start_button: Button
var settings_panel: Control
var generation_progress_bar: ProgressBar

var _playfield: Control
var _virtual_canvas: Control
var _fullscreen_canvas: Control
var _background_image: TextureRect
var _background_tint: ColorRect
var _screen_root: Control
var _generation_job: RefCounted
var _generation_started_at := 0
var _finishing_generation := false


func _ready() -> void:
	theme = AntiqueTheme.shared_theme()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	skirmish_catalog = SkirmishSettings.catalog()
	available_matches = MatchRegistry.entries()
	for value in available_matches:
		var entry: Dictionary = value
		if String(entry.get("kind", "")) != "custom_skirmish":
			campaign_matches.append(entry)
	_build_shell()
	_show_main_menu()
	if is_instance_valid(active_game):
		return
	var requested := MatchRegistry.requested_match(OS.get_cmdline_args())
	if requested.is_empty():
		requested = MatchRegistry.requested_match(OS.get_cmdline_user_args())
	if not requested.is_empty() and bool(requested.get("available", false)):
		if String(requested.get("kind", "")) == "custom_skirmish":
			_show_random_map_menu()
			call_deferred("_launch_custom_skirmish")
		else:
			call_deferred("_launch_entry", requested)


func _process(_delta: float) -> void:
	_poll_launcher_save()
	if current_screen != SCREEN_LOADING or _generation_job == null or _finishing_generation:
		return
	var snapshot: Dictionary = _generation_job.snapshot()
	if generation_progress_bar != null:
		generation_progress_bar.value = float(snapshot.get("progress", 0.0)) * 100.0
	if status_label != null:
		var elapsed_seconds := float(Time.get_ticks_msec() - _generation_started_at) / 1000.0
		status_label.text = "%s  •  %.1f с" % [String(snapshot.get("stage", "Создание карты")), elapsed_seconds]
	if bool(snapshot.get("complete", false)):
		_finishing_generation = true
		_finish_generated_match()


func _exit_tree() -> void:
	if _generation_job != null:
		_generation_job.shutdown()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	match current_screen:
		SCREEN_SINGLE_PLAYER:
			_show_main_menu()
		SCREEN_SAVES:
			_leave_save_menu()
		SCREEN_CAMPAIGNS, SCREEN_RANDOM_MAP:
			_show_single_player_menu()
		_:
			pass
	get_viewport().set_input_as_handled()


func _build_shell() -> void:
	var outer_background := ColorRect.new()
	outer_background.color = Color("080503")
	outer_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(outer_background)

	# The artwork belongs to the physical window, not to the 800x600 layout
	# canvas. KEEP_ASPECT_COVERED fills every aspect ratio while preserving the
	# central composition; only the safe outer edges are cropped.
	_background_image = TextureRect.new()
	_background_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background_image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_background_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_image)

	_background_tint = ColorRect.new()
	_background_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background_tint)

	var aspect := AspectRatioContainer.new()
	aspect.ratio = 4.0 / 3.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(aspect)

	_playfield = Control.new()
	_playfield.custom_minimum_size = Vector2(800.0, 600.0)
	_playfield.mouse_filter = Control.MOUSE_FILTER_PASS
	aspect.add_child(_playfield)
	_playfield.resized.connect(_layout_virtual_canvas)

	_virtual_canvas = Control.new()
	_virtual_canvas.size = Vector2(800.0, 600.0)
	_virtual_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_playfield.add_child(_virtual_canvas)
	_layout_virtual_canvas()

	# Map settings use the whole window, independently of the main menu's
	# original 4:3 composition.
	_fullscreen_canvas = Control.new()
	_fullscreen_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fullscreen_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fullscreen_canvas)


func _layout_virtual_canvas() -> void:
	if _playfield == null or _virtual_canvas == null:
		return
	var scale_factor := minf(_playfield.size.x / 800.0, _playfield.size.y / 600.0)
	_virtual_canvas.scale = Vector2.ONE * scale_factor
	_virtual_canvas.position = (_playfield.size - Vector2(800.0, 600.0) * scale_factor) * 0.5


func _begin_screen(screen_name: String, background_path: String, tint: Color) -> Control:
	current_screen = screen_name
	screen_buttons.clear()
	status_label = null
	start_button = null
	description_label = null
	match_selector = null
	campaign_selector = null
	settings_panel = null
	generation_progress_bar = null
	save_list = null
	save_name_input = null
	save_details_label = null
	if _screen_root != null:
		# Menu callbacks run from BaseButton.pressed. Freeing the screen
		# immediately would destroy the signal emitter while Godot is still using
		# it and can crash the packaged build. Hide it now and release it safely at
		# the end of the frame.
		_screen_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen_root.hide()
		_screen_root.queue_free()
	_background_image.texture = load(background_path)
	_background_tint.color = tint
	_screen_root = Control.new()
	if screen_name == SCREEN_RANDOM_MAP:
		_fullscreen_canvas.add_child(_screen_root)
		_screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		_screen_root.size = Vector2(800.0, 600.0)
		_virtual_canvas.add_child(_screen_root)
	return _screen_root


func _show_main_menu() -> void:
	var root := _begin_screen(SCREEN_MAIN, BACKGROUND_MAIN, Color(0.0, 0.0, 0.0, 0.03))
	var has_game := is_instance_valid(active_game)
	var panel_height := 426.0 if has_game else 378.0
	var panel := _make_panel(root, Vector2(430, 574 - panel_height), Vector2(344, panel_height), false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)
	var heading := _label("ГЛАВНОЕ МЕНЮ", 18, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.heading(heading, 18)
	column.add_child(heading)
	if has_game:
		column.add_child(_menu_button("ПРОДОЛЖИТЬ ИГРУ", _resume_active_game, true, "Вернуться к текущему матчу", "resume"))
	column.add_child(_menu_button("ОДИНОЧНАЯ ИГРА", _show_single_player_menu, true, "Кампании и случайная карта", "single_player"))
	column.add_child(_menu_button("СОХРАНЕНИЯ И ЗАГРУЗКА", _show_save_menu, true, "Загрузить игру или сохранить текущий матч", "saves"))
	column.add_child(_menu_button("СЕТЕВАЯ ИГРА", Callable(), false, "Сетевой режим ещё не готов", "multiplayer"))
	column.add_child(_menu_button("РЕДАКТОР СЦЕНАРИЕВ", Callable(), false, "Редактор сценариев ещё не готов", "scenario_editor"))
	column.add_child(_menu_button("СПРАВКА", Callable(), false, "Раздел справки ещё не готов", "help"))
	column.add_child(_menu_button("ВЫХОД", _quit_game, true, "Выйти из игры", "exit"))
	status_label = _label("Текущий матч приостановлен" if has_game else "Недоступные разделы отмечены серым", 12, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.caption(status_label, 12)
	column.add_child(status_label)


func _show_single_player_menu() -> void:
	var root := _begin_screen(SCREEN_SINGLE_PLAYER, BACKGROUND_SINGLE_PLAYER, Color(0.0, 0.0, 0.0, 0.28))
	root.add_child(_screen_title("ОДИНОЧНАЯ ИГРА"))
	var panel := _make_panel(root, Vector2(448, 270), Vector2(324, 292), false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	column.add_child(_menu_button("КАМПАНИИ", _show_campaign_menu, true, "Выбрать кампанию", "campaigns"))
	column.add_child(_menu_button("СЛУЧАЙНАЯ КАРТА", _show_random_map_menu, bool(skirmish_catalog.get("valid", false)), "Настроить новую игру", "random_map"))
	column.add_child(_menu_button("СОХРАНЁННАЯ ИГРА", _show_save_menu, true, "Открыть сохранения", "saved_game"))
	column.add_child(_menu_button("СЦЕНАРИЙ", Callable(), false, "Пользовательские сценарии ещё не готовы", "scenario"))
	column.add_child(_menu_button("НАЗАД", _show_main_menu, true, "Вернуться в главное меню", "back"))
	status_label = _label("Esc — назад", 12, HORIZONTAL_ALIGNMENT_RIGHT)
	LauncherTheme.caption(status_label, 12)
	status_label.position = Vector2(570, 574)
	status_label.size = Vector2(194, 20)
	root.add_child(status_label)


func _show_campaign_menu() -> void:
	var root := _begin_screen(SCREEN_CAMPAIGNS, BACKGROUND_BATTLE, Color(0.0, 0.0, 0.0, 0.43))
	root.add_child(_screen_title("КАМПАНИИ"))
	var panel := _make_panel(root, Vector2(72, 104), Vector2(656, 396), false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)

	var prompt := _label("Выберите кампанию или учебную игру", 15)
	LauncherTheme.caption(prompt, 15)
	column.add_child(prompt)
	campaign_selector = OptionButton.new()
	match_selector = campaign_selector
	LauncherTheme.apply_option(campaign_selector, 590.0)
	for entry_value in campaign_matches:
		var entry: Dictionary = entry_value
		campaign_selector.add_item(String(entry.get("title", "Без названия")))
		var index := campaign_selector.item_count - 1
		campaign_selector.set_item_metadata(index, entry)
		campaign_selector.set_item_disabled(index, not bool(entry.get("available", false)))
	campaign_selector.item_selected.connect(_refresh_campaign_selection)
	column.add_child(campaign_selector)

	description_label = _label("", 15)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size = Vector2(590, 104)
	LauncherTheme.body(description_label, 15)
	column.add_child(description_label)

	status_label = _label("", 13)
	LauncherTheme.caption(status_label, 13)
	column.add_child(status_label)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	footer.add_child(_menu_button("НАЗАД", _show_single_player_menu, true, "Вернуться", "back", true))
	start_button = _menu_button("НАЧАТЬ", _launch_selected_campaign, true, "Запустить выбранную игру", "start", true)
	footer.add_child(start_button)
	_refresh_campaign_selection(0)


func _refresh_campaign_selection(index: int) -> void:
	if campaign_selector == null or index < 0 or index >= campaign_selector.item_count:
		return
	var entry: Dictionary = campaign_selector.get_item_metadata(index)
	var available := bool(entry.get("available", false))
	description_label.text = String(entry.get("subtitle", ""))
	status_label.text = "Готово к запуску" if available else "Данные кампании отсутствуют"
	start_button.disabled = not available


func _launch_selected_campaign() -> void:
	if campaign_selector == null or campaign_selector.selected < 0:
		return
	_launch_entry(campaign_selector.get_item_metadata(campaign_selector.selected))


func _show_random_map_menu() -> void:
	var root := _begin_screen(SCREEN_RANDOM_MAP, BACKGROUND_PARCHMENT, Color(0.0, 0.0, 0.0, 0.40))
	setting_controls.clear()
	player_controls.clear()

	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 32)
	margins.add_theme_constant_override("margin_right", 32)
	margins.add_theme_constant_override("margin_top", 20)
	margins.add_theme_constant_override("margin_bottom", 20)
	root.add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margins.add_child(layout)
	var title := _label("СЛУЧАЙНАЯ КАРТА", 32, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.heading(title, 32)
	_readable_map_label(title)
	layout.add_child(title)

	# No opaque panel: the existing screen artwork is visible behind the
	# settings. Only the content scrolls on short windows; actions stay visible.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	var content := GridContainer.new()
	content.columns = 2
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("h_separation", 32)
	content.add_theme_constant_override("v_separation", 24)
	scroll.add_child(content)
	settings_panel = content
	content.add_child(_build_general_settings())
	content.add_child(_build_player_settings())
	scroll.resized.connect(func(): content.columns = 2 if scroll.size.x >= 1040.0 else 1)
	content.columns = 2 if root.size.x - 64.0 >= 1040.0 else 1

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	layout.add_child(footer)
	status_label = _label("Случайная цивилизация определяется по seed карты", 14)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	LauncherTheme.caption(status_label, 14)
	_readable_map_label(status_label)
	footer.add_child(status_label)
	var back_button := _menu_button("НАЗАД", _show_single_player_menu, true, "Вернуться", "back", true)
	LauncherTheme.apply_secondary_button(back_button, 16)
	back_button.custom_minimum_size = Vector2(168, 48)
	footer.add_child(back_button)
	start_button = _menu_button("НАЧАТЬ ИГРУ", _launch_custom_skirmish, bool(skirmish_catalog.get("valid", false)), "Создать случайную карту", "start", true)
	LauncherTheme.apply_secondary_button(start_button, 16)
	start_button.custom_minimum_size = Vector2(216, 48)
	footer.add_child(start_button)


func _build_general_settings() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	var heading := _label("ПАРАМЕТРЫ ИГРЫ", 22)
	LauncherTheme.heading(heading, 22)
	_readable_map_label(heading)
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	setting_controls["map_size_id"] = _add_catalog_option(grid, "Размер карты", skirmish_catalog.get("map_sizes", []), DEFAULT_MAP_SIZE_ID)
	setting_controls["map_type_id"] = _add_catalog_option(grid, "Тип карты", skirmish_catalog.get("map_types", []), "grasslands")
	setting_controls["resource_preset_id"] = _add_catalog_option(grid, "Ресурсы", skirmish_catalog.get("resource_presets", []), "standard")
	setting_controls["starting_age_id"] = _add_catalog_option(grid, "Начальная эпоха", skirmish_catalog.get("starting_ages", []), "stone")
	setting_controls["ai_difficulty_id"] = _add_catalog_option(grid, "Сложность", skirmish_catalog.get("ai_difficulties", []), "standard")
	setting_controls["victory_mode_id"] = _add_catalog_option(grid, "Условие победы", skirmish_catalog.get("victory_modes", []), "conquest")
	setting_controls["population_limit"] = _add_value_option(grid, "Население", skirmish_catalog.get("population_limits", []), DEFAULT_POPULATION_LIMIT)

	grid.add_child(_field_label("Игроки"))
	var count_control := SpinBox.new()
	count_control.min_value = 2
	count_control.max_value = 8
	count_control.step = 1
	count_control.value = 2
	count_control.value_changed.connect(_on_player_count_changed)
	LauncherTheme.apply_spin_box(count_control, 220.0)
	count_control.custom_minimum_size.y = 40
	count_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(count_control)
	setting_controls["player_count"] = count_control

	grid.add_child(_field_label("Seed карты"))
	var seed_control := SpinBox.new()
	seed_control.min_value = 1
	seed_control.max_value = 2147483647
	seed_control.step = 1
	seed_control.value = 41721
	LauncherTheme.apply_spin_box(seed_control, 220.0)
	seed_control.custom_minimum_size.y = 40
	seed_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(seed_control)
	setting_controls["seed"] = seed_control

	grid.add_child(_field_label("Победа союзников"))
	var allied_victory := CheckBox.new()
	_style_checkbox(allied_victory)
	grid.add_child(allied_victory)
	setting_controls["allied_victory_enabled"] = allied_victory

	grid.add_child(_field_label("Все технологии"))
	var full_tech := CheckBox.new()
	_style_checkbox(full_tech)
	grid.add_child(full_tech)
	setting_controls["full_tech_tree"] = full_tech
	return column


func _build_player_settings() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	var heading := _label("ИГРОКИ", 22)
	LauncherTheme.heading(heading, 22)
	_readable_map_label(heading)
	column.add_child(heading)
	var headers := HBoxContainer.new()
	headers.add_theme_constant_override("separation", 12)
	column.add_child(headers)
	for header_data in [["№", 28], ["Игрок", 154], ["Цивилизация", 190], ["Цвет", 84], ["Союз", 76]]:
		var header := _label(String(header_data[0]), 14, HORIZONTAL_ALIGNMENT_CENTER)
		header.custom_minimum_size.x = float(header_data[1])
		if String(header_data[0]) == "Цивилизация":
			header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		LauncherTheme.caption(header, 14)
		_readable_map_label(header)
		headers.add_child(header)
	for slot in range(1, 9):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)
		var slot_label := _label(str(slot), 16, HORIZONTAL_ALIGNMENT_CENTER)
		slot_label.custom_minimum_size = Vector2(28, 40)
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		LauncherTheme.body(slot_label, 16)
		_readable_map_label(slot_label)
		row.add_child(slot_label)

		var controller := OptionButton.new()
		_style_map_option(controller, 154.0)
		_add_option_item(controller, "Игрок", "human")
		_add_option_item(controller, "Компьютер", "ai")
		_add_option_item(controller, "Закрыт", "closed")
		_select_metadata(controller, "human" if slot == 1 else "ai" if slot == 2 else "closed")
		row.add_child(controller)

		var civilization := OptionButton.new()
		_style_map_option(civilization, 190.0)
		civilization.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for civilization_value in skirmish_catalog.get("civilizations", []):
			var civilization_entry: Dictionary = civilization_value
			_add_option_item(civilization, String(civilization_entry.get("name", "?")), int(civilization_entry.get("id", 0)))
		_select_metadata(civilization, 0)
		row.add_child(civilization)

		var color := _player_color_option(slot)
		row.add_child(color)

		var alliance := OptionButton.new()
		_style_map_option(alliance, 76.0)
		for alliance_index in range(1, 9):
			_add_option_item(alliance, str(alliance_index), alliance_index)
		_select_metadata(alliance, slot)
		row.add_child(alliance)
		player_controls.append({
			"row": row,
			"controller": controller,
			"civilization_id": civilization,
			"color_index": color,
			"alliance_id": alliance,
		})
	_on_player_count_changed(2.0)
	return column


func _style_map_option(option: OptionButton, width: float) -> void:
	LauncherTheme.apply_option(option, width)
	option.custom_minimum_size.y = 40
	option.add_theme_font_size_override("font_size", 16)
	option.add_theme_constant_override("icon_max_width", 42)


func _readable_map_label(label: Label) -> void:
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	label.add_theme_constant_override("outline_size", 2)


func _player_color_option(slot: int) -> OptionButton:
	var option := OptionButton.new()
	_style_map_option(option, 84.0)
	# Representative shades from the original AoE1/RoR palette 50500,
	# player-colour ramps 16 * player + 3. Metadata stays the game colour ID.
	var palette := [
		["Синий", Color("739bc7")],
		["Красный", Color("ff5f5f")],
		["Жёлтый", Color("e3e300")],
		["Коричневый", Color("b78b2b")],
		["Оранжевый", Color("f78b17")],
		["Зелёный", Color("7f8b37")],
		["Серый", Color("c7c7c7")],
		["Бирюзовый", Color("2bbf93")],
	]
	for index in range(palette.size()):
		var image := Image.create(42, 22, false, Image.FORMAT_RGBA8)
		image.fill(Color("3c3428"))
		image.fill_rect(Rect2i(2, 2, 38, 18), palette[index][1])
		option.add_icon_item(ImageTexture.create_from_image(image), "", index + 1)
		option.set_item_metadata(index, index + 1)
		option.set_item_tooltip(index, String(palette[index][0]))
	option.select(slot - 1)
	option.tooltip_text = String(palette[slot - 1][0])
	option.item_selected.connect(func(index: int): option.tooltip_text = String(palette[index][0]))
	return option


func _launch_custom_skirmish() -> void:
	if _generation_job != null or not bool(skirmish_catalog.get("valid", false)):
		return
	var settings := _settings_from_controls()
	_show_loading_screen("СОЗДАНИЕ СЛУЧАЙНОЙ КАРТЫ", "Подготовка генератора")
	# Let the loading screen reach the renderer before the worker starts doing
	# expensive work. This also makes the transition deterministic on slower
	# machines and in packaged builds.
	await get_tree().process_frame
	if not is_inside_tree() or current_screen != SCREEN_LOADING:
		return
	_generation_job = GenerationJob.new()
	_generation_started_at = Time.get_ticks_msec()
	_finishing_generation = false
	if not _generation_job.start(settings):
		_generation_job = null
		_show_random_map_menu()
		status_label.text = "Не удалось запустить генератор карты"


func _finish_generated_match() -> void:
	last_generated_match = _generation_job.take_result()
	_generation_job = null
	if not bool(last_generated_match.get("valid", false)):
		var error_text := ", ".join(last_generated_match.get("errors", []))
		_show_random_map_menu()
		status_label.text = "Карта не создана: %s" % error_text
		_finishing_generation = false
		return
	if generation_progress_bar != null:
		generation_progress_bar.value = 100.0
	if status_label != null:
		status_label.text = "Карта готова. Запуск игры…"
	await get_tree().create_timer(0.12).timeout
	_launch_generated_match(last_generated_match)


func _launch_generated_match(match_data: Dictionary) -> void:
	_discard_active_game()
	await get_tree().process_frame
	var game = GAME_SCENE.instantiate()
	game.match_path = String(match_data["identity"])
	game.match_definition_override = match_data["definition"].duplicate(true)
	game.map_definition_override = match_data["map_data"].duplicate(true)
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	queue_free()


func _launch_entry(entry: Dictionary) -> void:
	if not bool(entry.get("available", false)):
		return
	_show_loading_screen("ЗАГРУЗКА КАМПАНИИ", String(entry.get("title", "")))
	if generation_progress_bar != null:
		generation_progress_bar.value = 100.0
	_discard_active_game()
	await get_tree().process_frame
	var game = GAME_SCENE.instantiate()
	game.match_path = String(entry["path"])
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	queue_free()


func _show_loading_screen(title_text: String, initial_status: String) -> void:
	var root := _begin_screen(SCREEN_LOADING, BACKGROUND_PARCHMENT, Color(0.0, 0.0, 0.0, 0.36))
	root.add_child(_screen_title(title_text))
	var panel := _make_panel(root, Vector2(108, 358), Vector2(584, 148), false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)
	var message := _label("Империя рождается…", 20, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.heading(message, 20)
	column.add_child(message)
	generation_progress_bar = ProgressBar.new()
	generation_progress_bar.custom_minimum_size = Vector2(520, 28)
	generation_progress_bar.min_value = 0.0
	generation_progress_bar.max_value = 100.0
	generation_progress_bar.value = 0.0
	generation_progress_bar.show_percentage = true
	generation_progress_bar.add_theme_stylebox_override("background", LauncherTheme.progress_background_style())
	generation_progress_bar.add_theme_stylebox_override("fill", LauncherTheme.progress_fill_style())
	generation_progress_bar.add_theme_color_override("font_color", LauncherTheme.GOLD_BRIGHT)
	column.add_child(generation_progress_bar)
	status_label = _label(initial_status, 13, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.caption(status_label, 13)
	column.add_child(status_label)


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
			var control: BaseButton = controls[key]
			control.disabled = not active


func _add_catalog_option(parent: Control, title: String, entries: Array, default_id: String) -> OptionButton:
	parent.add_child(_field_label(title))
	var option := OptionButton.new()
	_style_map_option(option, 220.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry_value in entries:
		var entry: Dictionary = entry_value
		_add_option_item(option, String(entry.get("name", entry.get("id", "?"))), String(entry.get("id", "")))
	_select_metadata(option, default_id)
	parent.add_child(option)
	return option


func _add_value_option(parent: Control, title: String, entries: Array, default_value: int) -> OptionButton:
	parent.add_child(_field_label(title))
	var option := OptionButton.new()
	_style_map_option(option, 220.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in entries:
		_add_option_item(option, str(int(value)), int(value))
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


func _selected_int(option: OptionButton) -> int:
	return int(option.get_item_metadata(option.selected))


func _make_panel(parent: Control, panel_position: Vector2, panel_size: Vector2, soft: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = panel_position
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", LauncherTheme.panel_style(soft))
	parent.add_child(panel)
	return panel


func _menu_button(text: String, action: Callable, available: bool, hint: String, key: String, compact: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not available
	button.tooltip_text = hint
	if compact:
		LauncherTheme.apply_secondary_button(button, 13)
		button.custom_minimum_size = Vector2(142, 38)
	else:
		LauncherTheme.apply_primary_button(button, 15)
	if available and action.is_valid():
		button.pressed.connect(action)
	screen_buttons[key] = button
	return button


func _screen_title(text: String) -> Label:
	var title := _label(text, 25, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(20, 10)
	title.size = Vector2(760, 36)
	LauncherTheme.heading(title, 25)
	return title


func _label(text: String, font_size: int, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _field_label(text: String) -> Label:
	var label := _label(text, 16)
	label.custom_minimum_size = Vector2(156, 40)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	LauncherTheme.body(label, 16)
	_readable_map_label(label)
	return label


func _style_checkbox(check_box: CheckBox) -> void:
	check_box.custom_minimum_size.y = 40
	check_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	check_box.add_theme_font_override("font", AntiqueTheme.Typography.body_font())
	check_box.add_theme_color_override("font_color", AntiqueTheme.LIGHT_TEXT)
	check_box.add_theme_color_override("font_disabled_color", LauncherTheme.MUTED)


func _quit_game() -> void:
	get_tree().quit()

func _show_save_menu() -> void:
	if current_screen in [SCREEN_MAIN, SCREEN_SINGLE_PLAYER]:
		_save_menu_parent = current_screen
	var root := _begin_screen(SCREEN_SAVES, BACKGROUND_MAIN, Color(0.0, 0.0, 0.0, 0.03))
	root.add_child(_screen_title("СОХРАНЕНИЯ И ЗАГРУЗКА"))
	var panel := _make_panel(root, Vector2(68, 90), Vector2(664, 474), false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var heading := _label("ЛЕТОПИСЬ ВАШИХ ИГР", 17)
	LauncherTheme.heading(heading, 17)
	column.add_child(heading)
	save_list = ItemList.new()
	save_list.custom_minimum_size = Vector2(610, 158)
	save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_list.select_mode = ItemList.SELECT_SINGLE
	save_list.item_selected.connect(_on_save_selected)
	save_list.item_activated.connect(func(_index: int): _load_selected_save())
	column.add_child(save_list)
	save_details_label = _label("", 14)
	save_details_label.custom_minimum_size.y = 42
	save_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	LauncherTheme.body(save_details_label, 14)
	column.add_child(save_details_label)
	var load_row := HBoxContainer.new()
	load_row.add_theme_constant_override("separation", 10)
	var load_button := _menu_button("ЗАГРУЗИТЬ ИГРУ", _load_selected_save, true, "Продолжить выбранную сохранённую игру", "load_save", true)
	load_button.custom_minimum_size.x = 240
	load_row.add_child(load_button)
	var refresh := _menu_button("ОБНОВИТЬ СПИСОК", _refresh_saved_games, true, "Найти новые сохранения", "refresh_saves", true)
	refresh.custom_minimum_size.x = 220
	load_row.add_child(refresh)
	column.add_child(load_row)
	var save_caption := _label("СОХРАНИТЬ ТЕКУЩУЮ ИГРУ", 15)
	LauncherTheme.heading(save_caption, 15)
	column.add_child(save_caption)
	var save_row := HBoxContainer.new()
	save_row.add_theme_constant_override("separation", 10)
	save_name_input = LineEdit.new()
	save_name_input.max_length = GameSaveArchive.MAX_SLOT_NAME_LENGTH
	save_name_input.placeholder_text = "Название сохранения"
	save_name_input.editable = is_instance_valid(active_game)
	save_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	LauncherTheme.apply_line_edit(save_name_input, 380)
	save_name_input.text_submitted.connect(func(_text: String): _request_launcher_save())
	if is_instance_valid(active_game):
		var now := Time.get_datetime_dict_from_system()
		save_name_input.text = "Игра %02d.%02d — %02d:%02d" % [now["day"], now["month"], now["hour"], now["minute"]]
	save_row.add_child(save_name_input)
	var save_button := _menu_button("СОХРАНИТЬ", _request_launcher_save, is_instance_valid(active_game), "Создать именованное сохранение текущего матча", "save_game", true)
	save_button.custom_minimum_size.x = 200
	save_row.add_child(save_button)
	column.add_child(save_row)
	status_label = _label("", 13)
	status_label.custom_minimum_size.y = 34
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	LauncherTheme.caption(status_label, 13)
	column.add_child(status_label)
	column.add_child(_menu_button("НАЗАД", _leave_save_menu, true, "Вернуться в меню", "back", true))
	_refresh_saved_games()
	_set_save_status("Сохранение выполняется…" if _saving_current_game else "Матч приостановлен. Можно сохранить его или загрузить другую игру." if is_instance_valid(active_game) else "Чтобы создать сохранение, сначала начните игру. Загрузка доступна сразу.")


func _refresh_saved_games() -> void:
	if save_list == null:
		return
	var selected_path := ""
	var selection := save_list.get_selected_items()
	if not selection.is_empty() and selection[0] < saved_games.size():
		selected_path = String(saved_games[selection[0]]["path"])
	saved_games = GameSaveArchive.list_saves()
	save_list.clear()
	var selected := 0
	for index in range(saved_games.size()):
		var entry: Dictionary = saved_games[index]
		var label := String(entry.get("slot_name", "Без названия"))
		save_list.add_item(label)
		save_list.set_item_tooltip(index, "%s\n%s" % [label, _save_description(entry)])
		if String(entry["path"]) == selected_path:
			selected = index
	if not saved_games.is_empty():
		save_list.select(selected)
		_on_save_selected(selected)
	else:
		save_details_label.text = "Сохранённых игр пока нет."
	_update_save_buttons()


func _on_save_selected(index: int) -> void:
	if index >= 0 and index < saved_games.size() and save_details_label != null:
		save_details_label.text = _save_description(saved_games[index])
	_update_save_buttons()


func _save_description(entry: Dictionary) -> String:
	var seconds := floori(float(entry.get("tick", 0)) * 0.05)
	var duration := "%02d:%02d:%02d" % [floori(seconds / 3600.0), floori(seconds / 60.0) % 60, seconds % 60]
	var saved_at := int(entry.get("saved_at_unix", 0))
	if saved_at <= 0:
		return "Игровое время: %s · Дата сохранения недоступна" % duration
	var local_time := Time.get_datetime_dict_from_unix_time(saved_at + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	return "Игровое время: %s\nСохранено: %02d.%02d.%04d в %02d:%02d" % [duration, local_time["day"], local_time["month"], local_time["year"], local_time["hour"], local_time["minute"]]


func _update_save_buttons() -> void:
	if current_screen != SCREEN_SAVES:
		return
	var can_load := not saved_games.is_empty() and not _saving_current_game
	if screen_buttons.has("load_save"):
		screen_buttons["load_save"].disabled = not can_load
	if screen_buttons.has("save_game"):
		screen_buttons["save_game"].disabled = not is_instance_valid(active_game) or _saving_current_game
	if save_name_input != null:
		save_name_input.editable = is_instance_valid(active_game) and not _saving_current_game


func _request_launcher_save() -> void:
	if not is_instance_valid(active_game) or _saving_current_game or save_name_input == null:
		return
	var name := GameSaveArchive.normalized_slot_name(save_name_input.text)
	if not GameSaveArchive.valid_slot_name(name):
		_set_save_status(GameSaveArchive.error_message("slot_name_invalid"), true)
		return
	if FileAccess.file_exists(GameSaveArchive.named_path(name)):
		_pending_save_name = name
		if _save_overwrite_dialog == null:
			_save_overwrite_dialog = ConfirmationDialog.new()
			_save_overwrite_dialog.theme = AntiqueTheme.shared_theme()
			_save_overwrite_dialog.title = "Заменить сохранение?"
			_save_overwrite_dialog.ok_button_text = "ЗАМЕНИТЬ"
			_save_overwrite_dialog.cancel_button_text = "ОТМЕНА"
			_save_overwrite_dialog.confirmed.connect(func(): _save_current_game(_pending_save_name))
			add_child(_save_overwrite_dialog)
		_save_overwrite_dialog.dialog_text = "Сохранение «%s» уже существует. Заменить его текущим матчем?" % name
		_save_overwrite_dialog.popup_centered(Vector2i(480, 160))
		return
	_save_current_game(name)


func _save_current_game(name: String) -> void:
	if not is_instance_valid(active_game) or _saving_current_game:
		return
	if not active_game.request_save_game_to_path(GameSaveArchive.named_path(name), name):
		_set_save_status(GameSaveArchive.error_message(active_game.last_save_error), true)
		return
	_saving_current_game = true
	_set_save_status("Сохранение выполняется…")
	_update_save_buttons()


func _poll_launcher_save() -> void:
	if not is_instance_valid(active_game):
		return
	var queue = active_game.background_saves
	var had_pending: bool = queue.active_request >= 0 or not queue.waiting.is_empty() or not queue.completed.is_empty()
	active_game._poll_save_jobs()
	if queue.active_request >= 0 or not queue.waiting.is_empty():
		return
	if _saving_current_game or had_pending:
		_saving_current_game = false
		if current_screen == SCREEN_SAVES:
			_refresh_saved_games()
			_set_save_status("Игра сохранена" if active_game.last_save_error.is_empty() else GameSaveArchive.error_message(active_game.last_save_error), not active_game.last_save_error.is_empty())


func _set_save_status(message: String, failed: bool = false) -> void:
	if current_screen == SCREEN_SAVES and status_label != null:
		status_label.text = message
		status_label.add_theme_color_override("font_color", Color("f1a994") if failed else AntiqueTheme.LIGHT_TEXT)


func _load_selected_save() -> void:
	if save_list == null or _saving_current_game:
		return
	var selection := save_list.get_selected_items()
	if selection.is_empty() or selection[0] >= saved_games.size():
		return
	var path := String(saved_games[selection[0]]["path"])
	_show_loading_screen("ЗАГРУЗКА СОХРАНЕНИЯ", "Восстановление вашей игры…")
	await get_tree().process_frame
	var inspected := GameSaveArchive.read(path)
	if not bool(inspected.get("valid", false)):
		_show_save_menu()
		_set_save_status(GameSaveArchive.error_message(String(inspected.get("error", "archive_invalid"))), true)
		return
	var archive: Dictionary = inspected["archive"]
	var game = GAME_SCENE.instantiate()
	if int(archive.get("format_version", 3)) == GameSaveArchive.FORMAT_VERSION:
		game.match_path = String(archive["match_path"])
		var definition := MatchDefinition.load_json(game.match_path)
		if not bool(definition.get("valid", false)):
			game.free()
			_show_save_menu()
			_set_save_status("Исходная карта этого сохранения не найдена", true)
			return
	game.process_mode = Node.PROCESS_MODE_DISABLED
	game.hide()
	get_tree().root.add_child(game)
	if not game.load_game_from_path(path):
		var message := GameSaveArchive.error_message(game.last_save_error)
		game.queue_free()
		_show_save_menu()
		_set_save_status(message, true)
		return
	_discard_active_game()
	await get_tree().process_frame
	game.resume_from_launcher()
	get_tree().current_scene = game
	queue_free()


func _leave_save_menu() -> void:
	if _save_menu_parent == SCREEN_SINGLE_PLAYER:
		_show_single_player_menu()
	else:
		_show_main_menu()


func _resume_active_game() -> void:
	if not is_instance_valid(active_game):
		return
	var game = active_game
	active_game = null
	game.resume_from_launcher()
	get_tree().current_scene = game
	queue_free()


func _discard_active_game() -> void:
	if is_instance_valid(active_game):
		active_game.queue_free()
	active_game = null
	_saving_current_game = false
