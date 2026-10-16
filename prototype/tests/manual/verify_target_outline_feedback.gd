extends Node

const ObservedGame := preload("res://tests/support/observed_feedback_game.gd")
const Definition := preload("res://scripts/match_definition.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")

var failures: Array[String] = []
var output_path := "res://qa/target-feedback-20261016/source/report.json"
var report := {"passed": false, "cases": [], "screenshots": []}
var game

func _ready() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func select(ids: Array[int]) -> void:
	game.player_control_state.replace_or_add(ids, false)
	game.resource_feedback_time = 0
	game.interaction_highlight_id = -1
	game.selection_preview_ids.clear()
	game.sync_world_state()

func click(button: MouseButton, position: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = pressed
		event.position = position
		game._unhandled_input(event)

func pointer_for(target: Dictionary) -> Vector2:
	# Scan the actual sprite/footprint hit stack rather than assuming that its
	# anchor remains clickable underneath every source sprite.
	var center: Vector2 = game.world_to_screen(target["pos"])
	for dy in range(-64, 33, 4):
		for dx in range(-48, 49, 4):
			var point := center + Vector2(dx, dy)
			var hits: Array = game.pick_stack_at(point)
			if not hits.is_empty() and int(hits[0]["id"]) == int(target["id"]):
				return point
	check(false, "target is pickable: %s" % target.get("kind"))
	return center

func observe(target_id: int, phase: float, expected: bool, color: Color, label: String, capture := false) -> void:
	game.resource_feedback_time = phase
	game.observed_outlines.clear()
	var items: Array = game.current_world_drawables()
	var selections: Array = items.filter(func(item): return item["kind"] == "selection" and int(item["stable_id"]) == target_id)
	check(selections.size() == 1, label + ": exactly one selection record")
	if not selections.is_empty():
		check(not selections[0].has("sprite_command"), label + ": selection is never submitted as a body sprite")
	if DisplayServer.get_name() == "headless":
		for item in selections:
			if not item.has("sprite_command"): game.draw_world_item(item)
	else:
		game.queue_redraw()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var matches: Array = game.observed_outlines.filter(func(outline): return int(outline["id"]) == target_id and outline["color"] == color)
	check((not matches.is_empty()) == expected, label + ": visible outline matches blink phase")
	if capture and DisplayServer.get_name() != "headless":
		var path := output_path.get_base_dir().path_join(label + ".png")
		check(get_tree().root.get_texture().get_image().save_png(path) == OK, label + ": screenshot")
		report["screenshots"].append(ProjectSettings.globalize_path(path))

func order_case(actor: Dictionary, target: Dictionary, command_type: String, label: String, capture := false) -> void:
	select([int(actor["id"])])
	game.center_view_on_world(target["pos"])
	game.sync_world_state()
	var sequence_before: int = game.game_controller.replay_recorder.command_records.size()
	click(MOUSE_BUTTON_RIGHT, pointer_for(target))
	var records: Array = game.game_controller.replay_recorder.command_records
	check(records.size() == sequence_before + 1, label + ": real right click creates a command")
	if records.size() != sequence_before + 1: return
	var command: Dictionary = records[-1]
	check(command["type"] == command_type, label + ": expected context command")
	game.game_controller.tick_index += 1
	game.game_controller.process_commands()
	game.sync_world_state()
	game.process_presentation_events()
	check(bool(game.game_controller.get_command_result(int(command["sequence_id"])).get("accepted", false)), label + ": command accepted")
	check(game.resource_feedback_id == int(target["id"]) and game.resource_feedback_time > 0, label + ": accepted feedback targets clicked entity")
	for phase in [0.64, 0.54, 0.44, 0.34]:
		await observe(int(target["id"]), phase, int(phase * 10) % 2 == 0, Color("ffe56c"), label + ("-on" if phase == 0.64 else "-off" if phase == 0.54 else "-phase%d" % int(phase * 100)), capture and phase > 0.5)
	# The same publication is retained while moving/zooming the camera.
	game.view_offset += Vector2(19, -11)
	game.view_zoom = 1.25
	await observe(int(target["id"]), 0.44, true, Color("ffe56c"), label + "-camera")
	game.view_zoom = 1.0
	game.interaction_highlight_id = -1
	game.resource_feedback_time = 0
	game.observed_outlines.clear()
	check(not game.current_world_drawables().any(func(item): return item["kind"] == "selection" and int(item["stable_id"]) == int(target["id"])), label + ": target-only highlight expires")
	report["cases"].append(label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	report["release"] = not OS.has_feature("editor")
	report["graphical"] = DisplayServer.get_name() != "headless"
	if "--require-release" in OS.get_cmdline_user_args(): check(report["release"], "runs exported Release")
	get_tree().root.size = Vector2i(1280, 720)
	game = ObservedGame.new()
	game.match_definition_override = Definition.load_json("res://tests/fixtures/e3_save_state_matrix_match.json")
	get_tree().root.add_child(game)
	if not await MatchReady.wait_for_ready(get_tree(), game):
		check(false, "match navigation ready")
		finish()
		return
	game.set_process(false)
	game.game_controller.set_paused(true)
	var world = game.simulation_world
	var worker: Dictionary = world.get_units().filter(func(unit): return unit["team"] == 1 and unit["kind"] == "villager")[0]
	var soldier: Dictionary = world.get_units().filter(func(unit): return unit["team"] == 1 and unit["kind"] == "clubman")[0]
	var center: Dictionary = world.get_buildings().filter(func(building): return building["kind"] == "town_center")[0]
	var barracks: Dictionary = world.get_buildings().filter(func(building): return building["kind"] == "barracks")[0]
	var tree: Dictionary = world.get_resources()[0]
	var enemy: Dictionary = world.get_units().filter(func(unit): return unit["team"] == 2 and unit["kind"] == "clubman")[0]
	# Explicit visibility is part of this fixture; retain the real picking and
	# command paths without relying on accidental starting vision.
	world.fog_of_war.ensure_player(1)
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):
			world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	var vision_components: Dictionary = center["components"].duplicate(true)
	vision_components["vision"]["range"] = 40.0
	world.set_entity_field(center, "components", vision_components)
	world.fog_of_war.update(world.get_units(), world.get_buildings())
	world.set_entity_field(barracks, "hp", float(barracks["max_hp"]) * 0.7)
	await order_case(worker, barracks, "repair", "repair-building", true)
	world.set_entity_field(worker, "carried_resource_type_id", 1)
	world.set_entity_field(worker, "carried_amount", 5.0)
	await order_case(worker, center, "return_resources", "dropoff-building")
	world.set_entity_field(worker, "carried_amount", 0.0)
	await order_case(worker, tree, "gather", "gather-tree", true)
	var foundation: Dictionary = world.add_building(99001, "house", Vector2(19, 10), 1, false)
	await order_case(worker, foundation, "build", "continue-foundation")
	var farm: Dictionary = world.add_building(99002, "farm", Vector2(21, 14), 1, true)
	await order_case(worker, farm, "gather", "gather-farm")
	await order_case(soldier, enemy, "attack", "attack-unit")
	var enemy_building: Dictionary = world.add_building(99003, "house", Vector2(21, 20), 2, true)
	await order_case(soldier, enemy_building, "attack", "attack-building")
	select([])
	game.center_view_on_world(center["pos"])
	game.sync_world_state()
	click(MOUSE_BUTTON_LEFT, pointer_for(center))
	check(game.player_control_state.is_selected(int(center["id"])), "left click selects building")
	await observe(int(center["id"]), 0, true, Color("e8f45b"), "selected-building", true)
	select([int(worker["id"])])
	game.interaction_highlight_id = int(barracks["id"])
	await observe(int(barracks["id"]), 0, true, Color("66e8ff"), "hover-building")
	game.interaction_highlight_id = -1
	game.selection_preview_ids.assign([int(barracks["id"])])
	await observe(int(barracks["id"]), 0, true, Color("66e8ff"), "preview-building")
	report["cases"].append_array(["selected-building", "hover-building", "preview-building"])
	game.free()
	finish()

func finish() -> void:
	report["passed"] = failures.is_empty()
	report["failures"] = failures
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	print("Target outline feedback: %d cases, %d failures" % [report["cases"].size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
