extends SceneTree

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"

var failures: Array[String] = []


func _initialize() -> void:
	test_panned_statics_track_camera()
	if failures.is_empty():
		print("panned static projection tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_panned_statics_track_camera() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.scenario_overlay._dismiss_briefing()
	game.sync_world_state(true)
	var checked := 0
	# Interleave camera panning with fixed-tick snapshot republication: an
	# E6-026 regression let cached resource/environment statics keep a stale
	# screen position on publication frames, so panned scenery appeared glued
	# to the camera. Every static drawable must match the live projection on
	# every frame, including rebuild frames.
	for frame in range(24):
		game.view_offset += Vector2(23.0, 11.0)
		if frame % 3 == 2:
			game.game_controller.advance_frame(0.05, 1, 2)
			game.sync_world_state()
		checked += _assert_statics_projected(game, "pan frame %d" % frame)
	for zoom_step in range(6):
		game.view_zoom = clampf(game.view_zoom * 1.08, 0.5, 3.0)
		if zoom_step % 4 == 3:
			game.game_controller.advance_frame(0.05, 1, 2)
			game.sync_world_state()
		checked += _assert_statics_projected(game, "zoom step %d" % zoom_step)
	assert_true(checked > 0, "panned projection check inspected static drawables")


func _assert_statics_projected(game, context: String) -> int:
	var inspected := 0
	for drawable_value in game.current_world_drawables():
		var drawable: Dictionary = drawable_value
		var kind := String(drawable.get("kind", ""))
		if kind != "resource" and kind != "environment" and kind != "building":
			continue
		inspected += 1
		var anchor: Vector2 = drawable.get("world_anchor", Vector2.ZERO)
		var expected: Vector2 = game.world_to_screen(anchor)
		var actual: Vector2 = drawable.get("screen_position", Vector2(99999.0, 99999.0))
		if (expected - actual).length() > 0.6:
			failures.append("%s: static %s id=%s expected screen %s, kept %s" % [context, kind, str(drawable.get("stable_id")), str(expected), str(actual)])
	return inspected


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
