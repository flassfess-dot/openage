extends Button


func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TooltipPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.theme_type_variation = "TooltipLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = for_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = minf(480.0, get_viewport_rect().size.x - 32.0)
	label.add_theme_font_size_override("font_size", 16)
	panel.add_child(label)
	return panel
