extends SceneTree

const GameController := preload("res://scripts/game_controller.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var first := timed_match()
	var first_world = first["world"]
	var first_controller = first["controller"]
	var recorder = first_controller.start_recording(77123, true)
	for _tick in range(8):
		first_controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_equal(first_world.get_victory_result().get("over"), false, "timed match remains unfinished before its deadline")
	var saved_tick: int = first_controller.tick_index
	var saved_elapsed := float(SimulationSnapshot.canonical(first_world, saved_tick)["world"]["victory"]["elapsed_seconds"])
	assert_true(saved_elapsed > 0.0 and saved_elapsed < 0.5, "canonical state retains the partial countdown")
	var hasher = ReplaySystem.new()
	var saved_hash := hasher.world_state_hash(first_world, saved_tick)
	var recording: Dictionary = recorder.to_dictionary()
	var archive := GameSaveArchive.create("res://tests/timed-match", {"victory_rules": [{"type": "score", "time_limit_seconds": 0.5}]}, saved_tick, saved_hash, recording, [], {}, {})
	var decoded := GameSaveArchive.decoded(archive)
	assert_true(bool(decoded.get("valid", false)), "unfinished timed match is a valid save archive")
	if not bool(decoded.get("valid", false)):
		finish()
		return

	var restored := timed_match()
	var restored_world = restored["world"]
	var restored_controller = restored["controller"]
	assert_true(restored_controller.load_replay(decoded["archive"]["replay"]), "saved unfinished timed match replay loads")
	assert_true(restored_controller.replay_until_tick(saved_tick, 1, 2), "replay restores the exact unfinished tick")
	assert_equal(hasher.world_state_hash(restored_world, saved_tick), saved_hash, "restored timed state has the canonical hash")
	for _tick in range(3):
		first_controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
		restored_controller.advance_frame(GameController.FIXED_STEP_SECONDS, 1, 2)
	assert_equal(first_world.get_victory_result().get("reason"), "score", "deadline completes through the score rule")
	assert_equal(first_world.get_victory_result().get("winner_team"), 1, "higher score wins at the deadline")
	assert_equal(restored_world.get_victory_result(), first_world.get_victory_result(), "replayed deadline has the same MatchOutcome")
	assert_equal(hasher.world_state_hash(restored_world, restored_controller.tick_index), hasher.world_state_hash(first_world, first_controller.tick_index), "replayed terminal state has the same canonical hash")
	finish()


func timed_match() -> Dictionary:
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.configure_players([
		{"team": 1, "controller": "human", "civilization_id": 13},
		{"team": 2, "controller": "ai", "civilization_id": 13},
	])
	world.reset_game(false)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.configure_victory_rules([{"type": "score", "time_limit_seconds": 0.5}], false)
	world.add_unit(1, "clubman", Vector2(3, 3), false)
	world.add_unit(2, "clubman", Vector2(12, 12), false)
	world.set_score(1, 20)
	world.set_score(2, 10)
	var controller = GameController.new(world)
	controller.set_speed_multiplier(1.0)
	return {"world": world, "controller": controller}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P07 timed victory replay passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
