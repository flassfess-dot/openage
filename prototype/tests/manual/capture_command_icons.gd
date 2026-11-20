extends SceneTree

const Ready := preload("res://tests/support/match_ready.gd")
const Commands := preload("res://scripts/commands.gd")
const Definition := preload("res://scripts/match_definition.gd")

var output := "res://qa/command-icons-review/current"
var capture_error := OK
var include_compact := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Command icon review requires a graphical renderer.")
		quit(1)
		return
	var civilization := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
		elif argument.begins_with("--civ="):
			civilization = argument.trim_prefix("--civ=").to_int()
		elif argument == "--compact":
			include_compact = true
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) != OK:
		push_error("Could not create " + output)
		quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var game = load("res://main.tscn").instantiate()
	if civilization > 0:
		var definition := Definition.load_json()
		for player in definition["players"]:
			if player["team"] == definition["local_team"]:
				player["civilization_id"] = civilization
		game.match_definition_override = definition
	viewport.add_child(game)
	if not await Ready.wait_for_ready(self, game):
		quit(1)
		return
	game.game_controller.set_paused(true)
	game.set_process(false)
	var world = game.simulation_world
	var team: int = game.local_player_team
	var workers: Array = world.get_units().filter(func(unit):
		return unit["team"] == team and unit["kind"] == "villager"
	)
	if workers.is_empty():
		push_error("The review fixture needs an owned villager.")
		quit(1)
		return
	var worker: Dictionary = workers[0]
	var camp: Vector2 = worker["pos"]
	game.center_view_on_world(camp)
	select_ids(game, [int(worker["id"])])
	await capture(game, viewport, "worker")
	game.hud_controls.set_build_menu_open(true)
	await capture(game, viewport, "construction")

	var soldier: Dictionary = world.add_unit(team, "clubman", camp + Vector2(2, -1), false)
	var second: Dictionary = world.add_unit(team, "clubman", camp + Vector2(3, 0), false)
	var siege: Dictionary = world.add_unit(team, "stone_thrower", camp + Vector2(1, 2), false)
	var gate: Dictionary = world.add_building(90001, "gate", camp + Vector2(4, 3), team)
	world.update_fog_of_war()
	select_ids(game, [int(soldier["id"]), int(second["id"])])
	await capture(game, viewport, "formations")
	var widths := [800, 640, 320] if include_compact else [800, 640]
	for width in widths:
		viewport.size.x = width
		await capture(game, viewport, "formations-%d" % width)
	viewport.size.x = 1280

	select_ids(game, [int(siege["id"])])
	for stance in Commands.STANCE_ORDER:
		world.set_entity_field(siege, "stance", stance)
		await capture(game, viewport, "siege-" + stance)
	game.select_hud_building(int(gate["id"]))
	await capture(game, viewport, "gate")

	var ship: Dictionary = world.add_unit(team, "transport", camp, false)
	var trader: Dictionary = world.add_unit(team, "trade_boat", Vector2(ship["pos"]) + Vector2(0, 2), false)
	world.update_fog_of_war()
	game.center_view_on_world(ship["pos"])
	select_ids(game, [int(ship["id"])])
	await capture(game, viewport, "transport-empty")
	var passenger: Dictionary = world.add_unit(team, "clubman", ship["pos"], false)
	if not world.board_units([passenger], ship).is_empty():
		push_error("Could not board the review transport.")
		quit(1)
		return
	await capture(game, viewport, "transport-loaded")
	select_ids(game, [int(trader["id"])])
	await capture(game, viewport, "trade")

	var tower: Dictionary = world.add_building(90002, "tower", camp + Vector2(4, -2), team)
	var archer: Dictionary = world.add_unit(team, "archer", tower["pos"], false)
	if not world.board_units([archer], tower).is_empty():
		push_error("Could not fill the review garrison.")
		quit(1)
		return
	game.center_view_on_world(tower["pos"])
	game.select_hud_building(int(tower["id"]))
	await capture(game, viewport, "garrison")
	viewport.free()
	quit(0 if capture_error == OK else 1)


func select_ids(game, ids: Array[int]) -> void:
	game.player_control_state.replace_or_add(ids, false)


func capture(game, viewport: SubViewport, name: String) -> void:
	game.sync_world_state()
	game.refresh_hud_model()
	game.message_time = 0
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	var bottom := int(game.hud_bottom_height())
	var crop := image.get_region(Rect2i(0, image.get_height() - bottom, image.get_width(), bottom))
	var error := crop.save_png(output.path_join(name + ".png"))
	if error != OK:
		capture_error = error
		push_error("Could not save " + name)
	if name == "formations":
		error = image.save_png(output.path_join("in-game.png"))
		if error != OK:
			capture_error = error
			push_error("Could not save the full match screenshot.")
