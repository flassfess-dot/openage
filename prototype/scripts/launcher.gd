class_name RoRLauncher
extends Control

const MatchRegistry := preload("res://scripts/match_registry.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const GenerationJob := preload("res://scripts/skirmish_generation_job.gd")
const LauncherTheme := preload("res://scripts/launcher_theme.gd")
const GAME_SCENE := preload("res://main.tscn")

const SCREEN_MAIN := "main"
const SCREEN_SINGLE_PLAYER := "single_player"
const SCREEN_CAMPAIGNS := "campaigns"
const SCREEN_RANDOM_MAP := "random_map"
const SCREEN_LOADING := "loading"

const BACKGROUND_MAIN := "res://assets/menu/main-menu.png"
const BACKGROUND_SINGLE_PLAYER := "res://assets/menu/single-player.png"
const BACKGROUND_BATTLE := "res://assets/menu/single-player.png"
const BACKGROUND_PARCHMENT := "res://assets/menu/random-map.png"
const DEFAULT_MAP_SIZE_ID := "supergiant"
const DEFAULT_POPULATION_LIMIT := 500

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
var _background_image: TextureRect
var _background_tint: ColorRect
var _screen_root: Control
var _generation_job: RefCounted
var _generation_started_at := 0
var _finishing_generation := false


func _ready() -> void:
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
	_screen_root.size = Vector2(800.0, 600.0)
	_virtual_canvas.add_child(_screen_root)
	return _screen_root


func _show_main_menu() -> void:
	var root := _begin_screen(SCREEN_MAIN, BACKGROUND_MAIN, Color(0.0, 0.0, 0.0, 0.03))
	var panel := _make_panel(root, Vector2(452, 258), Vector2(320, 320), false)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	panel.add_child(column)

	var heading := _label("ГЛАВНОЕ МЕНЮ", 18, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.heading(heading, 18)
	column.add_child(heading)
	column.add_child(_menu_button("ОДИНОЧНАЯ ИГРА", _show_single_player_menu, true, "Кампании и случайная карта", "single_player"))
	column.add_child(_menu_button("СЕТЕВАЯ ИГРА", Callable(), false, "Сетевой режим ещё не готов", "multiplayer"))
	column.add_child(_menu_button("РЕДАКТОР СЦЕНАРИЕВ", Callable(), false, "Редактор сценариев ещё не готов", "scenario_editor"))
	column.add_child(_menu_button("СПРАВКА", Callable(), false, "Раздел справки ещё не готов", "help"))
	column.add_child(_menu_button("ВЫХОД", _quit_game, true, "Выйти из игры", "exit"))

	status_label = _label("Недоступные разделы отмечены серым", 11, HORIZONTAL_ALIGNMENT_CENTER)
	LauncherTheme.caption(status_label, 11)
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
	column.add_child(_menu_button("СОХРАНЁННАЯ ИГРА", Callable(), false, "Загрузка сохранений ещё не готова", "saved_game"))
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
	var root := _begin_screen(SCREEN_RANDOM_MAP, BACKGROUND_PARCHMENT, Color(0.0, 0.0, 0.0, 0.24))
	setting_controls.clear()
	player_controls.clear()
	root.add_child(_screen_title("СЛУЧАЙНАЯ КАРТА"))
	settings_panel = _make_panel(root, Vector2(22, 48), Vector2(756, 478), true)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	settings_panel.add_child(content)
	content.add_child(_build_general_settings())
	content.add_child(_build_player_settings())

	var footer := HBoxContainer.new()
	footer.position = Vector2(26, 539)
	footer.size = Vector2(748, 48)
	footer.add_theme_constant_override("separation", 10)
	root.add_child(footer)
	status_label = _label("Случайная цивилизация определяется по seed карты", 12)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	LauncherTheme.caption(status_label, 12)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 3)
	footer.add_child(status_label)
	footer.add_child(_menu_button("НАЗАД", _show_single_player_menu, true, "Вернуться", "back", true))
	start_button = _menu_button("НАЧАТЬ ИГРУ", _launch_custom_skirmish, bool(skirmish_catalog.get("valid", false)), "Создать случайную карту", "start", true)
	footer.add_child(start_button)


func _build_general_settings() -> Control:
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 318.0
	column.add_theme_constant_override("separation", 8)
	var heading := _label("ПАРАМЕТРЫ ИГРЫ", 16)
	LauncherTheme.heading(heading, 16)
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 5)
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
	LauncherTheme.apply_spin_box(count_control, 172.0)
	grid.add_child(count_control)
	setting_controls["player_count"] = count_control

	grid.add_child(_field_label("Seed карты"))
	var seed_control := SpinBox.new()
	seed_control.min_value = 1
	seed_control.max_value = 2147483647
	seed_control.step = 1
	seed_control.value = 41721
	LauncherTheme.apply_spin_box(seed_control, 172.0)
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
	column.add_theme_constant_override("separation", 5)
	var heading := _label("ИГРОКИ", 16)
	LauncherTheme.heading(heading, 16)
	column.add_child(heading)
	var headers := HBoxContainer.new()
	headers.add_theme_constant_override("separation", 4)
	column.add_child(headers)
	for header_data in [["№", 24], ["Игрок", 88], ["Цивилизация", 137], ["Цвет", 51], ["Союз", 51]]:
		var header := _label(String(header_data[0]), 11, HORIZONTAL_ALIGNMENT_CENTER)
		header.custom_minimum_size.x = float(header_data[1])
		LauncherTheme.caption(header, 11)
		headers.add_child(header)
	for slot in range(1, 9):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		column.add_child(row)
		var slot_label := _label(str(slot), 13, HORIZONTAL_ALIGNMENT_CENTER)
		slot_label.custom_minimum_size.x = 24
		LauncherTheme.body(slot_label, 13)
		row.add_child(slot_label)

		var controller := OptionButton.new()
		LauncherTheme.apply_option(controller, 88.0)
		_add_option_item(controller, "Игрок", "human")
		_add_option_item(controller, "Компьютер", "ai")
		_add_option_item(controller, "Закрыт", "closed")
		_select_metadata(controller, "human" if slot == 1 else "ai" if slot == 2 else "closed")
		row.add_child(controller)

		var civilization := OptionButton.new()
		LauncherTheme.apply_option(civilization, 137.0)
		for civilization_value in skirmish_catalog.get("civilizations", []):
			var civilization_entry: Dictionary = civilization_value
			_add_option_item(civilization, String(civilization_entry.get("name", "?")), int(civilization_entry.get("id", 0)))
		_select_metadata(civilization, 0)
		row.add_child(civilization)

		var color := OptionButton.new()
		LauncherTheme.apply_option(color, 51.0)
		for color_index in range(1, 9):
			_add_option_item(color, str(color_index), color_index)
		_select_metadata(color, slot)
		row.add_child(color)

		var alliance := OptionButton.new()
		LauncherTheme.apply_option(alliance, 51.0)
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
	LauncherTheme.apply_option(option, 172.0)
	for entry_value in entries:
		var entry: Dictionary = entry_value
		_add_option_item(option, String(entry.get("name", entry.get("id", "?"))), String(entry.get("id", "")))
	_select_metadata(option, default_id)
	parent.add_child(option)
	return option


func _add_value_option(parent: Control, title: String, entries: Array, default_value: int) -> OptionButton:
	parent.add_child(_field_label(title))
	var option := OptionButton.new()
	LauncherTheme.apply_option(option, 172.0)
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
	var label := _label(text, 12)
	label.custom_minimum_size = Vector2(126, 34)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	LauncherTheme.body(label, 12)
	return label


func _style_checkbox(check_box: CheckBox) -> void:
	check_box.custom_minimum_size.y = 32
	check_box.add_theme_color_override("font_color", LauncherTheme.GOLD_BRIGHT)
	check_box.add_theme_color_override("font_disabled_color", LauncherTheme.MUTED)


func _quit_game() -> void:
	get_tree().quit()
