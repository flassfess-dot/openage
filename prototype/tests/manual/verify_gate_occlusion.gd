extends Node

const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Renderer := preload("res://scripts/render_world.gd")
const Presentation := preload("res://scripts/gate_presentation.gd")
const Placement := preload("res://scripts/wall_placement.gd")
const Contract := preload("res://scripts/entity_read_contract.gd")
const Definition := preload("res://scripts/match_definition.gd")
const MatchReady := preload("res://tests/support/match_ready.gd")
const Commands := preload("res://scripts/commands.gd")
var catalog
var failures: Array[String] = []
var checked_uvs: Dictionary = {}
var output_path := "res://qa/gate-occlusion/source/report.json"
var report := {"passed": false, "poses": 0, "side_probes": 0, "motion_frames": 0, "live_passed": false, "screenshots": []}

func _ready() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value and failures.size() < 80: failures.append(message)

func project(point: Vector2) -> Vector2:
	return Presentation.project(point)

func frame_info(kind: String, entity: Dictionary) -> Dictionary:
	return catalog.building_frame_info(entity, 0) if kind == "building" else catalog.unit_frame_info(entity, "idle", 0) if kind == "unit" else {}

func make_world(civilization: int, level: int):
	var world = World.new(Vector2i(40, 40))
	world.set_gamespec(catalog.gamespec_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.navigation_grid.configure_elevation(func(_cell): return 0)
	world.set_team_civilization(1, civilization)
	var technologies := [101, 11]
	if level >= 1: technologies.append_array([102, 13])
	if level >= 2: technologies.append_array([103, 14])
	for technology in technologies: world.grant_technology(1, technology)
	return world

func check_clean_uv(part: Dictionary, context: String) -> void:
	var texture: Texture2D = part.get("texture")
	if texture == null or part.get("gate_uv", PackedVector2Array()).is_empty(): return
	var key := str([texture.get_instance_id(), part["gate_uv"]])
	if checked_uvs.has(key): return
	checked_uvs[key] = true
	var image := texture.get_image()
	var polygon := PackedVector2Array()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for uv in part["gate_uv"]:
		var point := Vector2(uv) * texture.get_size()
		polygon.append(point)
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var blue := 0
	for y in range(maxi(0, floori(minimum.y)), mini(image.get_height(), ceili(maximum.y))):
		for x in range(maxi(0, floori(minimum.x)), mini(image.get_width(), ceili(maximum.x))):
			if not Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), polygon): continue
			var color := image.get_pixel(x, y)
			if color.a > 0 and color.b > color.r * 1.15 and color.b > color.g * 1.12 and color.b > 0.176:
				blue += 1
	check(blue == 0, context + ": slab UVs contain no blue cutout fragments (%d)" % blue)

func check_leaf_groups(items: Array, unit_id: int, context: String) -> void:
	var unit_items: Array = items.filter(func(item): return item.get("stable_id") == unit_id and item.get("kind") in ["unit", "unit_part"])
	for leaf in [0, 1]:
		var pieces: Array = items.filter(func(item): return item.get("frame_info", {}).get("gate_leaf", -1) == leaf)
		check(pieces.size() == 3, context + ": leaf has front, top and end")
		if pieces.is_empty(): continue
		var depth: float = pieces[0]["screen_y"]
		var first: int = items.find(pieces[0])
		var last: int = first
		for piece in pieces:
			check(is_equal_approx(depth, float(piece["screen_y"])), context + ": all faces share exactly one depth")
			first = mini(first, items.find(piece))
			last = maxi(last, items.find(piece))
		for unit in unit_items:
			var index: int = items.find(unit)
			check(index < first or index > last, context + ": no rider part is inserted between the wooden faces")

