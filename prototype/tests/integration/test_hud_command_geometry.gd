extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const ViewModel := preload("res://scripts/hud_view_model.gd")
const HUD := preload("res://scripts/hud_controls.gd")
const Layout := preload("res://scripts/interface_layout.gd")
var failures: Array[String] = []
var reached_late_builds := 0


func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var view = ViewModel.new()
	view.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var hud = HUD.new()
	viewport.add_child(hud)
	hud.configure_icons(catalog.interface_icons)
	for civilization_id in range(1, 17):
		var style: int = catalog.interface_skin.style_index_for_civilization(civilization_id, catalog.object_catalog_data)
		hud.configure_interface_skin(catalog.interface_skin, style)
		var world = World.new(Vector2i(64, 64))
		world.set_gamespec(catalog.gamespec_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_team_civilization(1, civilization_id)
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		var completed_buildings := 0
		for kind in ["town_center", "house", "barracks", "granary", "storage_pit", "dock"]:
			world.add_building(1000 + completed_buildings, kind, Vector2(4 + (completed_buildings % 5) * 10, 20 + (completed_buildings / 5) * 10), 1)
			completed_buildings += 1
		var worker: Dictionary = world.add_unit(1, "villager", Vector2(10, 10), false)
		var ids: Array[int] = [int(worker["id"])]
		for age_technology in [-1, 101, 102, 103]:
			if age_technology >= 0:
				world.grant_technology(1, age_technology)
			var new_buildings: Array = ["archery_range", "stable", "market"] if age_technology == 101 else ["academy", "government_center", "temple", "siege_workshop"] if age_technology == 102 else []
			for kind in new_buildings:
				world.add_building(1000 + completed_buildings, kind, Vector2(4 + (completed_buildings % 5) * 10, 20 + (completed_buildings / 5) * 10), 1)
				completed_buildings += 1
			if age_technology == 103:
				world.grant_technology(1, 16)
				world.grant_technology(1, 12)
			var snapshot: Dictionary = Snapshot.presentation(world, 0, 1, {"always_include_entity_ids": ids, "command_option_entity_ids": ids})
			var model: Dictionary = view.build(snapshot, ids, "LINE", "ru")
			var build_count: int = model["commands"].filter(func(command): return command.get("type") == "build").size()
			if age_technology == 103:
				reached_late_builds = maxi(reached_late_builds, build_count)
			for width in [320, 640, 800, 1024, 1280, 1920, 2560]:
				viewport.size = Vector2i(width, 720)
				hud.size = Vector2(width, 720)
				hud.set_layout(Layout.for_viewport(hud.size))
				hud.set_view_model(model)
				var reserved: Rect2 = hud.current_layout["command"]
				var production: Rect2 = hud.current_layout["production"]
				var context := "civilization %d / age %d / width %d" % [civilization_id, age_technology, width]
				check(production.size.x <= Layout.PRODUCTION_MAX_WIDTH, context + ": progress region stays bounded")
				if not hud.build_menu_open:
					hud.set_build_menu_open(true)
				check(hud.build_menu_open, context + ": worker opens construction")
				check(hud.current_layout["command"] == reserved and hud.current_layout["production"] == production, context + ": opening construction does not squeeze either area")
				if width >= 1280:
					check(hud.command_page_count == 1, context + ": complete real building palette fits without paging")
				var reached: Dictionary = {}
				for page in range(hud.command_page_count):
					hud.command_page = page
					hud.layout_controls()
					await process_frame
					for index in range(hud.active_train_commands.size()):
						var button: Button = hud.train_buttons[index]
						if not button.visible:
							continue
						reached[index] = true
						check(button.size == Vector2(50, 50), context + ": command size remains 50px")
						check(reserved.encloses(button.get_rect()), context + ": command fits its reserved grid")
						check(button.icon != null, context + ": native building or cancel-cross artwork loads")
						check(not production.intersects(button.get_rect()), context + ": progress cannot overlap a command")
					check(hud.train_buttons[build_count].visible, context + ": Back remains accessible")
					check(hud.train_buttons[build_count].icon == catalog.interface_icons.texture("command", 10), context + ": Back uses the original red cross")
					check(hud.train_buttons[build_count].get_rect().end.y <= reserved.end.y, context + ": cancel cross stays inside the command grid")
					for button in [hud.previous_commands_button, hud.next_commands_button]:
						if button.visible:
							check(reserved.encloses(button.get_rect()), context + ": page button fits its reserved grid")
				check(reached.size() == build_count + 1, context + ": every unlocked building is reachable")
				var retained_page: int = hud.command_page
				hud.set_view_model(model)
				check(hud.command_page == retained_page, context + ": routine simulation refresh does not turn the page")
				hud.train_buttons[build_count].emit_signal("pressed")
				check(not hud.build_menu_open and hud.command_page == 0, context + ": Back restores the worker commands")
		print("Fixed command grid verified for civilization %d through all four ages" % civilization_id)
	print("Maximum real late-age build count: %d" % reached_late_builds)
	check(reached_late_builds >= 14, "fixture exercises a dense late-age palette")
	# Clicking an item on another page must still address its original command index.
	var orders: Array = []
	for index in range(30):
		orders.append({"type": "research", "id": str(index), "technology_id": index, "building_id": 80, "label": "Research", "enabled": true})
	hud.size = Vector2(800, 720)
	hud.set_layout(Layout.for_viewport(hud.size))
	hud.set_view_model({"selection": {"category": "building", "leader": {"id": 80}}, "commands": orders})
	var requested: Array = []
	hud.research_requested.connect(func(technology_id: int, building_id: int): requested.append([technology_id, building_id]))
	hud.next_commands_button.emit_signal("pressed")
	var original_index: int = hud.command_page_size
	hud.train_buttons[original_index].emit_signal("pressed")
	check(requested == [[original_index, 80]], "second-page research retains the original technology and producer")
	hud.set_view_model({"selection": {"category": "unit", "leader": {"id": 81}}, "commands": []})
	check(hud.command_page == 0 and not hud.next_commands_button.visible and not hud.previous_commands_button.visible, "selection change clears command pagination")
	viewport.free()
	for failure in failures:
		push_error(failure)
	print("Fixed-size command geometry and civilization/age matrix: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func check(value: bool, description: String) -> void:
	if not value:
		failures.append(description)
