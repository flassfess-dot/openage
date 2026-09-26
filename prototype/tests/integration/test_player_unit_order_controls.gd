extends SceneTree

const Commands := preload("res://scripts/commands.gd")

const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var soldiers: Array = game.simulation_world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "clubman")
	var soldier_ids: Array[int] = []
	for soldier in soldiers:
		soldier_ids.append(int(soldier.get("id", -1)))
	game.player_control_state.replace_or_add(soldier_ids, false)
	game.sync_world_state()

	game.issue_unit_action("attack_move")
	assert_equal(game.pending_target_command, "attack_move", "HUD attack-move enters explicit target mode")
	var destination := Vector2(8.0, 22.0)
	var screen_destination: Vector2 = game.world_to_screen(destination)
	game.handle_input_action({"type": "selection_committed", "from": screen_destination, "to": screen_destination})
	assert_equal(game.pending_target_command, "", "target click consumes attack-move mode without changing selection")
	var attack_move_record: Dictionary = game.game_controller.replay_recorder.command_records[-1]
	assert_equal(String(attack_move_record.get("type", "")), "attack_move", "target mode emits the public replayable AttackMoveCommand")
	advance_tick(game)
	assert_true(bool(game.game_controller.get_command_result(int(attack_move_record.get("sequence_id", -1))).get("accepted", false)), "attack-move crosses the authoritative controller boundary")

	var formation = Commands.FormationMoveCommand.new(game.game_controller.tick_index + 1, soldier_ids, Vector2(14.0, 20.0), "LINE", Vector2.RIGHT)
	game.game_controller.enqueue_command(formation, true, 1)
	advance_tick(game)
	assert_true(not game.game_controller.formation_groups.is_empty(), "fixture enters a live formation before hold")
	game.hud_controls.unit_action_requested.emit("hold")
	advance_tick(game)
	for soldier_id in soldier_ids:
		var soldier: Dictionary = game.simulation_world.find_unit(soldier_id)
		assert_equal(String(soldier.get("task", "")), "idle", "hold stops formation member %d" % soldier_id)
		assert_equal(String(soldier.get("stance", "")), "stand_ground", "hold applies stand-ground stance to member %d" % soldier_id)
		assert_equal(int(soldier.get("formation_group_id", -2)), -1, "hold detaches member %d from the obsolete route" % soldier_id)
	assert_true(game.game_controller.formation_groups.is_empty(), "hold disbands the obsolete formation route")

	game.hud_controls.unit_action_requested.emit("stance")
	advance_tick(game)
	for soldier_id in soldier_ids:
		assert_equal(String(game.simulation_world.find_unit(soldier_id).get("stance", "")), "passive", "stance button advances stand-ground to passive")

	var move = Commands.MoveCommand.new(game.game_controller.tick_index + 1, soldier_ids, Vector2(12.0, 22.0))
	game.game_controller.enqueue_command(move, true, 1)
	advance_tick(game)
	game.hud_controls.unit_action_requested.emit("stop")
	advance_tick(game)
	for soldier_id in soldier_ids:
		var soldier: Dictionary = game.simulation_world.find_unit(soldier_id)
		assert_equal(String(soldier.get("task", "")), "idle", "stop cancels member %d movement" % soldier_id)
		assert_equal(String(soldier.get("stance", "")), "passive", "stop preserves member %d stance" % soldier_id)
	var barracks: Dictionary = game.simulation_world.get_buildings().filter(func(building): return int(building.get("team", 0)) == 1 and String(building.get("kind", "")) == "barracks")[0]
	for _order in range(3):
		assert_true(game.simulation_world.enqueue_unit_production(int(barracks["id"]), 1, "clubman") != null, "selected producer fixture queues three same-line units")
	var food_before_stop: int = game.simulation_world.get_resource_amount(1, 0)
	var barracks_ids: Array[int] = [int(barracks["id"])]
	game.player_control_state.replace_or_add(barracks_ids, false)
	game.sync_world_state()
	assert_true(game.hud_model.get("commands", []).any(func(action): return String(action.get("type", "")) == "unit_action" and String(action.get("id", "")) == "stop"), "selected producer exposes a Stop action")
	game.hud_controls.unit_action_requested.emit("stop")
	var building_stop_record: Dictionary = game.game_controller.replay_recorder.command_records[-1]
	assert_equal(String(building_stop_record.get("type", "")), "stop", "building HUD action records a replayable Stop command")
	advance_tick(game)
	assert_equal(barracks.get("production_queue", []).size(), 1, "building Stop preserves active production and clears waiting orders")
	assert_equal(game.simulation_world.get_resource_amount(1, 0), food_before_stop + 100, "building Stop refunds two waiting Clubmen")

	game.free()
	if failures.is_empty():
		print("E3 player unit order controls integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func advance_tick(game) -> void:
	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)
	game.sync_world_state()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
