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

const Projection := preload("res://scripts/minimap_projection.gd")
const Aperture := preload("res://scripts/minimap_aperture.gd")
const Fog := preload("res://scripts/fog_of_war.gd")
const Replay := preload("res://scripts/replay_system.gd")

func _initialize() -> void:
	var game = await create_game()
	if not failures.is_empty():
		game.free()
		finish("Live gameplay fixture")
		return
	var soldiers: Array = game.simulation_world.get_units().filter(func(unit): return unit.get("kind") == "clubman" and int(unit.get("team", 0)) == 1)
	var ids: Array[int] = []
	var starts: Dictionary = {}
	for soldier in soldiers:
		ids.append(int(soldier["id"]))
		starts[int(soldier["id"])] = soldier["pos"]
	game.player_control_state.replace_or_add(ids, false)
	game.sync_world_state()
	var geometry: Dictionary = game.minimap_geometry()
	var target := Vector2(-1, -1)
	for candidate in [Vector2(25.5, 2.5), Vector2(22.5, 3.5), Vector2(19.5, 2.5)]:
		var screen := Projection.world_to_minimap(candidate, geometry["center"], geometry["scale"])
		if game.simulation_world.get_fog_of_war().state_at_world(1, candidate) == Fog.UNKNOWN and Aperture.contains(screen, geometry["rectangle"]):
			target = candidate
			break
	check(target.x >= 0.0, "fixture contains an unknown point inside the minimap aperture")
	if target.x >= 0.0:
		var pointer := Projection.world_to_minimap(target, geometry["center"], geometry["scale"])
		var camera: Vector2 = game.view_offset
		var count: int = game.game_controller.replay_recorder.command_records.size()
		var click := InputEventMouseButton.new()
		click.position = pointer
		click.button_index = MOUSE_BUTTON_RIGHT
		click.pressed = true
		check(game.handle_minimap_input(click), "right minimap click is consumed")
		check(game.game_controller.replay_recorder.command_records.size() == count + 1, "minimap emits exactly one squad order")
		var record: Dictionary = game.game_controller.replay_recorder.command_records[-1]
		check(record["type"] == "formation_move", "minimap uses the ordinary formation movement command")
		var params: Dictionary = Replay.decode_variant(record["params"])
		check(Vector2(params["target"]).is_equal_approx(target), "command targets the clicked world location")
		check(game.view_offset == camera, "right click preserves the camera")
		advance_tick(game)
		check(bool(game.game_controller.get_command_result(int(record["sequence_id"])).get("accepted", false)), "unexplored destination is accepted")
		click.pressed = false
		check(game.handle_minimap_input(click), "right release is consumed without a duplicate order")
		check(game.game_controller.replay_recorder.command_records.size() == count + 1, "right release does not add a second order")
		for _tick in range(180): advance_tick(game)
		for id in ids:
			var soldier: Dictionary = game.simulation_world.find_unit(id)
			check(Vector2(soldier["pos"]).distance_to(starts[id]) > 1.0, "squad member %d actually moves after the minimap order" % id)
		click.pressed = true
		click.shift_pressed = true
		check(game.handle_minimap_input(click), "Shift + right minimap click is consumed")
		var queued: Dictionary = game.game_controller.replay_recorder.command_records[-1]
		var queued_params: Dictionary = Replay.decode_variant(queued["params"])
		check(queued["type"] == "move" and bool(queued_params.get("queue_order", false)), "Shift preserves the order queue contract")
		advance_tick(game)
		check(bool(game.game_controller.get_command_result(int(queued["sequence_id"])).get("accepted", false)), "queued minimap movement is accepted")
		click.pressed = false
		click.position = Vector2(-10, -10)
		count = game.game_controller.replay_recorder.command_records.size()
		check(game.handle_minimap_input(click), "a minimap right gesture also ends outside the minimap")
		check(game.game_controller.replay_recorder.command_records.size() == count, "outside release does not issue another order")
		click.position = pointer
		click.pressed = true
		game.local_spectator = true
		count = game.game_controller.replay_recorder.command_records.size()
		game.handle_minimap_input(click)
		check(game.game_controller.replay_recorder.command_records.size() == count, "spectator cannot issue minimap orders")
		game.local_spectator = false
		click.button_index = MOUSE_BUTTON_LEFT
		click.shift_pressed = false
		game.handle_minimap_input(click)
		check(game.game_controller.replay_recorder.command_records.size() == count, "left minimap click remains a camera action")
		check(game.view_offset != camera, "left minimap click still pans the camera")
	game.free()
	finish("Live gameplay minimap orders in unknown terrain")

func finish(label: String) -> void:
	if failures.is_empty():
		print(label + " passed")
		quit(0)
		return
	for failure in failures: push_error(failure)
	quit(1)

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)
