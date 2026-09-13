extends SceneTree

const Coordinates := preload("res://scripts/coordinates.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")

const MAP_SEED := 41721
const GOLDEN_SIZE := Vector2i(960, 560)
const EXPECTED_RGBA_SHA256 := "a21f53736f5bb91743ee557b38c790ac7ff60f1536cc51e38daa4a2014be4f99"

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var image := build_golden(catalog)
	var output_directory := ProjectSettings.globalize_path("res://qa/golden")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var output_path := output_directory.path_join("terrain-biomes.png")
	var save_error := image.save_png(output_path)
	assert_equal(save_error, OK, "golden screenshot can be saved")
	var digest_context := HashingContext.new()
	digest_context.start(HashingContext.HASH_SHA256)
	digest_context.update(image.get_data())
	var digest: String = digest_context.finish().hex_encode()
	assert_equal(digest, EXPECTED_RGBA_SHA256, "terrain golden RGBA hash")
	assert_equal(image.get_size(), GOLDEN_SIZE, "golden screenshot dimensions")

	if failures.is_empty():
		print("T-006 terrain golden tests passed (%s)" % output_path)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func build_golden(catalog) -> Image:
	var canvas := Image.create(GOLDEN_SIZE.x, GOLDEN_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("101820"))
	var panel_origins := [Vector2(220, 38), Vector2(700, 38), Vector2(220, 300), Vector2(700, 300)]
	for panel_index in range(panel_origins.size()):
		var terrain_ids := biome_map(panel_index)
		var elevation = TerrainElevation.new(Vector2i(8, 8))
		if panel_index == 0:
			elevation.generate_radial_hill(Vector2i(4, 4), 3, 2)
		var provider := func(cell: Vector2i) -> int:
			if cell.x < 0 or cell.y < 0 or cell.x >= 8 or cell.y >= 8:
				return int(terrain_ids.get(Vector2i(clampi(cell.x, 0, 7), clampi(cell.y, 0, 7)), 0))
			return int(terrain_ids.get(cell, 0))
		for y in range(8):
			for x in range(8):
				var cell := Vector2i(x, y)
				var drawable: Dictionary = TerrainRenderer.tile_drawable(cell, provider.call(cell), provider, catalog, elevation, 1.0, panel_origins[panel_index], MAP_SEED)
				blend_texture(canvas, drawable["texture"], Vector2i(roundi(drawable["position"].x), roundi(drawable["position"].y)))
				for layer in drawable["borders"]:
					var border_texture: Texture2D = catalog.get_terrain_border_texture(int(layer["border_id"]), int(layer["frame"]))
					var metadata: Dictionary = catalog.get_texture_metadata(String(layer["asset_name"]), int(layer["frame"]))
					var hotspot := Vector2.ZERO
					if metadata.has("hotspot"):
						hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
					blend_texture(canvas, border_texture, Vector2i(roundi(drawable["position"].x - hotspot.x), roundi(drawable["position"].y - hotspot.y)))
		if panel_index == 3:
			draw_forest_resources(canvas, catalog, elevation, panel_origins[panel_index])
		verify_scale_contract(catalog, elevation, provider)
	verify_flat_lattice(catalog)
	return canvas


func biome_map(panel_index: int) -> Dictionary:
	var result := {}
	for y in range(8):
		for x in range(8):
			var cell := Vector2i(x, y)
			match panel_index:
				0: result[cell] = 0
				1: result[cell] = 6 if x + y < 9 else 0
				2: result[cell] = 1 if x <= 2 else 2 if x == 3 else 0
				_: result[cell] = 10 if cell in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4), Vector2i(5, 4)] else 0
	return result


func draw_forest_resources(canvas: Image, catalog, elevation, view_offset: Vector2) -> void:
	var entries := [
		{"world": Vector2(3.5, 3.5), "texture": catalog.tree_texture, "name": "tree", "frame": 0},
		{"world": Vector2(4.5, 3.5), "texture": catalog.tree_texture, "name": "tree", "frame": 0},
		{"world": Vector2(4.5, 4.5), "texture": catalog.tree_texture, "name": "tree", "frame": 0},
		{"world": Vector2(5.5, 4.5), "texture": catalog.tree_stump_textures[2], "name": "tree_stump", "frame": 2},
		{"world": Vector2(2.5, 5.5), "texture": catalog.berry_texture, "name": "berry_bush", "frame": 0},
	]
	entries.sort_custom(func(left, right): return Coordinates.iso_raw(left["world"]).y < Coordinates.iso_raw(right["world"]).y)
	for entry in entries:
		var texture: Texture2D = entry["texture"]
		var metadata: Dictionary = catalog.get_texture_metadata(entry["name"], entry["frame"])
		var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
		if metadata.has("hotspot"):
			hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
		var anchor: Vector2 = elevation.world_to_screen(entry["world"], 1.0, view_offset)
		blend_texture(canvas, texture, Vector2i(roundi(anchor.x - hotspot.x), roundi(anchor.y - hotspot.y)))


func verify_scale_contract(catalog, elevation, provider: Callable) -> void:
	var cell := Vector2i(4, 4)
	var at_one := TerrainRenderer.tile_drawable(cell, int(provider.call(cell)), provider, catalog, elevation, 1.0, Vector2.ZERO, MAP_SEED)
	var at_two := TerrainRenderer.tile_drawable(cell, int(provider.call(cell)), provider, catalog, elevation, 2.0, Vector2.ZERO, MAP_SEED)
	assert_equal(at_two["size"], at_one["size"] * 2.0, "terrain texture scales by exact integer zoom")
	assert_equal(at_two["position"], at_one["position"] * 2.0, "terrain anchor scales by exact integer zoom")


func verify_flat_lattice(catalog) -> void:
	var elevation = TerrainElevation.new(Vector2i(3, 3))
	var provider := func(_cell: Vector2i) -> int: return 0
	var origin: Dictionary = TerrainRenderer.tile_drawable(Vector2i(0, 0), 0, provider, catalog, elevation, 1.0, Vector2.ZERO, MAP_SEED)
	var east: Dictionary = TerrainRenderer.tile_drawable(Vector2i(1, 0), 0, provider, catalog, elevation, 1.0, Vector2.ZERO, MAP_SEED)
	var south: Dictionary = TerrainRenderer.tile_drawable(Vector2i(0, 1), 0, provider, catalog, elevation, 1.0, Vector2.ZERO, MAP_SEED)
	assert_equal(origin["size"], Vector2(65, 33), "RoR sprite keeps its shared edge texel")
	assert_equal(east["position"] - origin["position"], Vector2(32, 16), "east tile advances on the 64x32 lattice")
	assert_equal(south["position"] - origin["position"], Vector2(-32, 16), "south tile advances on the 64x32 lattice")
	assert_equal(origin["position"], origin["position"].round(), "flat lattice remains pixel-aligned at 1x")


func blend_texture(canvas: Image, texture: Texture2D, position: Vector2i) -> void:
	if texture == null:
		failures.append("golden texture is missing")
		return
	var source := texture.get_image()
	canvas.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), position)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
