extends SceneTree
const Ready := preload("res://tests/support/match_ready.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640,480)
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	viewport.add_child(game)
	if not await Ready.wait_for_ready(self, game):
		game.free()
		quit(1)
		return
	game.set_process(false)
	game.game_controller.set_paused(false)
	game._sync_music_playback()
	check(not game.audio_player.stream_paused, "running match plays music")
	game.handle_input_action({"type":"toggle_pause"})
	check(game.game_controller.paused and game.audio_player.stream_paused, "ordinary pause also pauses music")
	game.handle_input_action({"type":"toggle_pause"})
	check(not game.audio_player.stream_paused, "ordinary resume restores music")
	game.view_offset += Vector2(137, -83)
	var camera_before: Vector2 = game.screen_to_world(game.viewport_focus)
	viewport.size = Vector2i(800,600)
	await process_frame
	await process_frame
	check(game.screen_to_world(game.viewport_focus).distance_to(camera_before) < 0.01, "resizing/fullscreen layout preserves the camera's world focus")
	viewport.size = Vector2i(640,480)
	await process_frame
	await process_frame
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	viewport.push_input(event, true)
	await process_frame
	check(game.hud_modal_overlay.is_blocking() and game.game_controller.paused, "Escape opens menu and pauses the single-player match")
	check(game.audio_player.stream_paused, "Escape menu pauses music")
	await process_frame
	check(Rect2(0,0,640,480).encloses(game.hud_modal_overlay.menu_card.get_global_rect()), "first menu opening in the real scene fits 640x480 after container layout")
	for section in ["save", "load", "settings", "achievements", "timeline", "instructions", "help", "menu"]:
		game.hud_modal_overlay.show_section(section)
		await process_frame
		await process_frame
		check(Rect2(0,0,640,480).encloses(game.hud_modal_overlay.menu_card.get_global_rect()), "real scene %s fits 640x480" % section)
	game._close_hud_modal()
	check(not game.game_controller.paused, "closing menu restores running state")
	check(not game.audio_player.stream_paused, "closing menu resumes music")
	game.handle_input_action({"type":"toggle_audio"})
	game._toggle_game_menu()
	game._close_hud_modal()
	check(game.audio_muted and game.audio_player.stream_paused, "menu close preserves manual mute")
	game.handle_input_action({"type":"toggle_audio"})
	check(not game.audio_player.stream_paused, "manual unmute resumes a running match")
	game._request_window_quit()
	check(game.hud_modal_overlay.active_section == "confirm" and game.hud_modal_overlay.pending_action.get("type") == "quit", "window close routes through a cancellable confirmation")
	game.hud_modal_overlay.go_back()
	game._close_hud_modal()
	game.game_controller.set_paused(true)
	game._toggle_game_menu()
	game._close_hud_modal()
	check(game.game_controller.paused, "closing menu preserves a pre-existing pause")
	check(game.audio_player.stream_paused, "closing menu preserves music pause when the match remains paused")
	game.game_controller.set_paused(false)
	game.player_control_state.clear()
	var before_tick: int = game.game_controller.tick_index
	event.keycode = KEY_R
	viewport.push_input(event, true)
	await process_frame
	check(game.game_controller.tick_index == before_tick and not game.hud_modal_overlay.visible, "R without repair context cannot restart the match")
	game._toggle_game_menu()
	game.hud_modal_overlay.show_section("timeline")
	var participants: Array = game.simulation_world.player_registry.all_teams()
	check(participants.size() >= 2, "fixture has multiple participants in an active match")
	check(game.hud_modal_overlay.timeline.history["teams"].size() == participants.size(), "active timeline lists all match participants")
	for team in participants:
		check(game.hud_modal_overlay.timeline.history["teams"].has(team), "active timeline includes participant %d" % team)
		for sample in game.hud_modal_overlay.timeline.history["samples"]:
			check(sample["teams"].has(team), "recorded population of participant %d remains visible" % team)
	check(game.hud_modal_overlay.timeline_rows.size() == participants.size(), "player table includes opponents before match completion")
	game.hud_modal_overlay.show_section("instructions")
	check(not game.hud_modal_overlay.instructions_text.text.is_empty(), "match instructions have actual content")
	var queued: int = game.game_controller.command_queue.size()
	game.hud_modal_overlay.request_confirmation("resign")
	game.hud_modal_overlay.go_back()
	check(game.game_controller.command_queue.size() == queued and game.simulation_world.player_registry.status(1) == "active", "cancelled resignation leaves the simulation untouched")
	game.hud_modal_overlay.request_confirmation("resign")
	game.hud_modal_overlay._confirm_action()
	check(game.game_controller.command_queue.size() == queued + 1, "confirmed resignation submits one authoritative command")
	check(not game.hud_modal_overlay.visible and not game.game_controller.paused, "confirmed resignation releases the menu pause")
	if await Ready.advance_to_tick(self, game.game_controller, game.game_controller.tick_index+1, 1, 2):
		game.sync_world_state()
		check(game.local_spectator, "confirmed resignation reaches the spectator lifecycle")
		game.handle_input_action({"type":"open_game_menu"})
		game.hud_modal_overlay.show_section("timeline")
		check(game.hud_modal_overlay.statistics.get("reveal_all", false), "completed or spectator match can review all TimeLine players")
		game._close_hud_modal()
		game.scenario_overlay.statistics_requested.emit()
		check(game.hud_modal_overlay.active_section == "achievements", "final result opens achievements with a TimeLine link")
	else: check(false, "resignation tick completes")
	game.free()
	viewport.free()
	for failure in failures: push_error(failure)
	print("Live match menu pipeline: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
