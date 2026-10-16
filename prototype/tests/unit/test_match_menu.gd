extends SceneTree

const Overlay := preload("res://scripts/hud_modal_overlay.gd")
const Adapter := preload("res://scripts/input_adapter.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var viewport := SubViewport.new()
	root.add_child(viewport)
	var menu := Overlay.new()
	viewport.add_child(menu)
	menu.configure(null, {"players": [{"team": 1}], "map": {"size": Vector2i(24,24)}})
	menu.set_preferences({"screen_size": Vector2i(800,600)}, 1.5)
	menu.set_named_saves([{"slot_name": "Рим", "path": "user://saves/named/a.json", "tick": 100}])
	menu.show_menu()
	for dimensions in [Vector2i(320,240), Vector2i(640,480), Vector2i(800,600), Vector2i(1024,768), Vector2i(1280,720), Vector2i(1366,768), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440)]:
		viewport.size = dimensions
		menu.set_viewport_size(Vector2(dimensions))
		for section in menu.pages:
			menu.show_section(section)
			await process_frame
			await process_frame
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(0.1)
			check(bounds.encloses(menu.menu_panel.get_global_rect()), "%s at %s fits viewport: %s" % [section, dimensions, menu.menu_panel.get_global_rect()])
			check(bounds.encloses(menu.back_button.get_global_rect()), "%s at %s retains Back" % [section, dimensions])
			if section == "menu" and dimensions.x >= 640:
				for button in menu.menu_buttons.values():
					if button == menu.resume_button: continue
					check(menu.body_scroll.get_global_rect().grow(1).encloses(button.get_global_rect()), "root action %s fits at %s" % [button.text, dimensions])
	menu.set_statistics({"current_tick": 400, "start_tick": 0, "reveal_all": true, "teams": {1:{"name":"Римляне"}, 2:{"name":"Греки"}}, "samples": [{"tick":0,"teams":{1:{"population":3,"age":100},2:{"population":1,"age":100}}}, {"tick":200,"teams":{1:{"population":12,"age":100},2:{"population":8,"age":100}}}, {"tick":400,"teams":{1:{"population":0,"age":101},2:{"population":10,"age":100}}}], "markers":[{"team":1,"tick":150,"kind":"age","value":101}]})
	menu.show_section("timeline")
	viewport.size = Vector2i(640,480)
	menu.set_viewport_size(Vector2(640,480))
	await process_frame
	await process_frame
	check(menu.timeline_roster_button.visible and menu.timeline.visible and not menu.timeline_side.visible, "compact timeline initially shows the complete graph")
	check(menu.body_scroll.get_global_rect().grow(1).encloses(menu.timeline.get_global_rect()), "640x480 chart includes its axes without scrolling")
	menu.timeline_roster_button.pressed.emit()
	check(menu.timeline_side.visible and not menu.timeline.visible, "compact timeline provides a separate readable player table")
	menu.timeline_roster_button.pressed.emit()
	menu.timeline._select(1)
	check(menu.timeline_readout.text.contains("00:00:10") and menu.timeline_readout.text.contains("20"), "timeline cursor displays the recorded time and total")
	check(menu.timeline_rows[1].get_text(1) == "12" and menu.timeline_rows[1].get_text(2) == "60.0%", "timeline table uses population and population share at selected time")
	check(menu.timeline_rows[1].get_text(3) == "Эпоха орудий", "exact age event takes precedence over sparse population sampling")
	menu.timeline_rows[1].select(0)
	menu._show_timeline_events()
	check(menu.timeline_event.text.contains("00:00:07") and menu.timeline_event.text.contains("Эпоха орудий"), "selected player has a readable dated event list")
	var cursor_key := InputEventKey.new()
	cursor_key.pressed = true
	cursor_key.keycode = KEY_END
	menu.timeline._gui_input(cursor_key)
	check(menu.timeline_rows[1].get_text(1) == "0", "keyboard End reaches extinction without losing the player row")
	cursor_key.keycode = KEY_LEFT
	menu.timeline._gui_input(cursor_key)
	check(menu.timeline_rows[1].get_text(1) == "12", "keyboard Left moves to previous recorded population")
	menu.timeline.hidden_teams[2] = true
	menu._update_timeline_readout()
	check(menu.timeline_rows[1].get_text(2) == "100.0%" and menu.timeline_rows[2].get_text(2) == "—", "filtered population shares have a consistent visible denominator")
	menu.timeline.hidden_teams[1] = true
	menu._update_timeline_readout()
	check(menu.timeline_readout.text.contains("Население: 0"), "empty selection is explicit and does not divide by zero")
	menu.timeline.hidden_teams.clear()
	menu.statistic_tabs[1].pressed.emit()
	check(menu.stats_table.columns == 6, "military tab opens comparable player columns")
	menu.statistic_tabs[2].pressed.emit()
	check(menu.stats_table.get_column_title(1) == "Еда", "economy tab opens resource totals")
	menu.statistic_tabs[4].pressed.emit()
	check(menu.stats_table.get_root().get_child(0).get_text(2) == "00:00:07", "technology table exposes recorded age transition times")
	var emitted: Array = []
	menu.named_save_requested.connect(func(name: String): emitted.append(["save", name]))
	menu.named_load_requested.connect(func(path: String): emitted.append(["load", path]))
	menu.restart_requested.connect(func(): emitted.append(["restart"]))
	menu.resign_requested.connect(func(): emitted.append(["resign"]))
	menu.quit_requested.connect(func(): emitted.append(["quit"]))
	menu.launcher_requested.connect(func(): emitted.append(["launcher"]))
	for action in ["restart", "resign", "quit", "launcher"]:
		menu.show_section("menu")
		menu.request_confirmation(action)
		check(emitted.is_empty(), "%s waits for confirmation" % action)
		check(menu.cancel_button.has_focus(), "cancellation has initial focus")
		menu.go_back()
		check(menu.active_section == "menu" and emitted.is_empty(), "Escape cancels %s" % action)
	menu.show_section("save")
	menu.named_save_input.text = "Рим"
	menu._request_save()
	check(menu.active_section == "confirm" and emitted.is_empty(), "existing named save cannot be silently overwritten")
	menu._confirm_action()
	menu._confirm_action()
	check(emitted == [["save", "Рим"]], "overwrite confirmation emits only once")
	emitted.clear()
	menu.show_section("load")
	menu._request_load()
	check(menu.active_section == "confirm" and emitted.is_empty(), "loading waits for confirmation")
	menu.go_back()
	check(menu.active_section == "load", "cancel returns to selected save list")
	menu._request_load()
	menu._confirm_action()
	check(emitted == [["load", "user://saves/named/a.json"]], "confirmed load retains the selected path")
	menu.set_capabilities(true)
	menu.show_section("menu")
	for key in ["save", "load", "restart"]: check(menu.menu_buttons[key].disabled, "network %s explains unsupported capability" % key)
	check(menu.network_note.text.contains("продолжается"), "network menu does not claim the match is paused")
	viewport.free()
	for failure in failures: push_error(failure)
	print("Match menu scenarios/layout: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
