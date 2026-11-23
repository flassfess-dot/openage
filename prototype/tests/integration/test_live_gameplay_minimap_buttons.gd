extends SceneTree

const Ready := preload("res://tests/support/match_ready.gd")
const Aperture := preload("res://scripts/minimap_aperture.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	viewport.add_child(game)
	if not await Ready.wait_for_ready(self, game):
		game.free()
		quit(1)
		return
	game.set_process(false)
	var world = game.simulation_world
	var hud = game.hud_controls
	var existing_workers: Array = world.get_units().filter(func(unit): return world.entity_is_worker(unit))
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(12, 14), false)
	var boat: Dictionary = world.add_unit(1, "fishing_boat", Vector2(1, 11), false)
	world.add_unit(2, "fishing_boat", Vector2(1, 22), false)
	world.add_unit(1, "scout_ship", Vector2(2, 20), false)
	var queued: Dictionary = world.add_unit(1, "villager", Vector2(17, 14), false)
	queued["components"]["order"]["queued"].append({"kind": "move"})
	world.match_statistics.sample(world, 100, true)
	var before := int(world.match_statistics.teams[1]["score"])
	world.match_statistics.consume(world, "ownership_changed", {"new_team": 1, "ownership_reason": "conversion"}, 101)
	world.match_statistics.sample(world, 200, true)
	check(before > 0 and int(world.match_statistics.teams[1]["score"]) > before, "ordinary match scores reflect play")
	var after_conversion := int(world.match_statistics.teams[1]["score"])
	world.economy_system.change_resource_amount(1, 3, 200, "trade_in")
	world.match_statistics.sample(world, 300, true)
	check(int(world.match_statistics.teams[1]["score"]) == after_conversion + 2, "gold brought home by traders counts towards the score")
	world.set_score(2, 572)
	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, 1, 2)
	for unit in existing_workers:
		world.set_entity_field(unit, "task", "gather")
	queued["components"]["order"]["queued"] = [{"kind": "move"}]
	game.sync_world_state()
	game.refresh_hud_model()
	check(not hud.score_panel.visible, "score overlay starts closed")
	for width in [1280, 800, 640, 360]:
		viewport.size = Vector2i(width, 720)
		game.hud_controls.size = Vector2(width, 720)
		await process_frame
		var map_rect: Rect2 = game.minimap_geometry()["rectangle"]
		for button in [hud.idle_worker_button, hud.score_button]:
			var button_rect: Rect2 = button.get_global_rect()
			check(Rect2(Vector2.ZERO, viewport.size).encloses(button_rect), "minimap button fits at width %d" % width)
			for corner in [button_rect.position, button_rect.end - Vector2.ONE, Vector2(button_rect.position.x, button_rect.end.y - 1), Vector2(button_rect.end.x - 1, button_rect.position.y)]:
				check(not Aperture.contains(corner, map_rect), "button leaves clickable minimap exposed at %d" % width)
		var camera: Vector2 = game.view_offset
		click(viewport, hud.score_button)
		check(hud.score_panel.visible and hud.score_panel.players.size() == 2, "click shows both scores at width %d" % width)
		if hud.score_panel.players.size() == 2:
			check(hud.score_panel.players[0]["score"] == world.match_statistics.teams[1]["score"] and hud.score_panel.players[1]["score"] == 572, "scoreboard uses public match scores including scenario points")
		check(Rect2(Vector2.ZERO, viewport.size).encloses(hud.score_panel.get_global_rect()), "scoreboard fits at width %d" % width)
		check(camera == game.view_offset, "toggle preserves camera at width %d" % width)
		if "--capture-minimap" in OS.get_cmdline_user_args() and width in [1280, 640]:
			await RenderingServer.frame_post_draw
			var dir := ProjectSettings.globalize_path("res://qa/minimap-controls")
			DirAccess.make_dir_recursive_absolute(dir)
			var shown := viewport.get_texture().get_image()
			shown.save_png(dir.path_join("scores-%d.png" % width))
			hud.idle_worker_button.hide()
			hud.score_button.hide()
			await RenderingServer.frame_post_draw
			var background := viewport.get_texture().get_image()
			for button in [hud.idle_worker_button, hud.score_button]:
				var region := Rect2i(button.get_global_rect())
				check(shown.get_region(region).get_data() != background.get_region(region).get_data(), "minimap frame does not cover button at width %d" % width)
				button.show()
		click(viewport, hud.score_button)
		check(not hud.score_panel.visible and camera == game.view_offset, "second click hides scores and preserves camera")
	for unit in [worker, boat, worker]:
		click(viewport, hud.idle_worker_button)
		check(game.player_control_state.selected_ids() == [int(unit["id"])], "button selected %s, expected %s (%s)" % [game.player_control_state.selected_ids(), unit["id"], unit["kind"]])
		var target: Vector2 = Vector2(viewport.size.x * 0.5, (game.hud_top_height() + viewport.size.y - game.hud_bottom_height()) * 0.5)
		check((game.iso_raw(unit["pos"]) * game.view_zoom + game.view_offset).distance_to(target) < 0.01, "camera centers on selected worker")
	click(viewport, hud.score_button)
	world.set_score(2, 0)
	game.game_controller.advance_frame(game.game_controller.FIXED_STEP_SECONDS, 1, 2)
	game.sync_world_state()
	game.refresh_hud_model()
	check(hud.score_panel.players[1]["score"] == 0, "open scoreboard refreshes and preserves an explicit zero")
	game.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Live gameplay minimap buttons passed")
	quit(0 if failures.is_empty() else 1)

func click(viewport: Viewport, button: Button) -> void:
	var point := button.get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = point
	viewport.push_input(hover, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		viewport.push_input(event, true)

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