func check_matrix() -> void:
	for civilization in [1, 2, 3, 10, 13]:
		for level in range(3):
			var world = make_world(civilization, level)
			var rider: Dictionary = world.add_unit(1, "cavalry", Vector2(20, 23), false)
			for axis in [0, 1]:
				var gate: Dictionary = world.add_building(9000 + axis, "gate", Vector2(20, 20), 1, true, {"gate_axis": axis})
				for pose in range(8):
					gate["gate_open_fraction"] = float(pose) / 7.0
					var context := "civ=%d tier=%d axis=%d pose=%d" % [civilization, level, axis, pose]
					var info: Dictionary = catalog.building_frame_info(gate, 0)
					for part in info["composite_parts"]: check_clean_uv(part, context)
					var pier: Vector2i = Placement.connection_cells(gate)[1]
					var pier_depth: float = project(Vector2(pier)).y
					for part in info["composite_parts"]:
						if part.get("gate_hinge", -1) == 1:
							check(project(Vector2(gate["pos"]) + Vector2(part["depth_world_offset"])).y < pier_depth, context + ": near pier hides the inner hinge mount")
					var renderer := Renderer.new()
					var items: Array = renderer.create_world_drawables({"buildings": [gate], "units": [rider]}, Callable(self, "project"), 1.0, Callable(self, "frame_info"))
					check_leaf_groups(items, int(rider["id"]), context)
					if pose == 7:
						for leaf in [0, 1]:
							var occluder: Dictionary = info["gate_occluders"][leaf]
							var start := Vector2(gate["pos"]) + Vector2(occluder["start"])
							var end := Vector2(gate["pos"]) + Vector2(occluder["end"])
							var normal := (end-start).orthogonal().normalized()
							if normal.dot(Vector2.ONE) < 0: normal = -normal
							for along in [0.15, 0.5, 0.85]:
								for side in [-1, 1]:
									var point: Vector2 = start.lerp(end, along) + normal * side * 0.35
									var probe: Dictionary = rider.duplicate()
									probe["pos"] = point
									probe["previous_pos"] = point - normal * side * 0.1
									items = renderer.create_world_drawables({"buildings": [gate], "units": [probe]}, Callable(self, "project"), 1.0, Callable(self, "frame_info"))
									for alpha in [1.0, 0.5]:
										renderer.refresh_world_drawables(items, Callable(self, "project"), alpha, true)
										check_leaf_groups(items, int(rider["id"]), context)
										var body: Dictionary = items.filter(func(item): return item["kind"] == "unit")[0]
										var faces: Array = items.filter(func(item): return item.get("frame_info", {}).get("gate_leaf", -1) == leaf)
										for face in faces: check((items.find(body) > items.find(face)) == (side > 0), context + ": rider stays on its physical side of the open leaf after interpolation")
									report["side_probes"] += 1
					report["poses"] += 1

