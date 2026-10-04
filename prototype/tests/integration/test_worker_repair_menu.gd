extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Main := preload("res://main.gd")
const Hud := preload("res://scripts/hud_controls.gd")
const ViewModel := preload("res://scripts/hud_view_model.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
var failures: Array[String] = []


func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	var world = World.new(Vector2i(32, 32))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain: Array[int] = []
	for y in range(32):
		for x in range(32):
			terrain.append(1 if x <= 6 else 2 if x == 7 else 0)
	var levels: Array[int] = []
	levels.resize(33 * 33)
	levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain, "vertex_levels": levels})
	var ship: Dictionary = world.add_unit(1, "transport", Vector2(6.5, 10.5), false)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(16.5, 10.5), false)
	var soldier: Dictionary = world.add_unit(1, "clubman", Vector2(17.5, 12.5), false)
	var house: Dictionary = world.add_building(800, "house", Vector2(22.5, 22.5), 1)
	ship["hp"] = float(ship["max_hp"]) - 20.0
	house["hp"] = float(house["max_hp"]) - 20.0
	world.update_fog_of_war()
	var game = Main.new()
	game.resource_catalog = catalog
	game.render_world = Main.RenderWorld.new()
	game.simulation_world = world
	game.game_controller = Controller.new(world)
	game.local_player_team = 1
	game.map_size = world.map_size
	game.presentation_snapshot = Snapshot.presentation(world, 0, 1)
	game.units = game.presentation_snapshot["units"]
	var ids: Array[int] = [int(worker["id"]), int(soldier["id"])]
	game.player_control_state.replace_or_add(ids, false)
	var model = ViewModel.new()
	model.configure(catalog.runtime_catalog_data, catalog.localization, catalog.object_catalog_data)
	var hud = Hud.new()
	game.hud_controls = hud
	hud.size = Vector2(1280, 720)
	hud.configure_icons(catalog.interface_icons)
	hud.unit_action_requested.connect(game.issue_unit_action)
	hud.build_menu_opened.connect(game.cancel_pending_targeting)
	hud.set_view_model(model.build(game.presentation_snapshot, ids, "RECTANGLE"))

	var repair_index := command_index(hud, "repair")
	check(repair_index >= 0, "mixed group has a separate Repair button")
	if repair_index >= 0:
		hud.train_buttons[repair_index].emit_signal("pressed")
	check(game.pending_target_command == "repair", "Repair button enters explicit targeting")
	check(not hud.build_menu_open and hud.available_formation_buttons.size() == 5, "Repair stays with actions and formations")
	game.handle_input_action({"type": "selection_committed", "from": Vector2(-1000, -1000), "to": Vector2(-1000, -1000)})
	check(game.pending_target_command == "repair" and game.game_controller.command_queue.is_empty(), "invalid left click keeps Repair targeting without an order")
	game.handle_input_action({"type": "context_committed", "position": game.world_to_screen(ship["pos"])})
	check(game.pending_target_command.is_empty() and game.game_controller.command_queue.is_empty(), "right click cancels Repair without boarding or issuing a context order")

	game.issue_unit_action("repair")
	hud.set_build_menu_open(true)
	check(game.pending_target_command.is_empty() and hud.build_menu_open, "Build opens its layer and cancels Repair targeting")
	game.issue_unit_action("repair")
	check(not hud.build_menu_open and game.pending_target_command == "repair", "Repair restores actions if entered from the construction layer")
	var ship_point: Vector2 = game.world_to_screen(ship["pos"])
	check(game.pick_stack_at(ship_point).any(func(hit): return int(hit.get("id", -1)) == int(ship["id"])), "damaged Transport is picked through its actual rendered footprint")
	game.handle_input_action({"type": "selection_committed", "from": ship_point, "to": ship_point})
	check(game.pending_target_command.is_empty(), "valid repair target consumes targeting")
	var queue: Array = game.game_controller.command_queue
	check(queue.size() == 1 and queue[0].command_type() == "repair", "left click on damaged Transport submits Repair instead of Board")
	if queue.size() == 1:
		check(queue[0].unit_ids == [int(worker["id"])], "mixed selection sends Repair only to villagers")
		check(queue[0].target_building_id == int(ship["id"]), "Repair retains the selected ship target")
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(worker["task"] == "repair" and soldier["task"] == "idle", "simulation accepts ship repair and leaves escort orders unchanged")
	check(world.get_embarked_units().is_empty(), "explicit Repair never embarks the worker")

	game.issue_unit_action("repair")
	var house_point: Vector2 = game.world_to_screen(house["pos"])
	game.handle_input_action({"type": "selection_committed", "from": house_point, "to": house_point})
	queue = game.game_controller.command_queue
	check(queue.size() == 1 and queue[0].command_type() == "repair" and queue[0].target_building_id == int(house["id"]), "same Repair button targets damaged buildings")
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	check(worker["task"] == "repair" and int(worker["target_building_id"]) == int(house["id"]), "building repair reaches the authoritative order system")
	game.issue_unit_action("repair")
	check(game.cancel_pending_targeting() and game.pending_target_command.is_empty(), "shared Escape cancellation clears Repair targeting")
	hud.free()
	game.free()
	for failure in failures:
		push_error(failure)
	print("Worker Repair menu and transport targeting: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)


func command_index(hud, id: String) -> int:
	for index in range(hud.active_train_commands.size()):
		if hud.active_train_commands[index].get("id") == id:
			return index
	return -1


func check(condition: bool, context: String) -> void:
	if not condition:
		failures.append(context)
