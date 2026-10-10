extends SceneTree
const Ready := preload("res://tests/support/match_ready.gd")
const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"
var failures: Array[String] = []

func create_game() -> Node:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	if not await Ready.wait_for_ready(self, game):
		failures.append("fixture navigation loading did not finish")
	game.set_process(false)
	game.sync_world_state()
	return game

func advance_tick(game) -> void:
	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, 1, 2)
	game.sync_world_state()
	game.process_presentation_events()

func _initialize() -> void:
	var game = await create_game()
	if not failures.is_empty():
		game.free()
		finish("Live gameplay fixture")
		return
	var producer: Dictionary = {}
	var technology := -1
	for building in game.simulation_world.get_buildings():
		if int(building.get("team", 0)) != 1: continue
		for option in game.simulation_world.get_research_options(int(building["id"]), 1):
			if bool(option.get("accepted", false)):
				producer = building
				technology = int(option["technology_id"])
				break
		if technology >= 0: break
	check(technology >= 0, "fixture provides an enabled research")
	if technology >= 0:
		var producer_ids: Array[int] = [int(producer["id"])]
		game.player_control_state.replace_or_add(producer_ids, false)
		game.sync_world_state()
		game.command_marker_presentation.reset()
		game.resource_feedback_time = 0.0
		game.hud_controls.research_requested.emit(technology, int(producer["id"]))
		var record: Dictionary = game.game_controller.replay_recorder.command_records[-1]
		check(record["type"] == "research", "HUD emits an ordinary research command")
		check(game.command_feedback_router.pending[int(record["sequence_id"])]["marker"] == null, "research gesture registers no world marker")
		advance_tick(game)
		check(bool(game.game_controller.get_command_result(int(record["sequence_id"])).get("accepted", false)), "research is accepted authoritatively")
		check(producer["production_queue"].any(func(order): return int(order.get("technology_id", -1)) == technology), "research enters the producer queue")
		check(game.command_marker_presentation.snapshot().is_empty(), "accepted research does not show red arrows")
		check(game.resource_feedback_time == 0.0, "research does not flash a target selection")
		# Guard the presentation boundary too, even if another UI caller supplies a marker.
		game.command_marker_presentation.reset()
		game.cancel_production_from_hud(int(producer["id"]), 0)
		var cancel: Dictionary = game.game_controller.replay_recorder.command_records[-1]
		game.command_feedback_router.pending[int(cancel["sequence_id"])]["marker"] = producer["pos"]
		advance_tick(game)
		check(bool(game.game_controller.get_command_result(int(cancel["sequence_id"])).get("accepted", false)), "cancelled research uses the public command boundary")
		check(game.command_marker_presentation.snapshot().is_empty(), "quiet queue commands suppress accidental positional markers")
	game.free()
	finish("Live gameplay production feedback")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