func check_live() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	for sample in range(4):
		var axis := sample % 2
		var level := int(sample / 2)
		var game = load("res://main.tscn").instantiate()
		var definition := Definition.load_json("res://tests/fixtures/e3_save_state_matrix_match.json")
		definition["players"][0]["color_index"] = 4
		game.match_definition_override = definition
		get_tree().root.add_child(game)
		if not await MatchReady.wait_for_ready(get_tree(), game):
			failures.append("live gate scene never became ready")
			game.free()
			return
		game.game_controller.set_paused(true)
		game.set_process(false)
		var world = game.simulation_world
		for technology in ([101,11] if level == 0 else [101,11,102,13]): world.grant_technology(1, technology)
		var target := Vector2(-1, -1)
		for y in range(8, world.map_size.y-5):
			for x in range(8, world.map_size.x-5):
				var position := Vector2(x, y)
				if world.can_place_foundation(1, "gate", position, {"gate_axis":axis}):
					target = position
					break
			if target.x >= 0: break
		check(target.x >= 0, "live fixture has a legal gate location")
		if target.x < 0:
			game.free()
			return
		var gate: Dictionary = world.add_building(9500, "gate", target, 1, true, {"gate_axis":axis})
		var piers := Placement.connection_cells(gate)
		var along := Vector2i.RIGHT if axis == 0 else Vector2i.DOWN
		for end in range(2):
			for distance in [1, 2]: world.add_building(9600+end*2+distance, "wall", Vector2(Vector2i(piers[end])+along*distance*(-1 if end == 0 else 1)))
		gate["gate_open_fraction"] = 1.0
		world.gate_system.set_mode([int(gate["id"])], 1, "open")
		world.sync_building_navigation_occupancy(gate)
		var rider: Dictionary = world.add_unit(1, "cavalry", Placement.masonry_center(gate)+Vector2(0, 2), true)
		game.resource_catalog.prewarm_match_entities([rider],[gate])
		var selected: Array[int] = [int(rider["id"])]
		game.player_control_state.replace_or_add(selected, false)
		game.view_zoom = 2.5
		game.center_view_on_world(Placement.masonry_center(gate)+Presentation.orient(Vector2(0, 0.5),axis))
		game.message_time = 0
		var info: Dictionary = game.resource_catalog.building_frame_info(gate, 0)
		var right: Dictionary = info["gate_occluders"][1]
		var start: Vector2 = Vector2(gate["pos"])+Vector2(right["start"])
		var end: Vector2 = Vector2(gate["pos"])+Vector2(right["end"])
		var normal := (end-start).orthogonal().normalized()
		if normal.dot(Vector2.ONE) < 0: normal = -normal
		for side in [-1, 1]:
			var point: Vector2 = start.lerp(end,0.75)+normal*side*0.4
			world.set_entity_field(rider,"pos",point)
			world.set_entity_field(rider,"previous_pos",point)
			world.update_fog_of_war()
			game.sync_world_state()
			game.refresh_hud_model()
			await capture(game,"level-%d-axis-%d-rider-%s" % [level,axis,"behind" if side < 0 else "front"])
		# Actual movement through the opening in both directions, rather than
		# relying on one successful static pose.
		var crossing := Presentation.orient(Vector2(0,1),axis)
		var center := Placement.masonry_center(gate)
		world.set_entity_field(rider,"pos",center-crossing*2.0)
		world.set_entity_field(rider,"previous_pos",center-crossing*2.0)
		world.assign_command_move([rider],center+crossing*3.0)
		for direction in [1,-1]:
			if direction < 0: world.assign_command_move([rider],center-crossing*2.0)
			for step in range(18):
				for tick in range(5):
					world.update_units(0.05,1,2)
				game.sync_world_state()
				game.current_world_drawables()
				var items: Array = game.current_world_drawables()
				check_leaf_groups(items,int(rider["id"]),"actual cavalry crossing")
				game.queue_redraw()
				await get_tree().process_frame
				if step in [3,7,11]: await capture(game,"level-%d-axis-%d-walk-%d-%d" % [level,axis,direction,step])
				report["motion_frames"] += 1
			check((Vector2(rider["pos"])-center).dot(crossing)*direction > 0.8,"actual cavalry crossed the gate in direction %d" % direction)
		game.free()
	report["live_passed"] = true

func capture(game, label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	game.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output_path.get_base_dir().path_join(label+".png")
	check(get_tree().root.get_texture().get_image().save_png(path) == OK, "captures real gate/rider frame")
	report["screenshots"].append(ProjectSettings.globalize_path(path))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	report["release"] = not OS.has_feature("editor")
	if "--require-release" in OS.get_cmdline_user_args(): check(report["release"],"uses the real Release runtime")
	catalog = Catalog.new()
	catalog.load()
	check_matrix()
	check(int(report["poses"]) == 240, "all style/tier/axis/pose combinations completed")
	if failures.is_empty(): await check_live()
	check(bool(report["live_passed"]),"all live scenes and motion probes completed")
	report["passed"] = failures.is_empty()
	report["failures"] = failures
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t"))
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Gate occlusion PASSED: 240 poses, physical rider sides, coherent leaves, hidden near hinges and clean UVs")
	get_tree().quit(0 if failures.is_empty() else 1)
