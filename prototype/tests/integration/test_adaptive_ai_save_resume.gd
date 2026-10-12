extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Replay := preload("res://scripts/replay_system.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")
const SAVE_PATH := "res://qa/adaptive-feedback-save-regression.json"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var settings := Settings.default_settings()
	settings["map_size_id"] = "compact"
	var built := Settings.build(settings)
	check(bool(built.get("valid", false)), "generated adaptive match is valid")
	if not bool(built.get("valid", false)):
		quit(1)
		return
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = String(built["identity"])
	game.match_definition_override = built["definition"].duplicate(true)
	game.map_definition_override = built["map_data"].duplicate(true)
	game.set_process(false)
	root.add_child(game)
	await process_frame
	game.ai_runtime.shutdown()
	game.task_coordinator.enabled = false
	game.game_controller.set_paused(false)
	game.game_controller.set_speed_multiplier(1.0)
	var ai = game.ai_players.filter(func(p): return p.enabled)[0]
	check(bool(ai.economic_policy.get("adaptive_strategy", false)), "fixture runs the new skirmish brain")
	var reached := false
	for frame in range(600):
		game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)
		if not game.ai_decision_queue.active and ai.strategy.pending.any(func(entry): return bool(game.game_controller.get_command_result(int(entry["sequence"])).get("accepted", false))):
			reached = true
			break
		await process_frame
	check(reached, "ordinary AI proposals execute before the next feedback drain")
	if not reached:
		await finish(game)
		return
	for record in game.game_controller.replay_recorder.command_records:
		check(not Replay.new().decode_variant(record["params"]).has("_ai_feedback"), "planner metadata stays out of replayed commands")
	var saved_tick: int = game.game_controller.tick_index
	var saved_ai: Dictionary = ai.canonical_state()
	check(game.save_game_to_path(SAVE_PATH, "Adaptive feedback regression"), "completed unconsumed AI results are saved")
	ai.collect_feedback(game.game_controller, saved_tick)
	var feedback_state: Dictionary = ai.canonical_state()
	check(ai.strategy.metrics["commands_accepted"] > 0 and not ai.strategy.spent.is_empty(), "accepted producer and construction costs feed back into income estimates")
	var target := saved_tick + 45
	check(await MatchReady.advance_to_tick(self, game.game_controller, target, game.PLAYER_TEAM, game.ENEMY_TEAM), "continuous adaptive simulation reaches the comparison tick")
	var codec := Replay.new()
	var expected_hash := codec.world_state_hash(game.simulation_world, target, game.game_controller)
	var expected_ai: Array = game.ai_players.map(func(p): return p.canonical_state())
	var expected_commands: Variant = JSON.parse_string(JSON.stringify(game.game_controller.replay_recorder.command_records))
	check(game.load_game_from_path(SAVE_PATH), "adaptive checkpoint reloads through the normal game save boundary")
	if game.game_controller.tick_index != saved_tick:
		check(false, "saved source tick is restored")
		await finish(game)
		return
	ai = game.ai_players.filter(func(p): return p.enabled)[0]
	check(ai.canonical_state() == saved_ai, "nested AI state restores with exact numeric types before feedback")
	ai.collect_feedback(game.game_controller, saved_tick)
	check(ai.canonical_state() == feedback_state, "saved own results produce exactly the same feedback once")
	check(await MatchReady.advance_to_tick(self, game.game_controller, target, game.PLAYER_TEAM, game.ENEMY_TEAM), "resumed adaptive simulation reaches the same comparison tick")
	check(codec.world_state_hash(game.simulation_world, target, game.game_controller) == expected_hash, "adaptive save/resume preserves the authoritative simulation hash")
	check(game.ai_players.map(func(p): return p.canonical_state()) == expected_ai, "adaptive save/resume preserves strategy, income and pending proposals")
	check(JSON.parse_string(JSON.stringify(game.game_controller.replay_recorder.command_records)) == expected_commands, "adaptive save/resume preserves public command order and ticks")
	await finish(game)

func finish(game) -> void:
	if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("Adaptive save and feedback: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
