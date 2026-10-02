extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const ViewModel := preload("res://scripts/hud_view_model.gd")
const HUD := preload("res://scripts/hud_controls.gd")
const Layout := preload("res://scripts/interface_layout.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.grant_technology(1, 101)
	world.grant_technology(1, 102)
	world.grant_technology(1, 103)
	var view = ViewModel.new()
	view.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var hud = HUD.new()
	viewport.add_child(hud)
	hud.configure_icons(catalog.interface_icons)
	hud.configure_interface_skin(catalog.interface_skin, 4)
	hud.size = Vector2(1280, 720)
	hud.set_layout(Layout.for_viewport(hud.size))
	for kind in ["clubman", "archer", "villager", "scout_ship", "fishing_boat", "trade_boat", "transport", "catapult_trireme", "stone_thrower", "ballista", "priest"]:
		var unit: Dictionary = world.add_unit(1, kind, Vector2(10, 10), false)
		if kind == "villager":
			unit["carried_amount"] = 10
			unit["carried_resource_type_id"] = 0
		var ids: Array[int] = [int(unit["id"])]
		var snapshot: Dictionary = Snapshot.presentation(world, 0, 1, {"always_include_entity_ids": ids, "command_option_entity_ids": ids})
		var model: Dictionary = view.build(snapshot, ids, "LINE", "ru")
		hud.set_view_model(model)
		await process_frame
		check(model["selection"]["category"] == "unit", kind + ": categorized as unit")
		check(hud.status_panel.portrait.texture != null, kind + ": real portrait loads")
		check(not hud.status_panel.name_label.text.is_empty(), kind + ": localized name appears")
		check(not hud.status_panel.stats_label.text.is_empty(), kind + ": HP appears")
		check(not hud.status_panel.job_label.visible and not hud.status_panel.cancel_button.visible, kind + ": production controls hidden")
		for button in hud.train_buttons:
			if button.visible:
				check(button.icon != null, kind + ": command has a native icon")
				check(hud.current_layout["command"].encloses(button.get_rect()), kind + ": commands fit their panel")
		if kind == "villager": check(hud.status_panel.owner_label.text.contains("Пища: 10"), "worker cargo shown")
		if kind == "priest": check(hud.status_panel.owner_label.text.begins_with("Вера:"), "priest faith shown")
		if kind == "trade_boat":
			check(model["commands"].filter(func(command): return command.get("type") == "trade_resource").size() == 3, "trade ship resource choices retained")
			var pressed_resources := 0
			for index in range(hud.active_train_commands.size()):
				var command: Dictionary = hud.active_train_commands[index]
				if command.get("type") == "trade_resource":
					check(hud.train_buttons[index].text.is_empty(), "trade command uses compact icon presentation")
					if hud.train_buttons[index].button_pressed:
						pressed_resources += 1
						check(int(command["resource_type_id"]) == 1, "source default wood choice is highlighted")
			check(pressed_resources == 1, "exactly one trade choice is active")
		if kind in ["stone_thrower", "catapult_trireme"]: check(model["commands"].any(func(command): return command.get("id") == "attack_ground"), kind + ": attack ground retained")
		print("Checked unit HUD: %s / %s" % [kind, hud.status_panel.name_label.text])
	viewport.free()
	for failure in failures: push_error(failure)
	print("Unit HUD matrix: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, description: String) -> void:
	if not value: failures.append(description)