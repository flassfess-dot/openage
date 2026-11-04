extends SceneTree
const Task := preload("res://scripts/ai_planning_task.gd")
const Queue := preload("res://scripts/ai_decision_queue.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Ready := preload("res://tests/support/match_ready.gd")
const Definition := preload("res://scripts/match_definition.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const SAVE_PATH := "res://qa/pending-ai-save-resume.json"
var failures: Array[String] = []
var details: Dictionary = {}
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	# The original default fixture uses the legacy policy. Supply a normal
	# competitive match definition, including the current runtime parameters.
	var definition: Dictionary = Definition.load_json()
	for player in definition["players"]:
		if String(player.get("controller","")) != "ai": continue
		var policy: Dictionary = Policy.resolve("random_map_balanced","standard")
		policy["algorithm_version"] = "competitive_v2"
		policy.merge(policy.get("competitive_parameters",{}),true)
		player["ai"] = policy
	game.match_definition_override = definition
	root.add_child(game)
	game.game_controller.set_paused(true)
	if not await Ready.wait_for_ready(self, game, 120000):
		check(false, "initial navigation completes before the pending-plan fixture")
		finish(game)
		return
	game.set_process(false)
	await process_frame
	game.ai_decision_queue.cancel(game.task_coordinator)
	game.task_coordinator.enabled = false
	game.game_controller.set_paused(false)
	game.game_controller.set_speed_multiplier(1.0)
	var enabled: Array = game.ai_players.filter(func(ai): return bool(ai.enabled))
	check(not enabled.is_empty(), "fixture contains an enabled AI")
	if enabled.is_empty():
		finish(game)
		return
	var ai = enabled[0]
	check(bool(ai.economic_policy.get("competitive",false)) and ai.competitive_controller != null, "pending fixture actually activates competitive_v2")
	var source: int = game.game_controller.tick_index
	var target := source + Queue.LOOKAHEAD_TICKS
	var options: Dictionary = ai.presentation_options()
	options["include_navigation"] = true
	options["defer_build_sites"] = true
	var snapshot: Dictionary = game.ai_observation_store.observe_with_queries(game.simulation_world, source, int(ai.team), options)
	game.ai_decision_queue.begin([ai], source, target, Callable(game, "_capture_ai_decision"))
	game.ai_decision_queue.records[0]["input"] = Data.seal(Task.capture(ai, snapshot, target))
	game.ai_decision_queue.poll(game.task_coordinator, source, Engine.get_process_frames())
	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, game.PLAYER_TEAM, game.ENEMY_TEAM)
	var saved_tick: int = game.game_controller.tick_index
	check(saved_tick == source + 1 and game.ai_decision_queue.active, "save boundary lies inside background planning")
	check(game.save_game_to_path(SAVE_PATH, "Pending AI regression"), "full checkpoint saves pending future plans")
	await advance_to(game, target)
	var verifier := Replay.new()
	var expected_hash := verifier.world_state_hash(game.simulation_world, target, game.game_controller)
	var expected_states: Array = game.ai_players.map(func(player): return player.canonical_state())
	var expected_commands: Array = game.game_controller.replay_recorder.command_records.duplicate(true)
	check(not expected_commands.is_empty(), "the pending plan applies a real public command")
	check(game.load_game_from_path(SAVE_PATH), "checkpoint restores a plan captured before its saved tick")
	game.game_controller.set_paused(true)
	game.set_process(true)
	if not await Ready.wait_for_ready(self, game, 120000):
		check(false, "restored navigation completes before resumed fixed ticks")
		finish(game)
		return
	game.set_process(false)
	check(game.game_controller.tick_index == saved_tick and game.ai_decision_queue.source_tick == source and game.ai_decision_queue.apply_tick == target, "loading preserves all three tick boundaries")
	game.game_controller.set_paused(false)
	await advance_to(game, target)
	check(verifier.world_state_hash(game.simulation_world, target, game.game_controller) == expected_hash, "resumed plan reproduces the authoritative state hash")
	check(game.ai_players.map(func(player): return player.canonical_state()) == expected_states, "resumed plan reproduces AI state")
	check(game.game_controller.replay_recorder.command_records == expected_commands, "resumed plan preserves command order and application ticks")
	details = {"competitive":bool(ai.economic_policy.get("competitive",false)), "source_tick":source, "saved_tick":saved_tick, "apply_tick":target,
		"recorded_commands":expected_commands.size(),
		"world_equal":verifier.world_state_hash(game.simulation_world, target, game.game_controller) == expected_hash,
		"ai_equal":game.ai_players.map(func(player): return player.canonical_state()) == expected_states,
		"commands_equal":game.game_controller.replay_recorder.command_records == expected_commands,
		"native":ClassDB.class_exists("RoRPathKernel") and ClassDB.class_exists("RoRReadModelKernel")}
	finish(game)

func advance_to(game, target: int) -> void:
	for _frame in range(400):
		if game.game_controller.tick_index >= target:
			return
		var delta: float = 0.0 if game.game_controller.accumulator_seconds + 0.000001 >= game.game_controller.FIXED_STEP_SECONDS else game.game_controller.FIXED_STEP_SECONDS
		game.game_controller.advance_frame(delta, game.PLAYER_TEAM, game.ENEMY_TEAM)
		await process_frame
	check(false, "future AI deadline resumes within the bounded fixture")

func finish(game) -> void:
	if not OS.get_cmdline_user_args().is_empty():
		var file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
		if file == null: push_error("Pending competitive proof is not writable"); quit(1); return
		file.store_string(JSON.stringify({"passed":failures.is_empty(),"checks":checks,"details":details,"failures":failures,"scope":"Competitive pending economic plan, real save/load, full legal navigation, fixed source/saved/apply ticks. Native editor component test, not actual Release EXE or full-game strength."},"\t")); file.close()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	game.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
