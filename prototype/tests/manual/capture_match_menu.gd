extends SceneTree
const Overlay := preload("res://scripts/hud_modal_overlay.gd")
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
	print("Menu capture matrix completed (47 frames). Synthetic 8-player history for layout review.")
	quit()
