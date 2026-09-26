class_name RoRScenarioOverlay
extends Control

signal restart_requested
signal menu_requested

const PresentationModel := preload("res://scripts/scenario_presentation_model.gd")

var model_builder := PresentationModel.new()
var match_definition: Dictionary = {}
var presentation_model: Dictionary = {}
var briefing_dismissed := false
var result_dismissed := false

var briefing_layer: ColorRect
var briefing_title: Label
var briefing_text: Label
var briefing_objectives: Label
var objectives_panel: PanelContainer
var objectives_text: Label
var result_layer: ColorRect
var result_title: Label
var result_text: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	visible = false


func configure(definition: Dictionary, localization_catalog, object_data: Dictionary) -> void:
	match_definition = definition.duplicate(true)
	model_builder.configure(localization_catalog, object_data)


func reset_presentation() -> void:
	briefing_dismissed = false
	result_dismissed = false
	presentation_model.clear()
	visible = false


func set_snapshot(snapshot: Dictionary) -> void:
	var observer_team := int(snapshot.get("observer_team", match_definition.get("local_team", 1)))
	var scenario_state: Dictionary = snapshot.get("scenario", {}).duplicate(true)
	if not bool(scenario_state.get("result", {}).get("over", false)) and bool(snapshot.get("match_result", {}).get("over", false)):
		scenario_state["result"] = snapshot.get("match_result", {}).duplicate(true)
	presentation_model = model_builder.build(match_definition, scenario_state, observer_team, "ru")
	if not bool(presentation_model.get("visible", false)) and bool(scenario_state.get("result", {}).get("over", false)):
		var match_result: Dictionary = scenario_state["result"]
		var winning_side: Array = match_result.get("winner_teams", [int(match_result.get("winner_team", -1))])
		presentation_model = {
			"visible": true,
			"title": String(match_definition.get("title", "Матч")),
			"briefing": "",
			"objectives": [],
			"over": true,
			"outcome": "victory" if observer_team in winning_side else "defeat",
		}
	visible = bool(presentation_model.get("visible", false))
	if not visible:
		return
	var objective_lines := _objective_lines(presentation_model.get("objectives", []))
	briefing_title.text = String(presentation_model.get("title", "Сценарий"))
	briefing_text.text = String(presentation_model.get("briefing", ""))
	briefing_objectives.text = objective_lines
	objectives_text.text = objective_lines
	var over := bool(presentation_model.get("over", false))
	briefing_layer.visible = not briefing_dismissed and not over
	result_layer.visible = over and not result_dismissed
	objectives_panel.visible = briefing_dismissed and not result_layer.visible
	if over:
		var victory := String(presentation_model.get("outcome", "")) == "victory"
		result_title.text = "ПОБЕДА" if victory else "ПОРАЖЕНИЕ"
		var reason := String(scenario_state.get("result", {}).get("reason", ""))
		var reason_label := String({"conquest": "завоевание", "score": "счёт или время", "wonder": "чудо света", "ruins": "руины", "artifacts": "артефакты", "scenario": "условия сценария"}.get(reason, reason))
		result_text.text = "Условие победы: %s." % reason_label if not reason_label.is_empty() else "Матч завершён."


func is_blocking() -> bool:
	return visible and (briefing_layer.visible or result_layer.visible)


func _objective_lines(objectives: Array) -> String:
	var lines: Array[String] = ["ЦЕЛИ"]
	for objective_value in objectives:
		var objective: Dictionary = objective_value
		var marker := "✓" if bool(objective.get("achieved", false)) else "•"
		lines.append("%s %s  (%d/%d)" % [marker, String(objective.get("label", "")), int(objective.get("current", 0)), int(objective.get("required", 0))])
	return "\n".join(lines)


func _build_interface() -> void:
	objectives_panel = PanelContainer.new()
	objectives_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	objectives_panel.position = Vector2(-470, 52)
	objectives_panel.size = Vector2(450, 112)
	objectives_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objectives_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.055, 0.06, 0.91)))
	objectives_text = Label.new()
	objectives_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objectives_text.add_theme_font_size_override("font_size", 14)
	objectives_text.add_theme_color_override("font_color", Color("f4e8c7"))
	objectives_panel.add_child(_with_margin(objectives_text, 12))
	add_child(objectives_panel)

	briefing_layer = _full_layer()
	var briefing_panel := _center_panel(Vector2(720, 500))
	briefing_layer.add_child(briefing_panel)
	var briefing_column := _panel_column(briefing_panel)
	briefing_title = _heading_label()
	briefing_column.add_child(briefing_title)
	briefing_text = _body_label(140)
	briefing_column.add_child(briefing_text)
	briefing_objectives = _body_label(120)
	briefing_column.add_child(briefing_objectives)
	var begin_button := Button.new()
	begin_button.text = "НАЧАТЬ МИССИЮ"
	begin_button.custom_minimum_size.y = 46
	begin_button.pressed.connect(_dismiss_briefing)
	briefing_column.add_child(begin_button)
	add_child(briefing_layer)

	result_layer = _full_layer()
	var result_panel := _center_panel(Vector2(600, 330))
	result_layer.add_child(result_panel)
	var result_column := _panel_column(result_panel)
	result_title = _heading_label()
	result_column.add_child(result_title)
	result_text = _body_label(76)
	result_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_column.add_child(result_text)
	var observe_button := Button.new()
	observe_button.text = "НАБЛЮДАТЬ"
	observe_button.custom_minimum_size.y = 42
	observe_button.pressed.connect(_dismiss_result)
	result_column.add_child(observe_button)
	var retry_button := Button.new()
	retry_button.text = "ПОВТОРИТЬ"
	retry_button.custom_minimum_size.y = 42
	retry_button.pressed.connect(func(): restart_requested.emit())
	result_column.add_child(retry_button)
	var menu_button := Button.new()
	menu_button.text = "ВЫБОР ИГРЫ"
	menu_button.custom_minimum_size.y = 42
	menu_button.pressed.connect(func(): menu_requested.emit())
	result_column.add_child(menu_button)
	add_child(result_layer)


func _dismiss_briefing() -> void:
	briefing_dismissed = true
	briefing_layer.visible = false
	objectives_panel.visible = true


func _dismiss_result() -> void:
	result_dismissed = true
	result_layer.visible = false


func _full_layer() -> ColorRect:
	var layer := ColorRect.new()
	layer.color = Color(0.01, 0.015, 0.02, 0.82)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	return layer


func _center_panel(panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.10, 0.08, 0.055, 0.98)))
	return panel


func _panel_column(panel: PanelContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(_with_margin(column, 30))
	return column


func _with_margin(child: Control, amount: int) -> MarginContainer:
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, amount)
	margin.add_child(child)
	return margin


func _heading_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color("f1d890"))
	return label


func _body_label(minimum_height: float) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.y = minimum_height
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("e6d6ae"))
	return label


func _panel_style(fill: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = Color("c6a866")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style
