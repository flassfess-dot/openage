extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")

const TEST_PATH := "res://qa/e3-game-save-load-test.json"
const NAMED_DIRECTORY := "res://qa/e3-game-save-named-tests"

var failures: Array[String] = []


func _initialize() -> void:
	cleanup()
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.game_controller.set_speed_multiplier(1.0)
	var selected: Array[int] = game.player_control_state.selected_ids()
	assert_true(not selected.is_empty(), "fixture exposes a selected controllable unit")
	if selected.is_empty():
		finish(game)
		return
	var unit: Dictionary = game.simulation_world.find_unit(selected[0])
	var target := Vector2(unit.get("pos", Vector2.ZERO)) + Vector2(1.0, 0.0)
	var command = Commands.MoveCommand.new(game.game_controller.tick_index + 1, [selected[0]], target)
	game.game_controller.enqueue_command(command, true, game.PLAYER_TEAM)
	for _step in range(8):
		game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)
	game.sync_world_state()
	game.view_offset = Vector2(321, 222)
	game.view_zoom = 1.12
	game.control_groups.assign(4, selected)
	var saved_tick: int = int(game.game_controller.tick_index)
	var pending_stop = Commands.StopCommand.new(saved_tick + 3, [selected[0]])
	game.game_controller.enqueue_command(pending_stop, true, game.PLAYER_TEAM)
	var verifier := ReplaySystem.new()
	var saved_hash := verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller)
	var saved_command_count: int = int(game.game_controller.replay_recorder.command_records.size())
	game.sound_cue_history.consume_distress([{"sequence": 7, "target_team": game.PLAYER_TEAM, "target_id": selected[0], "position": Vector2(9, 8)}], game.PLAYER_TEAM, saved_tick)
	var saved_cues: Dictionary = game.sound_cue_history.canonical_state()
	assert_true(game.save_game_to_path(TEST_PATH), "live match writes a versioned replay-backed save")
	var named_path: String = GameSaveArchive.named_path("Экспедиция", NAMED_DIRECTORY)
	assert_true(game.save_game_to_path(named_path, "Экспедиция"), "live match writes an independent named save")
	assert_equal(GameSaveArchive.read(named_path).get("archive", {}).get("metadata", {}).get("slot_name", ""), "Экспедиция", "named archive retains its display metadata")

	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)
	game.view_offset = Vector2.ZERO
	game.player_control_state.clear()
	game.control_groups.clear()
	assert_true(game.load_game_from_path(TEST_PATH), "save reconstructs and atomically replaces the live match")
	assert_equal(game.game_controller.tick_index, saved_tick, "load restores the exact fixed tick")
	assert_equal(verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller), saved_hash, "load verifies and restores the exact authoritative state hash")
	assert_equal(game.view_offset, Vector2(321, 222), "load restores camera position")
	assert_equal(game.view_zoom, 1.12, "load restores camera zoom")
	assert_equal(game.player_control_state.selected_ids(), selected, "load restores valid selection IDs")
	assert_equal(game.control_groups.groups.get(4, []), selected, "load restores control groups")
	assert_equal(game.sound_cue_history.canonical_state(), saved_cues, "load restores fog-safe sound cue history and Home cursor")
	assert_equal(game.game_controller.replay_recorder.command_records.size(), saved_command_count, "loaded recorder retains command history")
	assert_equal(game.game_controller.command_queue.size(), 1, "load retains commands scheduled after the saved tick")
	assert_equal(game.game_controller.command_queue[0].tick, saved_tick + 3, "future command retains its authoritative tick")
	var follow_up = Commands.StopCommand.new(saved_tick + 1, [selected[0]])
	game.game_controller.enqueue_command(follow_up, true, game.PLAYER_TEAM)
	assert_equal(game.game_controller.replay_recorder.command_records.size(), saved_command_count + 1, "recording continues after load")
	game.sound_cue_history.reset()
	assert_true(game.load_game_from_path(named_path), "named save independently restores the same authoritative tick")
	assert_equal(game.sound_cue_history.canonical_state(), saved_cues, "named save restores presentation memory without replaying stale cues")

	var live_hash_before_rejected_load := verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller)
	var raw_archive: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))
	var codec := ReplaySystem.new()
	var bad_view: Dictionary = codec.decode_variant(raw_archive.get("view_state", {}))
	bad_view["sound_cue_history"]["cues"][0]["tick"] = saved_tick + 100
	raw_archive["view_state"] = codec.encode_variant(bad_view)
	assert_equal(GameSaveArchive.write(TEST_PATH, raw_archive), OK, "structurally valid invalid cue fixture reaches view-state validation")
	assert_true(not game.load_game_from_path(TEST_PATH), "future-dated sound cue history is rejected")
	assert_equal(game.last_save_error, "sound_cue_history_invalid", "invalid cue state has an explicit load reason")
	assert_equal(verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller), live_hash_before_rejected_load, "rejected cue history leaves the live match untouched")
	assert_true(game.save_game_to_path(TEST_PATH), "valid quick save can replace rejected cue fixture")
	var archive_result: Dictionary = GameSaveArchive.read(TEST_PATH)
	var corrupt_archive: Dictionary = archive_result.get("archive", {})
	corrupt_archive["state_sha256"] = "0".repeat(64)
	assert_equal(GameSaveArchive.write(TEST_PATH, corrupt_archive), OK, "structurally valid corrupt fixture reaches authoritative verification")
	assert_true(not game.load_game_from_path(TEST_PATH), "incorrect authoritative hash rejects the archive")
	assert_equal(verifier.world_state_hash(game.simulation_world, saved_tick, game.game_controller), live_hash_before_rejected_load, "rejected load leaves the live match untouched")
	finish(game)


func finish(game) -> void:
	cleanup()
	game.free()
	if failures.is_empty():
		print("E3 game save/load pipeline tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func cleanup() -> void:
	for suffix in ["", ".tmp", ".bak"]:
		var path := ProjectSettings.globalize_path(TEST_PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var named_path: String = GameSaveArchive.named_path("Экспедиция", NAMED_DIRECTORY)
	for suffix in ["", ".tmp", ".bak"]:
		var absolute_named: String = ProjectSettings.globalize_path(named_path + suffix)
		if FileAccess.file_exists(absolute_named):
			DirAccess.remove_absolute(absolute_named)
	var absolute_directory: String = ProjectSettings.globalize_path(NAMED_DIRECTORY)
	if DirAccess.dir_exists_absolute(absolute_directory):
		DirAccess.remove_absolute(absolute_directory)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
