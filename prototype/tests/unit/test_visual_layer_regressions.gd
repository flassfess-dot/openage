extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const Render := preload("res://scripts/render_world.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Main := preload("res://main.gd")
const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	test_farm(catalog)
	test_rowing(catalog)
	test_cliff_direction(catalog)
	test_edge_fog_mesh()
	for failure in failures: push_error(failure)
	print("Visual layers, native cliff placement, galley rowing: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func project(point: Vector2) -> Vector2:
	return Vector2((point.x-point.y)*32.0, (point.x+point.y)*16.0)
func test_farm(catalog) -> void:
	for team in [1, 2]:
		var farm := {"id": 100, "kind": "farm", "source_unit_id": 50, "team": team, "pos": Vector2(8,8), "hp": 50.0, "max_hp": 50.0, "harvestable": true, "amount": 250, "state": "complete"}
		var info: Dictionary = catalog.building_frame_info(farm)
		check("field" in String(info.get("asset_name", "")), "farm base is a separate field")
		var hut_parts: Array = info.get("composite_parts", []).filter(func(p): return "hut" in String(p.get("asset_name", "")))
		check(hut_parts.size()==1, "farm has exactly one independent hut")
		if hut_parts.is_empty(): continue
		var full = load("res://assets/generated/graphic_273_p%d.png" % team).get_image()
		var field: Image = info["texture"].get_image()
		var hut: Image = hut_parts[0]["texture"].get_image()
		check(field.get_size()==full.get_size() and hut.get_size()==full.get_size(), "split farm preserves canvas and source pivot")
		var mismatch := 0
		for y in range(full.get_height()):
			for x in range(full.get_width()):
				var a := field.get_pixel(x,y)
				var b := hut.get_pixel(x,y)
				if a.a>0 and b.a>0: mismatch+=1
				if full.get_pixel(x,y).a>0 and (a if a.a>0 else b) != full.get_pixel(x,y): mismatch+=1
		check(mismatch==0, "field plus hut reproduce every native farm pixel without overlap")
		for offset in [Vector2(-.5,-.5), Vector2(.7,.7), Vector2(2,-1)]:
			var worker := {"id": 1, "kind": "villager", "team": team, "hp": 25.0, "pos": farm["pos"]+offset, "previous_pos": farm["pos"]+offset, "death_phase": "alive"}
			var render = Render.new()
			var provider := func(kind, _data): return info if kind=="building" else {}
			var items: Array = render.create_world_drawables({"buildings": [farm], "units": [worker]}, project, 1.0, provider)
			for zoom in [1.0, 2.0, 3.0]:
				var projection := func(p): return project(p)*zoom+Vector2(200,150)
				render.refresh_world_drawables(items, projection, 1.0, true)
				var body: Dictionary = items.filter(func(i): return i["kind"]=="unit")[0]
				var field_item: Dictionary = items.filter(func(i): return i["kind"]=="building")[0]
				var hut_item: Dictionary = items.filter(func(i): return "hut" in String(i["frame_info"].get("asset_name", "")))[0]
				check(items.find(field_item)<items.find(body), "field stays below farmers at every zoom")
				check((items.find(body)<items.find(hut_item)) == (offset.x+offset.y<.1875), "hut occludes a worker behind it, while a foreground worker covers the hut")
		farm["amount"] = 0
		check(catalog.building_frame_info(farm).get("graphic_id")==148, "depleted farm uses native lifecycle art")
func test_rowing(catalog) -> void:
	for team in [1,2]:
		for facing in range(8):
			var unit := {"id": 7, "kind": "scout_ship", "source_unit_id": 20, "team": team, "facing": facing, "hp": 100.0, "max_hp": 100.0}
			var a: Dictionary = catalog.unit_frame_info(unit, "move", 0.0)
			var b: Dictionary = catalog.unit_frame_info(unit, "move", .28)
			check(a.get("texture")!=null and b.get("texture")!=null, "galley movement frames exist in every direction")
			if a.get("texture")==null: continue
			check(a["texture"].get_image().get_data()!=b["texture"].get_image().get_data(), "actual oar pixels move, not just the frame index")
			check(a["hotspot"]==b["hotspot"], "rowlocks keep the hull anchor stable")
			check(a.get("mirrored")==b.get("mirrored"), "row cycle retains the facing and mirroring")
			var idle_a: Dictionary = catalog.unit_frame_info(unit,"idle",0.0)
			var idle_b: Dictionary = catalog.unit_frame_info(unit,"idle",.28)
			check(idle_a["texture"]==idle_b["texture"], "stationary hull does not row")
func test_cliff_direction(catalog) -> void:
	var cells: Array = []
	for x in range(7,31): cells.append(Vector2i(x,18+posmod(x,3)-1))
	var terrain: Array[int] = []
	terrain.resize(40*40)
	terrain.fill(0)
	var levels: Array[int] = []
	levels.resize(41*41)
	levels.fill(0)
	var coast := PackedInt32Array()
	coast.resize(40*40)
	coast.fill(20)
	var ridges := Landscape.rock_ridges(Vector2i(40,40),terrain,[],{"vertex_levels":levels,"coast_distance":coast},cells,42)
	check(ridges["scenery"].size()>=6, "jittered source ridge assembles a complete native chain")
	var normal := -1.0
	for cliff in ridges["scenery"]:
		check(cliff["cliff_axis"]==Vector2i.RIGHT, "expanded neighboring footprints never rotate horizontal cliff art")
		check(cliff["source_frame"] in [1,2,18,19], "horizontal ridge uses horizontal source variants and terminals")
		if normal<0: normal=cliff["position"].y
		check(cliff["position"].y==normal, "all crest anchors share one native centreline")
		var info: Dictionary = catalog.environment_frame_info(cliff)
		check(info.get("texture")!=null, "grounded native cliff is loaded")
func test_edge_fog_mesh() -> void:
	var game = Main.new()
	game.map_size = Vector2i(8,8)
	game.simulation_world = World.new(game.map_size)
	var mesh: ArrayMesh = game._build_world_fog_mesh(Rect2i(-6,-6,20,6))
	var arrays := mesh.surface_get_arrays(0)
	for uv in arrays[Mesh.ARRAY_TEX_UV]:
		check(uv.x>=.0625 and uv.x<=.9375 and uv.y==.0625, "outside crowns sample nearest map-edge fog and never wrap")
	game.free()
