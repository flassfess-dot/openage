extends SceneTree
const Ready := preload("res://tests/support/match_ready.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Commands := preload("res://scripts/commands.gd")
const SAVE := "res://qa/simulation-owner-roundtrip.json"
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(self,game): quit(1); return
	game.set_process(false)
	game.simulation_owner_enabled = true
	game._refresh_render_terrain()
	game.game_controller.set_paused(false)
	var initial: int = game.game_controller.tick_index
	var worker_id := int(game.selected_units()[0]["id"])
	game._queue_local_command(Commands.MoveCommand.new(initial+1,[worker_id],Vector2(17,17)))
	for index in range(20):
		game._process(0.05)
		check(game.simulation_owner.pending,"scene hands exclusive ownership to its worker")
		var held_units: Array = game.presentation_snapshot["units"].duplicate(true)
		var held_fog: Variant = game.presentation_snapshot["fog"]["cells"].duplicate()
		var metadata: Dictionary = game.simulation_frame_state()
		metadata["tick"] = -123
		check(int(game.simulation_frame_state()["tick"]) != -123,"published metadata cannot mutate the owner's retained state")
		var old_offset: Vector2 = game.view_offset
		game.handle_input_action({"type":"pointer_moved","position":Vector2(200,200),"pan_delta":Vector2(4,2)})
		check(game.simulation_owner.pending,"pointer hover and camera panning do not join the simulation owner")
		game._process_owner_presentation(0.005)
		check(game.view_offset != old_offset,"camera and detached presentation remain available during a job")
		if index == 4:
			var state: Dictionary = game.simulation_frame_state()
			game._queue_local_command(Commands.MoveCommand.new(int(state["tick"])+8,[],Vector2(8,8)))
			check(not game.simulation_owner.pending,"command entry joins the live owner before changing its queue")
		else:
			game.join_simulation_owner()
		check(game.presentation_snapshot["units"] == held_units and game.presentation_snapshot["fog"]["cells"] == held_fog,"live movement and fog changes cannot mutate the displayed publication")
	check(game.game_controller.tick_index > initial,"worker-backed frame loop advances real fixed ticks")
	game._process(0.05)
	check(game.save_game_to_path(SAVE,"Owner roundtrip"),"save joins a pending job and writes a complete checkpoint")
	check(not game.simulation_owner.pending,"save returns exclusive ownership")
	var verifier := Replay.new()
	var tick: int = game.game_controller.tick_index
	var expected := verifier.world_state_hash(game.simulation_world,tick,game.game_controller)
	game._process(0.1)
	check(game.load_game_from_path(SAVE),"load replaces a world while a previous owner job is pending")
	game.set_process(false)
	game.join_simulation_owner()
	check(game.game_controller.tick_index == tick and verifier.world_state_hash(game.simulation_world,tick,game.game_controller) == expected,"load restores the saved authoritative hash")
	game.set_process(true)
	if not await Ready.wait_for_ready(self,game): check(false,"restored navigation becomes ready")
	game.set_process(false)
	game.game_controller.set_paused(false)
	game._process(0.05)
	var owner = game.simulation_owner
	game.free()
	check(not owner.thread.is_started() and not owner.pending,"scene exit joins the outstanding job before derived world shutdown")
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	for failure in failures: push_error(failure)
	print("Simulation owner scene: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
