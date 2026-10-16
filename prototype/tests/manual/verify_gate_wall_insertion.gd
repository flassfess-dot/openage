extends Node

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Placement := preload("res://scripts/wall_placement.gd")
const Footprint := preload("res://scripts/footprint.gd")
const Picking := preload("res://scripts/picking_service.gd")
const Contract := preload("res://scripts/entity_read_contract.gd")
const Definition := preload("res://scripts/match_definition.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Orders := preload("res://scripts/order_pipeline.gd")

var catalog
var failures: Array[String] = []
var output_path := "res://qa/gate-insertion/source/report.json"
var report := {"passed": false, "matrix_cases": 0, "rejection_cases": 0, "live_passed": false, "screenshots": []}

func _ready() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func make_world(civilization: int = 3, level: int = 0):
	var world = World.new(Vector2i(40, 40))
	world.set_gamespec(catalog.gamespec_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.navigation_grid.configure_elevation(func(_cell): return 0)
	world.set_team_civilization(1, civilization)
	for resource in range(4): world.set_resource_amount(1, resource, 10000)
	var technologies := [101, 11]
	if level >= 1: technologies.append_array([102, 13])
	if level >= 2: technologies.append_array([103, 14])
	for technology in technologies: world.grant_technology(1, technology)
	world.fog_of_war.ensure_player(1)
	for y in range(40):
		for x in range(40): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
	return world

func line(world, axis: int, center: Vector2 = Vector2(20, 20)) -> Array[int]:
	var ids: Array[int] = []
	for offset in range(-4, 4):
		var position: Vector2 = center + (Vector2(offset, 0) if axis == 0 else Vector2(0, offset))
		var wall: Dictionary = world.add_building(1000 + offset + 4, "wall", position)
		ids.append(int(wall["id"]))
	return ids

func check_geometry(gate: Dictionary, axis: int, label: String) -> void:
	var occupied: Array = gate["occupied_cells"]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for cell in occupied:
		minimum = minimum.min(Vector2(cell) - Vector2.ONE * 0.5)
		maximum = maximum.max(Vector2(cell) + Vector2.ONE * 0.5)
	var expected := PackedVector2Array([minimum, Vector2(maximum.x, minimum.y), maximum, Vector2(minimum.x, maximum.y)])
	for projection in [gate, Contract.render(gate), Contract.render_reference(gate)]:
		check(Placement.selection_polygon(projection) == expected, label + ": outline follows the exact four tile squares")
	var picking := Picking.new()
	var project := func(point): return point
	var near_point: Vector2 = minimum + (Vector2(0.15, 0.5) if axis == 0 else Vector2(0.5, 0.15))
	var far_point: Vector2 = maximum + (Vector2(0.15, -0.5) if axis == 0 else Vector2(-0.5, 0.15))
	check(picking.footprint_hit(near_point, "foundation", gate, project, 1.0), label + ": formerly missed half-tile is selectable")
	check(not picking.footprint_hit(far_point, "foundation", gate, project, 1.0), label + ": stale half-tile no longer selects the gate")

func check_matrix() -> void:
	for civilization in [1, 2, 3, 10, 13]:
		for level in range(3):
			for axis in [0, 1]:
				var world = make_world(civilization, level)
				var walls := line(world, axis)
				var label := "civ=%d level=%d axis=%d" % [civilization, level, axis]
				var revision: int = world.navigation_grid.revision
				check(world.can_place_foundation(1, "gate", Vector2(20, 20), {"gate_axis": axis}), label + ": existing wall accepts a gate")
				check(world.navigation_grid.revision == revision and world.buildings.size() == 8, label + ": preview never removes walls")
				var wood: int = world.get_resource_amount(1, 1)
				var stone: int = world.get_resource_amount(1, 2)
				var cost: Dictionary = world.building_cost("gate", 1)
				var gate: Variant = world.place_foundation(1, "gate", Vector2(20, 20), [], {"gate_axis": axis})
				check(gate != null, label + ": replaces the wall with a real foundation")
				if gate == null: continue
				check(world.get_resource_amount(1, 1) == wood - int(cost.get(1, 0)) and world.get_resource_amount(1, 2) == stone - int(cost.get(2, 0)), label + ": charges the normal gate cost exactly once")
				for index in range(8):
					var survives: bool = index not in [2, 3, 4, 5]
					check((world.find_building(walls[index]) != null) == survives, label + ": removes exactly the covered four walls")
					if not survives: check(not world.conquest_tracked_by_id.has(walls[index]), label + ": no phantom conquest presence")
				check(world.buildings.size() == 5, label + ": no overlapping or dead wall sprites remain")
				for cell in gate["occupied_cells"]:
					var occupants: Array = world.navigation_grid.occupants(cell)
					check(occupants.size() == 1 and int(occupants[0]["id"]) == int(gate["id"]), label + ": foundation alone occupies its tiles")
				for stage in range(4):
					gate["construction_stage"] = stage
					check_geometry(gate, axis, label + " stage=%d" % stage)
				world.complete_foundation(gate)
				check_geometry(gate, axis, label + " complete")
				check(world.gate_system.set_mode([int(gate["id"])], 1, "open") == "", label + ": inserted gate accepts open mode")
				for tick in range(10): world.gate_system.advance(0.1)
				for cell in gate["gate_passage_cells"]: check(world.navigation_grid.occupants(cell).is_empty(), label + ": open passage has no stale wall obstruction")
				for id in [walls[1], walls[6]]:
					check(int(world.find_building(id)["connection_mask"]) == (10 if axis == 0 else 5), label + ": neighboring wall meets the new pier")
				report["matrix_cases"] += 1

func check_rejections() -> void:
	for reason in ["enemy", "ally", "foundation", "house", "unit", "resources"]:
		var world = make_world()
		var walls := line(world, 0)
		var victim: Dictionary = world.find_building(walls[3])
		match reason:
			"enemy", "ally":
				victim["team"] = 2
				if reason == "ally": world.player_registry.set_relation(1, 2, "ally")
			"foundation": victim["state"] = "foundation"
			"house": world.add_building(2001, "house", Vector2(20, 20))
			"unit": world.add_unit(1, "villager", Vector2(19.5, 20.5), false)
			"resources": world.set_resource_amount(1, 1, 0)
		var wood: int = world.get_resource_amount(1, 1)
		var revision: int = world.navigation_grid.revision
		check(world.place_foundation(1, "gate", Vector2(20, 20), [], {"gate_axis": 0}) == null, "rejects " + reason)
		check(world.get_resource_amount(1, 1) == wood and world.navigation_grid.revision == revision, reason + ": rejection does not charge or mutate navigation")
		for id in walls: check(world.find_building(id) != null, reason + ": rejection preserves every wall")
		report["rejection_cases"] += 1

func check_replay_and_full_queue() -> void:
	var first = make_world()
	var second = make_world()
	line(first, 0)
	line(second, 0)
	var worker: Dictionary = first.add_unit(1, "villager", Vector2(20, 16), false)
	second.add_unit(1, "villager", Vector2(20, 16), false)
	var controller := Controller.new(first)
	var replay_controller := Controller.new(second)
	var recorder = controller.start_recording(731, false)
	second.set_simulation_seed(731)
	var command = Commands.BuildCommand.new(0, [int(worker["id"])], "gate", Vector2(20, 20))
	command.params["gate_axis"] = 0
	controller.enqueue_command(command, true, 1)
	controller.process_commands()
	check(bool(controller.get_command_result(command.sequence_id).get("accepted", false)), "public insertion command is recorded")
	var decoded = recorder.command_from_record(recorder.command_records[0])
	replay_controller.enqueue_command(decoded, false, 1)
	replay_controller.process_commands()
	check(recorder.world_state_hash(first, 0, controller) == recorder.world_state_hash(second, 0, replay_controller), "replayed insertion produces the exact same authoritative state")
	var world = make_world()
	var walls := line(world, 0)
	var busy: Dictionary = world.add_unit(1, "villager", Vector2(20, 16), false)
	for index in range(Orders.MAX_QUEUED_ORDERS): world.append_entity_queued_order(busy, {"type": "move", "params": {}})
	var queued_controller := Controller.new(world)
	var queued = Commands.BuildCommand.new(0, [int(busy["id"])], "gate", Vector2(20, 20))
	queued.params["plan_only"] = true
	queued_controller.enqueue_command(queued, true, 1)
	queued_controller.process_commands()
	check(not bool(queued_controller.get_command_result(queued.sequence_id).get("accepted", true)), "a full Shift queue rejects insertion before wall replacement")
	for id in walls: check(world.find_building(id) != null, "a full Shift queue preserves the wall")
	check(int(world.get_resource_amount(1, 1)) == 10000, "a full Shift queue does not charge the gate")
	report["replay_and_queue_passed"] = true

func check_live_scene() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	for axis in [0, 1]:
		var game = load("res://main.tscn").instantiate()
		game.match_definition_override = Definition.load_json("res://tests/fixtures/e3_save_state_matrix_match.json")
		get_tree().root.add_child(game)
		if not await MatchReady.wait_for_ready(get_tree(), game):
			failures.append("live match did not become ready")
			game.free()
			return
		game.game_controller.set_paused(true)
		var world = game.simulation_world
		for technology in [101, 11]: world.grant_technology(1, technology)
		for resource in range(4): world.set_resource_amount(1, resource, 10000)
		for y in range(world.map_size.y):
			for x in range(world.map_size.x): world.fog_of_war.reveal_explored_cell(1, Vector2i(x, y))
		var target := Vector2(-1, -1)
		for y in range(8, world.map_size.y - 4):
			for x in range(8, world.map_size.x - 4):
				var point := Vector2(x, y)
				var sites: Array = []
				for offset in range(-4, 4): sites.append(point + (Vector2(offset, 0) if axis == 0 else Vector2(0, offset)))
				if world.can_place_foundation(1, "gate", point, {"gate_axis": axis}) and sites.all(func(site): return world.can_place_foundation(1, "wall", site)):
					target = point
					break
			if target.x >= 0: break
		check(target.x >= 0, "live fixture has room for a complete wall line")
		if target.x < 0:
			game.free()
			return
		var walls := line(world, axis, target)
		var worker: Dictionary = world.get_units().filter(func(unit): return unit["team"] == 1 and world.entity_is_worker(unit))[0]
		var workers: Array[int] = [int(worker["id"])]
		game.player_control_state.replace_or_add(workers, false)
		game.sync_world_state()
		game.refresh_hud_model()
		game.begin_build_placement("gate")
		game.pending_gate_axis = axis
		game.commit_build_placement(game.world_to_screen(target))
		game.game_controller.tick_index += 1
		game.game_controller.process_commands()
		var gates: Array = world.get_buildings().filter(func(building): return building["kind"] == "gate")
		check(gates.size() == 1, "public mouse placement embeds one gate in the existing wall")
		if gates.size() != 1:
			game.free()
			return
		var gate: Dictionary = gates[0]
		game.select_hud_building(int(gate["id"]))
		game.view_zoom = 1.6
		game.center_view_on_world(Placement.masonry_center(gate))
		game.interaction_highlight_id = int(gate["id"])
		game.interaction_cursor_semantic = "select"
		game.message_time = 0
		for stage in [0, 2, 3]:
			world.set_entity_field(gate, "construction_stage", stage)
			world.set_entity_field(gate, "construction_progress", float(stage) / 4.0)
			game.sync_world_state()
			game.refresh_hud_model()
			var expected_world := Placement.selection_polygon(gate)
			var outline: PackedVector2Array = game.building_selection_outline(gate)
			check(outline.size() == 5 and outline[0] == outline[4], "main outline is a closed polygon")
			for index in range(4): check(outline[index] == PixelScaling.snap_screen(game.world_to_screen(expected_world[index])), "actual main outline uses the corrected tile center")
			await capture(game, "axis-%d-stage-%d" % [axis, stage])
		var save_path := output_path.get_base_dir().path_join("axis-%d-save.json" % axis)
		check(game.save_game_to_path(save_path, "Gate wall insertion verification"), "saves the inserted gate under construction")
		check(game.load_game_from_path(save_path), "loads the inserted gate without resurrecting walls")
		if not await MatchReady.wait_for_ready(get_tree(), game):
			failures.append("loaded insertion fixture did not become ready")
			game.free()
			return
		var loaded: Dictionary = game.simulation_world.get_buildings().filter(func(building): return building["kind"] == "gate")[0]
		check_geometry(loaded, axis, "loaded inserted gate")
		for index in [2, 3, 4, 5]: check(game.simulation_world.find_building(walls[index]) == null, "replaced wall stays removed after loading")
		game.free()
	report["live_passed"] = true

func capture(game, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output_path.get_base_dir().path_join(label + ".png")
	check(get_tree().root.get_texture().get_image().save_png(path) == OK, "captures the real gate outline")
	report["screenshots"].append(ProjectSettings.globalize_path(path))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	report["release"] = not OS.has_feature("editor")
	if "--require-release" in OS.get_cmdline_user_args(): check(report["release"], "runs the exported Release")
	catalog = Catalog.new()
	catalog.load()
	check_matrix()
	check_rejections()
	check_replay_and_full_queue()
	check(bool(report.get("replay_and_queue_passed", false)), "replay and Shift queue scenarios completed")
	check(int(report["matrix_cases"]) == 30, "all matrix cases completed")
	check(int(report["rejection_cases"]) == 6, "all rejection cases completed")
	if failures.is_empty(): await check_live_scene()
	check(bool(report["live_passed"]), "every live placement and save/load scenario completed")
	report["passed"] = failures.is_empty()
	report["failures"] = failures
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Gate insertion and selection PASSED: 30 architectural/tier/axis cases, rejection safety, real mouse placement and save/load")
	get_tree().quit(0 if failures.is_empty() else 1)
