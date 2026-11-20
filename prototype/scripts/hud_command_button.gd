extends Button

var command_selected := false:
	set(value):
		if command_selected != value:
			command_selected = value
			queue_redraw()


func _draw() -> void:
	if disabled:
		return
	var selected := command_selected or (toggle_mode and button_pressed)
	if selected or is_hovered():
		var rim := Rect2(Vector2(1.5, 1.5), size - Vector2(3.0, 3.0))
		draw_rect(rim, Color("211a12"), false, 3.0)
		draw_rect(rim, Color("f3cd79") if selected else Color("c9b694"), false, 1.0)


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TooltipPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.theme_type_variation = "TooltipLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = for_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	var font := label.get_theme_font("font")
	var width := 0.0
	for line in for_text.split("\n"):
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
	label.custom_minimum_size.x = clampf(ceilf(width), 1.0, maxf(1.0, minf(480.0, get_viewport_rect().size.x - 32.0)))
	panel.add_child(label)
	return panel
