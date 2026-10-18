extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Placement := preload("res://scripts/wall_placement.gd")
const Contract := preload("res://scripts/entity_read_contract.gd")
const Render := preload("res://scripts/render_world.gd")
const Coordinates := preload("res://scripts/coordinates.gd")
var failures: Array[String] = []
var catalog

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func make_world(civilization: int, level: int):
	var world = World.new(Vector2i(40,40))
	world.set_gamespec(catalog.gamespec_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.navigation_grid.configure_elevation(func(_cell): return 0)
	world.set_team_civilization(1,civilization)
	world.set_resource_amount(1,1,10000)
	world.set_resource_amount(1,2,10000)
	var technologies := [101,11]
	if level >= 1:
		technologies.append_array([102,13])
	if level >= 2:
		technologies.append_array([103,14])
	for technology in technologies:
		world.grant_technology(1,technology)
	world.fog_of_war.ensure_player(1)
	for y in range(40):
		for x in range(40):
			world.fog_of_war.reveal_explored_cell(1,Vector2i(x,y))
	return world

func test_junction(civilization: int, level: int, axis: int, walls_first: bool) -> void:
	var world = make_world(civilization,level)
	var expected: Array = [Vector2i(18,20),Vector2i(21,20)] if axis == 0 else [Vector2i(20,18),Vector2i(20,21)]
	var direction := Vector2i.RIGHT if axis == 0 else Vector2i.DOWN
	var label := "civ=%d level=%d axis=%d walls_first=%s" % [civilization,level,axis,walls_first]
	var near_cells: Array = [expected[0]-direction,expected[1]+direction]
	var far_cells: Array = [expected[0]-direction*2,expected[1]+direction*2]
	if walls_first:
		for index in range(2):
			world.add_building(200+index,"wall",Vector2(near_cells[index]))
			world.add_building(300+index,"wall",Vector2(far_cells[index]))
		check(world.can_place_foundation(1,"gate",Vector2(20,20),{"gate_axis":axis}),"gate fits gap with walls on both sides: "+label)
	var gate: Dictionary = world.add_building(100,"gate",Vector2(20,20),1,true,{"gate_axis":axis})
	check(Placement.connection_cells(gate) == expected,"ports are the two end tiles: "+label)
	if not walls_first:
		for index in range(2):
			check(world.can_place_foundation(1,"wall",Vector2(near_cells[index])),"wall can be built flush with gate pier: "+label)
			world.add_building(300+index,"wall",Vector2(far_cells[index]))
			var plan: Dictionary = world.plan_wall_line(1,[near_cells[index]])
			check(plan["entries"][0]["valid"],"public wall plan accepts pier neighbor: "+label)
			var expected_mask := 10 if axis == 0 else 5
			check(int(plan["entries"][0]["connection_mask"]) == expected_mask,"wall preview includes gate pier: "+label)
			world.add_building(200+index,"wall",Vector2(near_cells[index]))
	for index in range(2):
		var wall: Dictionary = world.find_building(200+index)
		check(int(wall["connection_mask"]) == (10 if axis == 0 else 5),"built wall matches preview: "+label)
		check(Vector2(wall["pos"]).distance_to(Vector2(expected[index])) == 1,"junction uses adjacent tile anchors: "+label)
	for pose in [0.0,0.5,1.0]:
		gate["gate_open_fraction"] = pose
		for projection in [gate,Contract.render(gate),Contract.render_reference(gate)]:
			var info: Dictionary = catalog.building_frame_info(projection,0)
			var hinges: Array = info.get("gate_occluders", [])
			for side in range(hinges.size()):
				var mount := Vector2(gate["pos"]) + Vector2(hinges[side]["start"])
				var pier := Vector2(expected[side])
				check(absf(mount.x-pier.x) <= 0.5 and absf(mount.y-pier.y) <= 0.5,"wooden hinge remains seated inside its masonry pier: "+label)
			var found: Array = []
			for part in info.get("composite_parts",[]):
				if part.has("gate_polygon"):
					continue
				var anchor := Vector2(gate["pos"])+Vector2(part.get("depth_world_offset",Vector2.ZERO))
				check(anchor == Vector2(expected[0]) or anchor == Vector2(expected[1]),"every masonry/flag/shadow part uses a real pier anchor: "+label)
				if anchor not in found:
					found.append(anchor)
			check(found.size() == 2,"both piers have render parts: "+label)
	# Walls alongside the opening must not treat wooden leaves as masonry.
	var flank: Vector2i = Vector2i(19,21) if axis == 0 else Vector2i(21,19)
	var isolated: Dictionary = world.add_building(400,"wall",Vector2(flank))
	check(int(isolated["connection_mask"]) == 0,"opening is not a wall socket: "+label)
	world.begin_entity_death(gate)
	world.refresh_building_connectivity()
	check(int(world.find_building(200)["connection_mask"]) != (10 if axis == 0 else 5),"destroyed gate releases wall connection: "+label)

func _initialize() -> void:
	catalog = Catalog.new()
	catalog.load()
	for civilization in [1,2,3,10,13]:
		for level in range(3):
			for axis in [0,1]:
				for walls_first in [false,true]:
					test_junction(civilization,level,axis,walls_first)
	for failure in failures:
		push_error(failure)
	print("Gate wall junction placement, preview, anchors and lifecycle: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
