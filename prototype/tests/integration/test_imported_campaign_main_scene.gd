extends SceneTree

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"

var failures: Array[String] = []


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	var elapsed := Time.get_ticks_msec() - started
	assert_equal(game.match_definition.get("id"), "campaign_birth_of_rome", "main scene launches the selected imported match")
	assert_equal(game.map_size, Vector2i(250, 250), "main scene owns the complete source map")
	assert_equal(game.simulation_world.get_units().size() + game.simulation_world.get_buildings().size() + game.simulation_world.get_resources().size(), 9546, "main scene bootstraps every source simulation entity including wildlife and the static forest field")
	assert_equal(game.ai_players.size(), 6, "all opponents execute their imported source campaign AI profile")
	assert_true(game.ai_players.all(func(player): return player.profile == "source_campaign_v1"), "campaign never falls back to generic skirmish AI")
	assert_equal(game.simulation_world.economy_system.get_population_limit(2), 75, "source population limit reaches the authoritative economy system")
	assert_equal(game.presentation_snapshot.get("markers", []).size(), 12, "source scenario flags reach the presentation snapshot without becoming simulation entities")
	assert_equal(game.environment_presentation_field.item_count, 5340, "viewport field indexes source scenery, overlays, birds and cliffs once")
	var flag_frame: Dictionary = game.resource_catalog.scenario_marker_frame_info(game.presentation_snapshot.get("markers", [])[0])
	assert_equal(String(flag_frame.get("asset_name", "")), "graphic_322_p1", "scenario flag resolves its original imported art")
	assert_true(flag_frame.get("texture") != null, "scenario flag texture is loadable")
	assert_true(game.scenario_overlay.visible and game.scenario_overlay.briefing_layer.visible, "campaign opens with its briefing")
	assert_true(game.scenario_overlay.is_blocking(), "simulation waits while the briefing is open")
	assert_true(game.scenario_overlay.briefing_objectives.text.contains("0/12"), "briefing presents all twelve source objective areas")
	var bounds: Rect2i = game.visible_tile_bounds()
	assert_true(bounds.get_area() < game.map_size.x * game.map_size.y / 4, "large-map renderer limits terrain work to the visible camera footprint: %s" % bounds)
	print("I12-020D visible terrain bounds: %s (%d tiles)" % [str(bounds), bounds.get_area()])
	game.scenario_overlay._dismiss_briefing()
	assert_true(not game.scenario_overlay.is_blocking(), "begin button releases simulation")
	assert_true(game.scenario_overlay.objectives_panel.visible, "compact objectives remain visible during play")
	game.set_process(false)
	var render_started := Time.get_ticks_msec()
	for _frame in range(10):
		game.queue_redraw()
		await process_frame
	var render_elapsed := Time.get_ticks_msec() - render_started
	var simulation_started := Time.get_ticks_msec()
	for _tick in range(10):
		game.game_controller.advance_frame(0.05, 1, 2)
		game.sync_world_state()
	var simulation_elapsed := Time.get_ticks_msec() - simulation_started
	game.set_process(true)
	var active_started := Time.get_ticks_msec()
	var active_frame_times: Array[int] = []
	var active_frame_ticks: Array[int] = []
	for _frame in range(10):
		var frame_started := Time.get_ticks_msec()
		await process_frame
		active_frame_times.append(Time.get_ticks_msec() - frame_started)
		active_frame_ticks.append(game.game_controller.tick_index)
	var active_elapsed := Time.get_ticks_msec() - active_started
	assert_true(active_frame_times.max() < 5000, "source campaign avoids the former multi-second pathfinding frame regression: %s" % [active_frame_times])
	game.set_process(false)
	var completed_snapshot: Dictionary = game.presentation_snapshot.duplicate(true)
	completed_snapshot["match_result"] = {"over": true, "winner_team": 1, "loser_teams": [2], "reason": "scenario"}
	game.scenario_overlay.set_snapshot(completed_snapshot)
	assert_true(game.scenario_overlay.result_layer.visible, "authoritative match result opens the final screen")
	assert_equal(game.scenario_overlay.result_title.text, "ПОБЕДА", "local winner receives victory presentation")
	print("I12-020E imported campaign main scene ready: %d ms" % elapsed)
	print("I12-020E imported campaign 10 forced render frames: %d ms" % render_elapsed)
	print("I12-020E imported campaign 10 fixed ticks plus source-AI snapshots: %d ms" % simulation_elapsed)
	print("I12-020E imported campaign 10 active frames: %d ms" % active_elapsed)
	print("I12-020E active frame milliseconds: %s; ticks: %s" % [str(active_frame_times), str(active_frame_ticks)])
	game.free()
	_finish("I12-020E imported campaign main scene tests passed")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
