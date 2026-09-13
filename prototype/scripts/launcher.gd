class_name RoRLauncher
extends Control

const MatchRegistry := preload("res://scripts/match_registry.gd")
const GAME_SCENE := preload("res://main.tscn")

var match_selector: OptionButton
var description_label: Label
var status_label: Label
var start_button: Button
var available_matches: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
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
		_launch_entry(requested)


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color("101820")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-330, -225)
	panel.size = Vector2(660, 450)
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
	start_button.disabled = not bool(entry["available"])
	status_label.text = "Готово к запуску" if bool(entry["available"]) else "Данные матча отсутствуют — выполните импорт ресурсов"


func _launch_selected() -> void:
	var index := match_selector.selected
	if index < 0 or index >= available_matches.size():
		return
	_launch_entry(available_matches[index])


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
