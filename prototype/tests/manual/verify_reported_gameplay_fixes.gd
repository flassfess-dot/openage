extends Node

const Ready := preload("res://tests/support/match_ready.gd")
var failures: Array[String] = []
var checks: Array = []
var root: Window:
	get: return get_tree().root
var current_scene: Node:
	get: return get_tree().current_scene

func quit(code: int) -> void:
	get_tree().quit(code)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var save := ""
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): save = arg.trim_prefix("--save=")
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if save.is_empty() or output.is_empty() or FileAccess.file_exists(output):
		push_error("Pass the source save and a new report path")
		quit(1)
		return
	var game = load("res://main.tscn").instantiate()
	game.autosave.enabled = false
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	if not await Ready.wait_for_ready(get_tree(), game, 120000): game.free(); quit(1); return
	if not game.load_game_from_path(save): push_error(game.last_save_error); game.free(); quit(1); return
	if not await Ready.wait_for_ready(get_tree(), game, 120000): game.free(); quit(1); return
	game.set_process(false)
	game.game_controller.set_paused(false)
	game._sync_music_playback()
	var loaded_tick: int = game.game_controller.tick_index
	check(not game.audio_player.stream_paused, "loaded running match plays music")
	game.handle_input_action({"type":"open_game_menu"})
	check(game.game_controller.paused and game.audio_player.stream_paused, "Esc/F10 menu pauses simulation and music")
	game._close_hud_modal()
	check(not game.audio_player.stream_paused, "leaving the menu restores music")
	game.handle_input_action({"type":"toggle_pause"})
	check(game.game_controller.paused and game.audio_player.stream_paused, "ordinary pause pauses music")
	game._toggle_game_menu()
	game._close_hud_modal()
	check(game.game_controller.paused and game.audio_player.stream_paused, "menu preserves an earlier pause")
	game.handle_input_action({"type":"toggle_pause"})
	game.handle_input_action({"type":"toggle_audio"})
	game._toggle_game_menu()
	game._close_hud_modal()
	check(game.audio_muted and game.audio_player.stream_paused, "menu preserves manual mute")
	game.handle_input_action({"type":"toggle_audio"})
	check(not game.audio_player.stream_paused, "manual unmute restores music")

	var worker: Dictionary = {}
	for unit in game.simulation_world.get_units():
		if int(unit["team"]) == game.local_player_team and game.simulation_world.entity_is_worker(unit):
			worker = unit
			break
	check(not worker.is_empty(), "latest saved match has a human worker")
	var target := Vector2(-1, -1)
	if not worker.is_empty():
		var center := Vector2i(Vector2(worker["pos"]).floor())
		for y in range(center.y - 12, center.y + 13):
			for x in range(center.x - 12, center.x + 13):
				# Player placement snaps the pointer to integer world coordinates.
				var candidate := Vector2(x, y)
				if game.simulation_world.can_place_foundation(game.local_player_team, "house", candidate):
					target = candidate
					break
			if target.x >= 0: break
	check(target.x >= 0, "latest saved map has a legal house site")
	if target.x >= 0:
		var existing: Dictionary = {}
		for building in game.simulation_world.get_buildings(): existing[int(building["id"])] = true
		var worker_ids: Array[int] = [int(worker["id"])]
		game.player_control_state.replace_or_add(worker_ids, false)
		game.sync_world_state()
		game.pending_build_kind = "house"
		var screen: Vector2 = game.world_to_screen(target)
		game.handle_input_action({"type":"selection_committed", "from":screen, "to":screen, "mode":"single"})
		check(await Ready.advance_to_tick(get_tree(), game.game_controller, loaded_tick + 1, game.local_player_team, 2), "placed building command reaches simulation")
		var foundation: Dictionary = {}
		for building in game.simulation_world.get_buildings():
			if not existing.has(int(building["id"])) and String(building["kind"]) == "house": foundation = building
		check(not foundation.is_empty(), "normal player placement creates a foundation")
		if not foundation.is_empty():
			var key := (int(foundation["id"]) << 1) | 1
			var fog = game.simulation_world.get_fog_of_war()
			check(not fog.vision_sources.has(key), "placed foundation contributes no sight")
			game.simulation_world.update_fog_of_war()
			check(not fog.vision_sources.has(key), "full fog refresh still excludes the foundation")
			game.simulation_world.complete_foundation(foundation)
			game.simulation_world.update_fog_of_war()
			check(fog.vision_sources.has(key), "completed building starts providing sight")

	game._return_to_launcher()
	check(game.launcher_suspended and game.audio_player.stream_paused, "main menu suspends music")
	var launcher = current_scene
	launcher._resume_active_game()
	game.set_process(false)
	check(not game.launcher_suspended and not game.audio_player.stream_paused, "returning from main menu restores music")
	game.handle_input_action({"type":"toggle_audio"})
	game._return_to_launcher()
	launcher = current_scene
	launcher._resume_active_game()
	game.set_process(false)
	check(game.audio_muted and game.audio_player.stream_paused, "main menu round trip preserves manual mute")
	var report := {"release":not OS.is_debug_build(), "save":save, "loaded_tick":loaded_tick, "final_tick":game.game_controller.tick_index, "checks":checks, "failures":failures}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	game.free()
	await get_tree().process_frame
	for failure in failures: push_error(failure)
	print("Reported gameplay fixes on saved match: ", checks.size(), " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks.append({"check":message, "passed":value})
	if not value: failures.append(message)
