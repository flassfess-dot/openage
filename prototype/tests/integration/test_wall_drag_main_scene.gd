extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var worker_id := -1
	for unit_value in game.units:
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == game.PLAYER_TEAM and game.simulation_world.entity_is_worker(unit):
			worker_id = int(unit["id"])
			break
	if worker_id < 0:
		failures.append("fixture has no worker")
	else:
		var selected_worker_ids: Array[int] = [worker_id]
		game.player_control_state.replace_or_add(selected_worker_ids, false)
		game.simulation_world.grant_technology(game.PLAYER_TEAM, 101)
		game.simulation_world.grant_technology(game.PLAYER_TEAM, 11)
		for resource_id in range(4):
			game.simulation_world.set_resource_amount(game.PLAYER_TEAM, resource_id, 10000)
		var start := Vector2(-1, -1)
		var visible_count := 0
		var legal_count := 0
		for y in range(2, game.map_size.y - 2):
			for x in range(2, game.map_size.x - 4):
				var candidate := Vector2(x, y)
				var screen: Vector2 = game.world_to_screen(candidate)
				visible_count += 1
				if game.simulation_world.can_place_foundation(game.PLAYER_TEAM, "wall", candidate):
					legal_count += 1
				if game.simulation_world.can_place_foundation(game.PLAYER_TEAM, "wall", candidate) and game.simulation_world.can_place_foundation(game.PLAYER_TEAM, "wall", candidate + Vector2(1, 0)) and game.simulation_world.can_place_foundation(game.PLAYER_TEAM, "wall", candidate + Vector2(2, 0)):
					start = candidate
					break
			if start.x >= 0:
				break
		if start.x < 0:
			failures.append("fixture has no three-cell wall line: visible=%d legal=%d wall_available=%s sample_reason=%s" % [visible_count, legal_count, str(game.simulation_world.is_object_available(game.PLAYER_TEAM, 72)), str(game.simulation_world.last_build_failure)])
		else:
			game.begin_build_placement("wall")
			var before: int = game.game_controller.command_queue.size()
			game.handle_input_action({"type": "selection_committed", "from": game.world_to_screen(start), "to": game.world_to_screen(start + Vector2(2, 0)), "queue_order": false})
			var added: int = game.game_controller.command_queue.size() - before
			if added != 5:
				failures.append("three-cell drag must enqueue three foundations and two builder follow-ups, got %d" % added)
			if not game.pending_build_kind.is_empty():
				failures.append("unshifted wall drag exits placement mode")
	game.free()
	if failures.is_empty():
		print("Wall drag main scene tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
