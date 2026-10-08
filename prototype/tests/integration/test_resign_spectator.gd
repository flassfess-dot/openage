extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["players"][2]["enabled"] = true
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "three-player spectator fixture builds")
	if not bool(built.get("valid", false)):
		finish()
		return
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_definition_override = built["definition"]
	game.map_definition_override = built["map_data"]
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var resign = Commands.ResignCommand.new(game.game_controller.tick_index + 1)
	game.game_controller.enqueue_command(resign, true, 1)
	if not await advance_until_tick(game, int(resign.tick)):
		game.free()
		finish()
		return
	assert_true(bool(game.game_controller.get_command_result(resign.sequence_id).get("accepted", false)), "resign passes the authoritative command result boundary")
	game.sync_world_state()
	assert_equal(game.simulation_world.player_registry.status(1), "resigned", "local player is resigned through the authoritative command")
	assert_equal(game.battle_over, false, "other active players keep the match running")
	assert_equal(game.local_spectator, true, "local presentation becomes a spectator")
	assert_equal(game.player_control_state.selected_ids().size(), 0, "spectator selection is cleared")
	assert_equal(game.hud_model.get("read_only"), true, "spectator command panel is read-only")
	assert_equal(game.hud_modal_overlay.resign_button.disabled, true, "resign cannot be submitted twice from the menu")
	var queued_before: int = game.game_controller.command_queue.size()
	game.handle_input_action({"type": "resign"})
	assert_equal(game.game_controller.command_queue.size(), queued_before, "spectator hotkey cannot submit gameplay commands")
	game.enqueue_with_feedback(Commands.MoveCommand.new(game.game_controller.tick_index + 1, [1], Vector2(7, 7)), "move", "")
	assert_equal(game.game_controller.command_queue.size(), queued_before, "spectator HUD boundary cannot submit gameplay commands")
	var camera_before: Vector2 = game.view_offset
	game.handle_input_action({"type": "pointer_moved", "pan_delta": Vector2(14, 6), "position": Vector2(100, 100)})
	assert_true(game.view_offset != camera_before, "spectator retains camera control")
	game.free()
	finish()


func advance_until_tick(game, expected_tick: int) -> bool:
	# A rendered frame may only prepare asynchronous AI and leave the resign
	# command queued. Wait for its authoritative tick before checking the HUD.
	game.game_controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	var deadline := Time.get_ticks_msec() + 30_000
	while int(game.game_controller.tick_index) < expected_tick:
		if Time.get_ticks_msec() >= deadline:
			assert_true(false, "deferred AI completes the resign tick within its deadline")
			return false
		await process_frame
		# The first attempt already contributed the fixed step's time debt.
		game.game_controller.advance_frame(0.0, 1, 2)
	return true


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P07 resign spectator passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
