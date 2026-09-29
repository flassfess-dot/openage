extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const ShorelineTiles := preload("res://scripts/shoreline_tiles.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_frame_sets()
	test_seeded_variation()
	test_slope_tiles_have_base_and_raised_underlays()
	test_shoreline_neighbor_combinations()
	test_shoreline_pixels()
	test_shallows_do_not_render_as_open_water()
	test_forest_resources_preserve_source_forest_terrain()

	if failures.is_empty():
		print("T-001 terrain tile tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_frame_sets() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	for terrain_kind in ["grass", "sand", "water", "water_dark"]:
		var expected := TerrainRules.frame_count(terrain_kind)
		var terrain_id := int(TerrainRules.TERRAIN_IDS[terrain_kind])
		var source_record: Dictionary = catalog.terrain_catalog_data.get("terrains", {}).get(str(terrain_id), {})
		var flat_graphic: Dictionary = source_record.get("elevation_graphics", [])[0]
		assert_equal(expected, int(flat_graphic.get("frame_count", 0)), "%s count comes from flat elevation table" % terrain_kind)
		var frames: Array = catalog.terrain_textures.get(terrain_kind, [])
		assert_equal(frames.size(), expected, "%s complete frame set" % terrain_kind)
		for index in range(frames.size()):
			var texture: Texture2D = frames[index]
			assert_true(texture != null, "%s frame %d loads" % [terrain_kind, index])
			assert_true(texture.get_width() > 0 and texture.get_height() > 0, "%s frame %d dimensions" % [terrain_kind, index])


func test_seeded_variation() -> void:
	for terrain_kind in ["grass", "sand", "water", "water_dark"]:
		var count := TerrainRules.frame_count(terrain_kind)
		var first: Array[int] = []
		var repeated: Array[int] = []
		var second_seed: Array[int] = []
		var used := {}
		for y in range(32):
			for x in range(32):
				var cell := Vector2i(x, y)
				var frame := TerrainRules.tile_variant(cell, terrain_kind, 41721)
				first.append(frame)
				repeated.append(TerrainRules.tile_variant(cell, terrain_kind, 41721))
				second_seed.append(TerrainRules.tile_variant(cell, terrain_kind, 41722))
				used[frame] = true
		assert_equal(first, repeated, "%s deterministic for same seed" % terrain_kind)
		assert_true(first != second_seed, "%s changes with seed" % terrain_kind)
		assert_equal(used.size(), count, "%s reaches every imported frame" % terrain_kind)
		assert_no_repeated_stripes(first, 32, terrain_kind)


func test_slope_tiles_have_base_and_raised_underlays() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var elevation = TerrainElevation.new(Vector2i(2, 2))
	elevation.clear()
	elevation.set_vertex(Vector2i(0, 0), 1)
	elevation.set_vertex(Vector2i(1, 0), 1)
	var drawable := TerrainRenderer.tile_drawable(
		Vector2i.ZERO,
		int(TerrainRules.TERRAIN_IDS["grass"]),
		Callable(self, "grass_terrain_id"),
		catalog,
		elevation,
		1.0,
		Vector2.ZERO,
		41721
	)
	var underlays: Array = drawable.get("underlays", [])
	assert_equal(underlays.size(), 2, "raised slope has both base and raised underlays")
	assert_true(Vector2(underlays[0]["position"]) != Vector2(underlays[1]["position"]), "slope underlays cover different vertical bands")


func test_shoreline_neighbor_combinations() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var center := Vector2i(1, 1)
	var offsets := [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
	for water_id in [1, 4, 22]:
		for mask in range(256):
			var cells := {}
			for bit in range(8):
				if mask & (1 << bit):
					cells[center + offsets[bit]] = water_id
			var provider := func(cell: Vector2i) -> int: return int(cells.get(cell, 2))
			var layers := TerrainRules.border_layers(center, provider, catalog.terrain_catalog_data, 41721)
			assert_equal(layers.size(), 0 if mask == 0 else 1, "shore mask %d water %d composes without overpainting" % [mask, water_id])
			if not layers.is_empty():
				assert_equal(int(layers[0]["border_id"]), TerrainRules.BORDER_SHORELINE, "shoreline uses source-derived graphics")
				assert_equal(int(layers[0]["frame"]), mask, "all eight neighbors reach the shoreline frame")
				assert_true(catalog.get_terrain_border_texture(TerrainRules.BORDER_SHORELINE, mask) != null, "shore mask %d has a texture" % mask)


func test_shoreline_pixels() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var water_colors := {}
	for texture in catalog.terrain_textures["water"]:
		var image: Image = texture.get_image()
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				if pixel.a == 1.0:
					water_colors[pixel.to_rgba32()] = true
	var source_colors := {}
	for texture in catalog.terrain_border_textures[2]:
		var image: Image = texture.get_image()
		for y in image.get_height():
			for x in image.get_width():
				source_colors[image.get_pixel(x, y).to_rgba32()] = true
	var unique_textures := {}
	var edge_samples := [Vector2i(16, 8), Vector2i(48, 8), Vector2i(48, 24), Vector2i(16, 24)]
	var corner_samples := [Vector2i(32, 2), Vector2i(60, 16), Vector2i(32, 30), Vector2i(4, 16)]
	for mask in range(256):
		var texture: Texture2D = catalog.get_terrain_border_texture(TerrainRules.BORDER_SHORELINE, mask)
		unique_textures[texture.get_rid()] = true
		var image := texture.get_image()
		assert_equal(image.get_size(), Vector2i(65, 33), "shoreline preserves the source lattice")
		for side in range(4):
			if mask & (1 << side):
				assert_true(water_colors.has(image.get_pixelv(edge_samples[side]).to_rgba32()), "mask %d meets open water at side %d" % [mask, side])
		for y in image.get_height():
			for x in image.get_width():
				var pixel := image.get_pixel(x, y)
				assert_true(pixel.a == 0.0 or pixel.a == 1.0, "shoreline never introduces translucent diamonds")
				assert_true(pixel.a == 0.0 or source_colors.has(pixel.to_rgba32()) or water_colors.has(pixel.to_rgba32()), "shoreline retains the source palette")
	assert_equal(unique_textures.size(), 47, "equivalent neighbors reuse textures instead of growing the atlas")
	var island: Image = catalog.get_terrain_border_texture(TerrainRules.BORDER_SHORELINE, 15).get_image()
	assert_equal(island.get_pixel(32, 16).a, 1.0, "isolated shore cell retains opaque land at its center")
	assert_true(not water_colors.has(island.get_pixel(32, 16).to_rgba32()), "four water edges do not erase the central island")
	assert_equal(island.get_pixel(0, 0).a, 0.0, "isolated island keeps transparent outer corners")
	for y in island.get_height():
		for x in island.get_width():
			var pixel := island.get_pixel(x, y)
			if pixel.a > 0.0 and absi(x - 32) + 2 * absi(y - 16) >= 28:
				assert_true(water_colors.has(pixel.to_rgba32()), "isolated island has water along its entire perimeter")
	for corner in range(4):
		var texture: Texture2D = catalog.get_terrain_border_texture(TerrainRules.BORDER_SHORELINE, 1 << (corner + 4))
		var image := texture.get_image()
		assert_true(water_colors.has(image.get_pixelv(corner_samples[corner]).to_rgba32()), "diagonal-only inlet has water in corner %d" % corner)
		assert_equal(image.get_pixelv(corner_samples[(corner + 2) % 4]).a, 0.0, "diagonal inlet preserves opposite land")


func test_shallows_do_not_render_as_open_water() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	assert_equal(TerrainRules.base_texture_kind(22, catalog.terrain_catalog_data), "water_dark", "source deep water keeps its own RoR texture")
	assert_equal(TerrainRules.base_texture_kind(4, catalog.terrain_catalog_data), "sand", "source Shallows does not use the flat open-water placeholder")
	assert_true(4 in TerrainRules.WATER_TERRAIN_IDS, "source Shallows remains water-domain terrain for scenario placement")
	assert_true(TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(4)), "source Shallows is traversable by land units")
	assert_true(TerrainRules.is_water_navigable(TerrainRules.logical_for_terrain_id(4)), "source Shallows remains traversable by ships")


func test_forest_resources_preserve_source_forest_terrain() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var world := SimulationWorld.new(Vector2i(3, 3))
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain_ids: Array[int] = []
	terrain_ids.resize(9)
	terrain_ids.fill(0)
	terrain_ids[1 * 3 + 1] = 13
	var vertex_levels: Array[int] = []
	vertex_levels.resize(16)
	vertex_levels.fill(0)
	world.configure_map_data({"terrain_ids": terrain_ids, "vertex_levels": vertex_levels})
	world.add_scenario_resource("tree", Vector2(1.5, 1.5), 40)
	assert_equal(world.terrain_id_at_cell(Vector2i(1, 1)), 13, "source DesertPalm terrain survives tree registration")

	world.add_scenario_resource("tree", Vector2(2.5, 2.5), 40)
	assert_equal(world.terrain_id_at_cell(Vector2i(2, 2)), int(TerrainRules.TERRAIN_IDS["forest_floor"]), "generated tree on plain grass still synthesizes forest floor")


func grass_terrain_id(_cell: Vector2i) -> int:
	return int(TerrainRules.TERRAIN_IDS["grass"])


func assert_no_repeated_stripes(values: Array[int], width: int, context: String) -> void:
	var rows := {}
	var columns := {}
	for y in range(width):
		var row: Array[int] = []
		var column: Array[int] = []
		for x in range(width):
			row.append(values[y * width + x])
			column.append(values[x * width + y])
		rows[str(row)] = true
		columns[str(column)] = true
	assert_equal(rows.size(), width, "%s has no repeated horizontal stripe" % context)
	assert_equal(columns.size(), width, "%s has no repeated vertical stripe" % context)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
