extends SceneTree

const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 752)
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	viewport.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var resource: Dictionary = game.simulation_world.add_resource("tree", Vector2(21.5, 10.5), 75)
	game.center_view_on_world(Vector2(resource["pos"]))
	game.sync_world_state()
	var screen: Vector2 = game.world_to_screen(Vector2(resource["pos"]))
	game.finish_selection(screen, screen)
	game.sync_world_state()
	var leader: Dictionary = game.hud_model.get("selection", {}).get("leader", {})
	var valid := int(leader.get("id", -1)) == int(resource["id"])
	valid = valid and int(leader.get("resource_amount", -1)) == 75
	valid = valid and String(game.hud_model.get("selection", {}).get("category", "")) == "resource"
	valid = valid and game.hud_model.get("commands", []).is_empty()
	var worker: Dictionary = game.simulation_world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "villager")[0]
	var worker_ids: Array[int] = [int(worker["id"])]
	game.player_control_state.replace_or_add(worker_ids, false)
	right_click(game, screen)
	game.game_controller.advance_frame(0.05, 1, 2)
	game.process_presentation_events()
	valid = valid and game.resource_feedback_id == int(resource["id"]) and game.resource_feedback_time > 0.0
	valid = valid and game.command_marker_presentation.snapshot().is_empty()
	# Berry bushes report zero source HP, but their remaining food must make
	# them pickable both for inspection and a worker's right-click order.
	var berries: Dictionary = game.simulation_world.add_resource("berries", Vector2(14.5, 21.5), 150)
	game.center_view_on_world(Vector2(berries["pos"]))
	game.sync_world_state()
	var berry_screen: Vector2 = game.world_to_screen(Vector2(berries["pos"]))
	var berry_hits: Array = game.pick_stack_at(berry_screen).map(func(hit): return {"kind": hit.get("kind"), "id": hit.get("id"), "type": hit.get("entity_type")})
	game.finish_selection(berry_screen, berry_screen)
	var berry_leader: Dictionary = game.hud_model.get("selection", {}).get("leader", {})
	valid = valid and int(berry_leader.get("id", -1)) == int(berries["id"])
	valid = valid and not bool(berry_leader.get("show_hp", true)) and int(berry_leader.get("resource_amount", -1)) == 150
	game.player_control_state.replace_or_add(worker_ids, false)
	game.issue_order(berry_screen)
	game.game_controller.advance_frame(0.05, 1, 2)
	valid = valid and int(worker.get("resource_id", -1)) == int(berries["id"]) and String(worker.get("task", "")) == "gather"
	var barracks: Dictionary = game.simulation_world.get_buildings().filter(func(building): return int(building.get("team", 0)) == 1 and String(building.get("kind", "")) == "barracks")[0]
	game.train_unit_from_hud("clubman", int(barracks["id"]))
	game.game_controller.advance_frame(0.05, 1, 2)
	game.process_presentation_events()
	valid = valid and game.command_marker_presentation.snapshot().is_empty()
	viewport.free()
	valid = (await verify_mineral_pointer_flow("gold_mine")) and valid
	valid = (await verify_mineral_pointer_flow("stone_mine")) and valid
	if not valid:
		print("Berry input diagnostics: berry_id=%d berry_hp=%.1f screen=%s leader=%s hits=%s worker=%s" % [int(berries["id"]), float(berries["hp"]), berry_screen, berry_leader, berry_hits, {"task": worker.get("task"), "resource_id": worker.get("resource_id")}])
		push_error("Resource inspection, green gather feedback and marker-free training must stay separate")
		quit(1)
		return
	print("Resource inspection selection passed")
	quit(0)


func right_click(game: Node, screen: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = screen
	game._unhandled_input(press)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	release.position = screen
	game._unhandled_input(release)


func verify_mineral_pointer_flow(kind: String) -> bool:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 752)
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	viewport.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var resource: Dictionary = game.simulation_world.add_resource(kind, Vector2(21.5, 10.5), 75)
	game.center_view_on_world(Vector2(resource["pos"]))
	game.sync_world_state()
	var screen: Vector2 = game.world_to_screen(Vector2(resource["pos"]))
	var hits: Array = game.pick_stack_at(screen)
	var worker: Dictionary = game.simulation_world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "villager")[0]
	var worker_ids: Array[int] = [int(worker["id"])]
	game.player_control_state.replace_or_add(worker_ids, false)
	right_click(game, screen)
	game.game_controller.advance_frame(0.05, 1, 2)
	var valid := not hits.is_empty() and int(hits[0].get("id", -1)) == int(resource["id"])
	valid = valid and String(worker.get("task", "")) == "gather" and int(worker.get("resource_id", -1)) == int(resource["id"])
	if not valid:
		print("Mineral pointer diagnostics: kind=%s screen=%s hits=%s worker=%s" % [kind, screen, hits.map(func(hit): return {"kind": hit.get("kind"), "id": hit.get("id"), "type": hit.get("entity_type")}), {"task": worker.get("task"), "resource_id": worker.get("resource_id")}])
	viewport.free()
	return valid
