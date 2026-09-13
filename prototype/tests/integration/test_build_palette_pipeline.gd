extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var worker: Dictionary = {}
	for unit_value in game.units:
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == game.PLAYER_TEAM and game.simulation_world.entity_is_worker(unit):
			worker = unit
			break
	assert_true(not worker.is_empty(), "main scene provides a controllable worker")
	if not worker.is_empty():
		var selected_worker_ids: Array[int] = [int(worker["id"])]
		game.player_control_state.replace_or_add(selected_worker_ids, false)
		game.refresh_hud_model()
		var build_index := command_index(game.hud_controls.active_train_commands, "build", "house")
		assert_true(build_index >= 0, "worker HUD exposes House through the age-filtered palette")
		if build_index >= 0:
			var button: Button = game.hud_controls.train_buttons[build_index]
			assert_true(button.icon != null and not button.disabled, "House action uses its imported source icon and is enabled")
			button.emit_signal("pressed")
			assert_equal(game.pending_build_kind, "house", "HUD click enters placement mode")

			var target := valid_build_position(game, "house")
			assert_true(target.x >= 0.0, "fixture has an explored valid House placement")
			if target.x >= 0.0:
				var before_ids: Dictionary = {}
				for building_value in game.simulation_world.get_buildings():
					before_ids[int(building_value.get("id", -1))] = true
				var screen: Vector2 = game.world_to_screen(target)
				game.handle_input_action({"type": "selection_committed", "from": screen, "to": screen, "mode": "single"})
				assert_equal(game.pending_build_kind, "", "world click consumes placement mode")
				game.update_units(0.2)
				var foundation: Dictionary = {}
				for building_value in game.simulation_world.get_buildings():
					var building: Dictionary = building_value
					if not before_ids.has(int(building.get("id", -1))) and String(building.get("kind", "")) == "house":
						foundation = building
						break
				assert_true(not foundation.is_empty(), "normal click route enqueues and places the House foundation")
				if not foundation.is_empty():
					assert_equal(String(foundation.get("state", "")), "foundation", "new building begins with the authoritative construction lifecycle")
	game.free()

	if failures.is_empty():
		print("I12-018 build palette pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func command_index(commands: Array, command_type: String, command_id: String) -> int:
	for index in range(commands.size()):
		var command: Dictionary = commands[index]
		if String(command.get("type", "")) == command_type and String(command.get("id", "")) == command_id:
			return index
	return -1


func valid_build_position(game, kind: String) -> Vector2:
	for y in range(2, game.map_size.y - 2):
		for x in range(2, game.map_size.x - 2):
			var position := Vector2(x, y)
			if game.simulation_world.can_place_foundation(game.PLAYER_TEAM, kind, position):
				return position
	return Vector2(-1.0, -1.0)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
