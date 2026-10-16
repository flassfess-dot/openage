extends SceneTree
const Commands := preload("res://scripts/commands.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _initialize() -> void:
	root.size = Vector2i(1280,720)
	var game = load("res://main.tscn").instantiate()
	game.match_path = "res://tests/fixtures/e3_save_state_matrix_match.json"
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var world = game.simulation_world
	for technology in [101,11,102,13]:
		world.grant_technology(1,technology)
	for resource in range(4):
		world.set_resource_amount(1,resource,10000)
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):
			world.fog_of_war.reveal_explored_cell(1,Vector2i(x,y))
	var worker: Dictionary = world.get_units().filter(func(unit): return int(unit["team"]) == 1 and world.entity_is_worker(unit))[0]
	var selected: Array[int] = [int(worker["id"])]
	game.player_control_state.replace_or_add(selected,false)
	game.sync_world_state()
	game.refresh_hud_model()
	check(game.hud_model["commands"].any(func(command): return command.get("type") == "build" and command.get("id") == "gate" and command.get("icon_kind") == "gate"),"gate has its own build menu icon")
	check(game.hud_controls.set_build_menu_open(true),"construction menu opens")
	var commands: Array = game.hud_controls.active_train_commands
	var gate_index := -1
	for index in range(commands.size()):
		if commands[index].get("type") == "build" and commands[index].get("id") == "gate":
			gate_index = index
	check(gate_index >= 0,"gate appears in construction palette")
	if gate_index >= 0:
		game.hud_controls._on_action_pressed(gate_index)
	check(game.pending_build_kind == "gate","construction button starts gate placement")
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	game._input(key)
	check(game.pending_gate_axis == 1,"Tab turns gate even while a HUD control has focus")
	var target := Vector2(-1,-1)
	for y in range(8,world.map_size.y-4):
		for x in range(5,world.map_size.x-4):
			var position := Vector2(x,y)
			var wall_sites: Array = [position+Vector2(0,-4),position+Vector2(0,-3),position+Vector2(0,2),position+Vector2(0,3)]
			if world.can_place_foundation(1,"gate",position,{"gate_axis":1}) and wall_sites.all(func(site): return world.can_place_foundation(1,"wall",site)):
				target = position
				break
		if target.x >= 0:
			break
	check(target.x >= 0,"fixture has legal rotated gate location")
	if target.x >= 0:
		game.commit_build_placement(game.world_to_screen(target))
		game.game_controller.tick_index += 1
		game.game_controller.process_commands()
		var gates: Array = world.get_buildings().filter(func(building): return building["kind"] == "gate")
		check(gates.size() == 1,"mouse placement reserves exactly one gate")
		if not gates.is_empty():
			var gate: Dictionary = gates[0]
			check(int(gate["gate_axis"]) == 1,"placement carries selected direction")
			check(Vector2(gate["pos"]).is_equal_approx(target),"mouse placement uses the chosen target: expected %s, got %s" % [target,gate["pos"]])
			world.complete_foundation(gate)
			for side in [[-4,-3],[2,3]]:
				var wall_command = Commands.BuildCommand.new(game.game_controller.tick_index+1,[int(worker["id"])],"wall",target)
				wall_command.params["wall_cells"] = [Vector2i(target)+Vector2i(0,side[0]),Vector2i(target)+Vector2i(0,side[1])]
				game.game_controller.enqueue_command(wall_command,true,1)
				game.game_controller.tick_index += 1
				game.game_controller.process_commands()
				check(bool(game.game_controller.get_command_result(wall_command.sequence_id).get("accepted",false)),"public wall drag attaches to gate")
			for offset in [-4,-3,2,3]:
				var expected_position := target+Vector2(0,offset)
				check(world.get_buildings().any(func(building): return building["kind"] == "wall" and Vector2(building["pos"]).is_equal_approx(expected_position)),"public drag reserves wall at %s next to gate %s" % [expected_position,gate["pos"]])
			for wall in world.get_buildings().filter(func(building): return building["kind"] == "wall" and building["state"] == "foundation"):
				world.complete_foundation(wall)
			var stop_building = Commands.StopCommand.new(game.game_controller.tick_index+1,[int(worker["id"])])
			game.game_controller.enqueue_command(stop_building,true,1)
			game.game_controller.tick_index += 1
			game.game_controller.process_commands()
			selected = [int(gate["id"])]
			game.player_control_state.replace_or_add(selected,false)
			game.sync_world_state()
			game.refresh_hud_model()
			check(game.hud_model["commands"].filter(func(command): return String(command.get("id","")).begins_with("gate_")).size() == 3,"selected gate exposes three controls")
			await capture_scene(game,gate,"closed")
			game.issue_unit_action("gate_open")
			game.game_controller.tick_index += 1
			game.game_controller.process_commands()
			check(gate["gate_mode"] == "open","gate control reaches simulation")
			world.gate_system.advance(1.0)
			game.sync_world_state()
			game.refresh_hud_model()
			check(game.hud_model["commands"].any(func(command): return command.get("id") == "gate_open" and command.get("active",false)),"HUD refreshes active gate mode")
			var info: Dictionary = game.resource_catalog.building_frame_info(gate,0)
			check(info.get("composite_parts",[]).any(func(part): return part.has("gate_polygon")),"main scene receives volume gate geometry")
			await capture_scene(game,gate,"open")
			check(game.save_game_to_path("res://qa/gate-main-save.json"),"main scene saves gate")
			check(game.load_game_from_path("res://qa/gate-main-save.json"),"main scene loads gate")
			gate = game.simulation_world.find_building(int(selected[0]))
			check(gate != null and gate["gate_mode"] == "open" and int(gate["gate_axis"]) == 1,"loaded game retains gate controls and direction")
	game.free()
	if failures.is_empty():
		print("Gate main scene palette, rotation, placement, HUD and save/load tests passed")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func capture_scene(game, gate: Dictionary, pose: String) -> void:
	if "--capture-main-gates" not in OS.get_cmdline_user_args():
		return
	game.view_zoom = 2.0
	game.center_view_on_world(Vector2(gate["pos"]))
	for step in range(30):
		game._process(0.0)
		game.queue_redraw()
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://qa/gates/main-%s.png" % pose)
