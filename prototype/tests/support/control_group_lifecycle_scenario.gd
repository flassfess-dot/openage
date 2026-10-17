extends RefCounted
const Ready := preload("res://tests/support/match_ready.gd")
const Commands := preload("res://scripts/commands.gd")
var failures: Array[String] = []

func run(tree: SceneTree) -> Array[String]:
	var game = load("res://main.tscn").instantiate()
	tree.root.add_child(game)
	if not await Ready.wait_for_ready(tree, game, 120000): game.free(); return ["fixture did not become ready"]
	game.set_process(false)
	game.game_controller.set_paused(false)
	var ids: Array[int] = []
	for unit in game.simulation_world.get_units():
		if int(unit.get("team", 0)) == game.local_player_team and float(unit.get("hp", 0)) > 0:
			ids.append(int(unit["id"]))
			if ids.size() == 3: break
	check(not ids.is_empty(), "fixture has local units")
	game.player_control_state.replace_or_add(ids, false)
	game.sync_world_state()
	press(game, KEY_1, true)
	check(game.control_groups.groups.get(1, []) == ids, "Ctrl+1 assigns through the keyboard input path")
	for id in ids:
		game.game_controller.enqueue_command(Commands.DeleteEntityCommand.new(game.game_controller.tick_index + 1, [id]), true, game.local_player_team)
	if not await Ready.advance_to_tick(tree, game.game_controller, game.game_controller.tick_index + 2, game.PLAYER_TEAM, game.ENEMY_TEAM): game.free(); return ["fixture did not become ready"]
	game.sync_world_state()
	game.set_process(true)
	await tree.process_frame
	if not await Ready.wait_for_ready(tree, game, 120000): game.free(); return ["fixture did not become ready"]
	game.set_process(false)
	game.sync_world_state()
	for id in ids:
		var unit = game.simulation_world.find_unit(id)
		check(unit == null or float(unit.get("hp", 0)) <= 0, "group member died through a game command")
	var camera_before: Vector2 = game.view_offset
	for _repeat in range(3):
		press(game, KEY_1)
		check(game.game_message == "Группа 1 пуста", "destroyed group reports empty")
		check(game.view_offset == camera_before, "destroyed group does not move the camera")
		game.current_world_drawables()
	check(game.control_groups.groups.get(1, []) == [], "dead IDs are removed")
	press(game, KEY_8)
	check(game.game_message == "Группа 8 пуста", "unassigned group also reports empty")
	var survivor := -1
	for unit in game.simulation_world.get_units():
		if int(unit.get("team", 0)) == game.local_player_team and float(unit.get("hp", 0)) > 0: survivor = int(unit["id"]); break
	check(survivor > 0, "fixture retains another local unit")
	var survivor_ids: Array[int] = [survivor]
	game.player_control_state.replace_or_add(survivor_ids, false)
	press(game, KEY_1, false, true)
	check(game.player_control_state.selected_ids() == [survivor], "Shift+1 preserves another living selection")
	press(game, KEY_1, true)
	check(game.control_groups.groups.get(1, []) == [survivor], "empty group can be reassigned")
	press(game, KEY_1)
	press(game, KEY_1)
	check(game.player_control_state.selected_ids() == [survivor], "reassigned group can be recalled and centered")
	game.free()
	return failures

func press(game: Node, key: Key, control: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	event.ctrl_pressed = control
	event.shift_pressed = shift
	game._unhandled_input(event)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
