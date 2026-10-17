extends SceneTree
const Overlay := preload("res://scripts/hud_modal_overlay.gd")
const Scenario := preload("res://scripts/scenario_overlay.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	var viewport := SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var backdrop := ColorRect.new()
	backdrop.color = Color("39372e")
	backdrop.size = Vector2(2560,1440)
	viewport.add_child(backdrop)
	var menu := Overlay.new()
	viewport.add_child(menu)
	menu.configure(catalog.interface_skin, {"title":"Римская экспедиция", "map":{"size":Vector2i(72,72),"seed":41721},"players":[{"team":1}]},4,catalog.localization)
	menu.set_preferences({"screen_size":Vector2i(1280,720)},1.5)
	menu.set_named_saves([{"slot_name":"Рим перед осадой","path":"fixture","tick":72000,"saved_at_unix":1792180000}])
	var history := {"teams":{},"samples":[],"markers":[],"current_tick":72000,"start_tick":0,"reveal_all":true}
	var names := ["Вы · Римляне", "Ганнибал · Карфагеняне", "Перикл · Греки", "Рамсес · Египтяне", "Хаммурапи · Вавилоняне", "Кир · Персы", "Саргон · Ассирийцы", "Тан · Шан"]
	for team in range(1,9): history["teams"][team] = {"name":names[team-1],"population":40+team*2,"peak_population":60,"age":103,"status":"active","produced":40+team*7,"kills":team*9,"lost":team*3,"gathered":[team*1230,team*2451,team*521,team*847],"research":8+team}
	for i in range(13):
		var values := {}
		for team in range(1,9): values[team] = {"population":maxi(3,3+i*4+team*2-roundi(14*maxf(0,sin(i+team)))),"age":100}
		if i >= 7: values[7]["population"] = 0
		if i >= 10: values[2]["population"] = 0
		history["samples"].append({"tick":i*6000,"teams":values})
	for team in range(1,9):
		for age in range(101,104):
			if team == 7 and age == 103: continue
			history["markers"].append({"tick":(age-100)*15000+team*500,"team":team,"kind":"age","value":age})
	history["markers"].append({"tick":42000,"team":7,"kind":"player_defeated"})
	history["markers"].append({"tick":60000,"team":2,"kind":"player_resigned"})
	history["teams"][7]["status"] = "defeated"
	history["teams"][7]["population"] = 0
	history["teams"][2]["status"] = "resigned"
	history["teams"][2]["population"] = 0
	menu.set_statistics(history)
	menu.set_instructions({"title":"Римская экспедиция","briefing":"Развивайте поселение и защитите союзников.","hints":"Исследуйте берег и постройте порт.","history":"Рим борется за контроль над Средиземноморьем.","objectives":[{"label":"Уничтожьте вражеский лагерь","achieved":false}]})
	menu.show_menu()
	for dimensions in [Vector2i(640,480),Vector2i(800,600),Vector2i(1024,768),Vector2i(1280,720),Vector2i(1920,1080)]:
		viewport.size = dimensions
		menu.set_viewport_size(Vector2(dimensions))
		for section in ["menu","save","load","settings","achievements","timeline","instructions","help","confirm"]:
			if section == "confirm": menu.request_confirmation("restart")
			else: menu.show_section(section)
			if section == "timeline": menu.timeline._select(8); menu.timeline_rows[1].select(0); menu._show_timeline_events()
			for _frame in range(3): await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://../tmp/menu-%s-%dx%d.png" % [section,dimensions.x,dimensions.y])
			if section == "timeline" and dimensions == Vector2i(640,480):
				menu.timeline_roster_button.pressed.emit()
				for _frame in range(3): await process_frame
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("res://../tmp/menu-timeline-players-640x480.png")
				menu.timeline_roster_button.pressed.emit()
			if section == "timeline" and dimensions == Vector2i(1280,720):
				menu.timeline_mode.select(1)
				menu.timeline_mode.item_selected.emit(1)
				for _frame in range(3): await process_frame
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("res://../tmp/menu-timeline-count-1280x720.png")
				menu.timeline_mode.select(0)
				menu.timeline_mode.item_selected.emit(0)
	for dimensions in [Vector2i(640,480),Vector2i(1280,720)]:
		viewport.size = dimensions
		menu.set_viewport_size(Vector2(dimensions))
		var players: Array = []
		for team in range(1,9): players.append({"team":team,"civilization_id":13 if team == 1 else team,"controller":"human" if team == 1 else "ai","status":"active"})
		menu.set_snapshot({"player_state":{"team":1,"allies":[1,3],"players":players}})
		menu.show_diplomacy()
		for _frame in range(4): await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png("res://../tmp/menu-diplomacy-%dx%d.png" % [dimensions.x,dimensions.y])
		print("Diplomacy %s: panel=%s min=%s rows=%s" % [dimensions,menu.diplomacy_panel.get_global_rect(),menu.diplomacy_panel.get_combined_minimum_size(),menu.diplomacy_rows.get_global_rect()])
		var column = menu.diplomacy_rows.get_parent().get_parent()
		for child in column.get_children():
			if child is Control: print("  %s %s min=%s" % [child.get_class(),child.get_global_rect(),child.get_combined_minimum_size()])
	menu.close()
	var scenario := Scenario.new()
	viewport.add_child(scenario)
	for dimensions in [Vector2i(640,480), Vector2i(1280,720), Vector2i(1920,1080)]:
		viewport.size = dimensions
		scenario.size = Vector2(dimensions)
		scenario.visible = true
		scenario.briefing_title.text = "РИМСКАЯ ЭКСПЕДИЦИЯ"
		scenario.briefing_text.text = "Сенат поручил вам укрепить границу и обеспечить безопасность союзников. Развивайте поселение, защитите торговые пути и захватите укрепления противника."
		scenario.briefing_objectives.text = "ЦЕЛИ\n• Постройте укреплённое поселение.\n• Защитите союзников.\n• Уничтожьте вражеский лагерь."
		for section in ["briefing", "result"]:
			scenario.briefing_layer.visible = section == "briefing"
			scenario.result_layer.visible = section == "result"
			scenario.result_title.text = "ПОБЕДА"
			scenario.result_text.text = "Условие победы: завоевание."
			for _frame in range(4): await process_frame
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://../tmp/menu-%s-%dx%d.png" % [section,dimensions.x,dimensions.y])
	print("Match screen capture completed: 47 menu frames + 2 diplomacy frames + 6 scenario frames. Synthetic history/briefing fixtures for layout review.")
	quit()
