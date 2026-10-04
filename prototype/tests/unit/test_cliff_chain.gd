extends SceneTree
const Chain := preload("res://scripts/cliff_chain.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var catalog = Catalog.new()
	catalog.load()
	test_direction_and_terminals()
	test_corners_and_order(catalog)
	test_corner_seam_pixels(catalog)
	test_corner_cache_refresh(catalog)
	test_isolated_and_junction(catalog)
	test_generated_turns()
	for failure in failures: push_error(failure)
	print("Native cliff axes, both terminals and inner/outer corners: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func scenery(points: Array) -> Array:
	var items: Array = []
	for point in points:
		items.append({"kind": "cliff", "graphic_id": 107, "asset_name": "cliff_grounded", "position": Vector2(point) + Vector2(0.5, 0.5), "source_elevation": 2.0})
	return items

func test_direction_and_terminals() -> void:
	var x := scenery([Vector2i(7, 13), Vector2i(10, 13), Vector2i(13, 13)])
	var y := scenery([Vector2i(13, 7), Vector2i(13, 10), Vector2i(13, 13)])
	Chain.apply(x)
	Chain.apply(y)
	check(x.map(func(i): return i["source_frame"]) == [18, 1, 19], "X chain joins NW-SE with the left and right original terminals")
	check(y.map(func(i): return i["source_frame"]) == [17, 4, 16], "Y chain joins NE-SW with terminals in the reverse frame order")
	check(x[0]["cliff_piece"] == "left_end" and x[2]["cliff_piece"] == "right_end", "X terminal sides agree with their screen position")
	check(y[0]["cliff_piece"] == "right_end" and y[2]["cliff_piece"] == "left_end", "Y terminal sides agree with their screen position")
	check(x[0]["position"] == Vector2(7.5, 13.5) and y[0]["position"] == Vector2(13.5, 7.5), "terminals keep their navigation anchors without an extra cell shift")
	Chain.apply(x, {Vector2i(10, 13): 1})
	Chain.apply(y, {Vector2i(13, 10): 1})
	check(x[1]["source_frame"] == 2 and y[1]["source_frame"] == 5, "both straight variants preserve the same connections")

func test_corners_and_order(catalog) -> void:
	var points := [Vector2i(7, 13), Vector2i(10, 13), Vector2i(10, 10), Vector2i(13, 10)]
	var items := scenery(points)
	Chain.apply(items)
	check(items.map(func(i): return i["source_frame"]) == [18, 3, 15, 19], "a staircase uses the outer and inner source corners, with correct ends")
	check(items[1]["cliff_piece"] == "outer_corner" and items[1]["cliff_connections"] == 3, "outer corner joins its left and upper neighbors")
	check(items[1]["cliff_screen_offset"] == Vector2(0, -5) and items[2]["cliff_screen_offset"] == Vector2.ZERO, "only the outer corner has the native join correction")
	check(items[2]["cliff_piece"] == "inner_corner" and items[2]["cliff_connections"] == 12, "inner corner joins its right and lower neighbors")
	var reversed := items.duplicate(true)
	reversed.reverse()
	Chain.apply(reversed)
	reversed.reverse()
	check(reversed == items, "piece selection does not depend on chain traversal or draw order")
	for item in items:
		var info: Dictionary = catalog.environment_frame_info(item)
		check(info.get("texture") != null and info["texture"].get_width() > 100, "every corner and terminal has actual populated native art")
		check(not bool(info.get("mirrored", false)), "cliff sprites stay upright in their original lighting")
		check(item["source_elevation"] == 2.0, "topology binding preserves source elevation")

# Composite the real native textures, including their hotspots and renderer
# offsets. The five-pixel bands straddle both joins inside the cliff face:
# grass showing through here is a seam, rather than the feathered ground skirt.
func test_corner_seam_pixels(catalog) -> void:
	for left_frame in [1, 2]:
		for right_frame in [4, 5]:
			var canvas := Image.create(400, 200, false, Image.FORMAT_RGBA8)
			canvas.fill(Color.TRANSPARENT)
			var items := scenery([Vector2i(-3, 0), Vector2i(0, -3), Vector2i.ZERO])
			Chain.apply(items)
			items[0]["source_frame"] = left_frame
			items[1]["source_frame"] = right_frame
			for item in items:
				var info: Dictionary = catalog.environment_frame_info(item)
				var texture: Texture2D = info["texture"]
				var pixels := texture.get_image()
				pixels.convert(Image.FORMAT_RGBA8)
				var center := Vector2i(Vector2(item["position"]).floor())
				var anchor := Vector2((center.x - center.y) * 32, (center.x + center.y) * 16)
				var destination := Vector2i(Vector2(200, 100) + anchor - info["hotspot"] + info.get("screen_offset", Vector2.ZERO))
				canvas.blend_rect(pixels, Rect2i(Vector2i.ZERO, pixels.get_size()), destination)
			var solid := true
			for side in [-1, 1]:
				for distance in range(20, 81, 2):
					for dy in range(-4, 1):
						var pixel := Vector2i(200 + distance * side, 100 - 48 + distance / 2 + dy)
						if canvas.get_pixelv(pixel).a < 0.99: solid = false
			check(solid, "outer corner joins both straight variants without transparent pixels inside the rock face (%d/%d)" % [left_frame, right_frame])


func test_corner_cache_refresh(catalog) -> void:
	var renderer = preload("res://scripts/render_world.gd").new()
	var items := scenery([Vector2i(10, 10)])
	items[0]["id"] = -700001
	items[0]["source_frame"] = 3
	var project := func(position: Vector2) -> Vector2: return Vector2((position.x - position.y) * 32.0, (position.x + position.y) * 16.0)
	var provide := func(_kind: String, item: Dictionary) -> Dictionary: return catalog.environment_frame_info(item)
	var before: Dictionary = renderer._snapshot_environment_drawables(items, project, provide)
	check(before["static"][0]["frame_info"]["screen_offset"] == Vector2.ZERO, "imported source cliffs retain their original anchor")
	items[0]["cliff_screen_offset"] = Vector2(0, -5)
	var after: Dictionary = renderer._snapshot_environment_drawables(items, project, provide)
	check(after["static"][0]["frame_info"]["screen_offset"] == Vector2(0, -5), "changing the corner binding invalidates the retained rendering record")
	check(after["static"][0]["world_anchor"] == Vector2(10.5, 10.5), "a drawing correction never moves the navigation anchor")


func test_isolated_and_junction(catalog) -> void:
	var isolated := scenery([Vector2i(10, 10)])
	Chain.apply(isolated)
	check(isolated[0]["source_frame"] == 24 and isolated[0]["cliff_piece"] == "isolated", "a lone rock uses the dedicated isolated frame")
	var nearby: Dictionary = {Vector2i(11, 10): true, Vector2i(10, 11): true}
	check(Chain.connections_at(Vector2i(10, 10), nearby) == 0, "expanded footprint cells do not masquerade as connected crest centers")
	for ports in [6, 9, 7, 15]:
		var item: Dictionary = Chain.piece(ports)
		item.merge({"kind": "cliff", "graphic_id": 107, "asset_name": "cliff_grounded"})
		var info: Dictionary = catalog.environment_frame_info(item)
		check(item["source_frame"] == 24 and info.get("texture") != null and info["texture"].get_width() > 100, "unsupported source joins never select transparent source frames")

func test_generated_turns() -> void:
	var size := Vector2i(64, 64)
	var terrain: Array[int] = []
	terrain.resize(size.x * size.y)
	terrain.fill(0)
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	levels.fill(2)
	var coast := PackedInt32Array()
	coast.resize(size.x * size.y)
	coast.fill(20)
	var fields := {"vertex_levels": levels, "coast_distance": coast}
	var corner_found := false
	for seed_value in range(32):
		var ridges := Landscape.rock_ridges(size, terrain, [], fields, [], seed_value)
		var items: Array = ridges["scenery"]
		if not items.any(func(i): return i["cliff_piece"] == "inner_corner"): continue
		corner_found = true
		check(items.any(func(i): return i["cliff_piece"] == "outer_corner"), "generated bends contain both original corner forms")
		check(ridges == Landscape.rock_ridges(size, terrain, [], fields, [], seed_value), "corner geometry and variants remain deterministic")
		var centers: Dictionary = {}
		for item in items: centers[Vector2i(item["position"])] = true
		for item in items:
			var center := Vector2i(item["position"])
			check(item["cliff_connections"] == Chain.connections_at(center, centers), "generation binds art to real neighbors rather than a nominal axis")
			check(item["occupied_cells"].size() == 9, "straight pieces, terminals and corners reserve their full footprint")
			for cell in item["occupied_cells"]: check(ridges["cells"].has(cell), "corner navigation remains continuous with the global obstruction map")
		break
	check(corner_found, "the generated geology exercises real connected corners")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
