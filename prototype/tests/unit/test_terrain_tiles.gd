extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_frame_sets()
	test_seeded_variation()
	test_slope_tiles_have_base_and_raised_underlays()
	test_water_corner_frames_follow_diagonal_terrain()
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


func test_water_corner_frames_follow_diagonal_terrain() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var external_map := {
		Vector2i(1, 1): 0,
		Vector2i(0, 1): 1,
		Vector2i(1, 0): 1,
		Vector2i(0, 0): 1,
	}
	var external_layers := TerrainRules.border_layers(Vector2i(1, 1), Callable(self, "terrain_from_external_corner_map").bind(external_map), catalog.terrain_catalog_data, 41721)
	assert_equal(external_layers.size(), 1, "external water corner emits one border layer")
	assert_equal(int(external_layers[0]["border_id"]), 2, "grass shoreline uses the rounded desert/water corner sprite")
	assert_equal(String(external_layers[0]["asset_name"]), "border_desert_water", "external water corner resolves the non-degenerate sprite set")
	assert_equal(int(external_layers[0]["frame"]), 1, "land protruding into water uses the external corner frame")

	var internal_map := external_map.duplicate()
	internal_map[Vector2i(0, 0)] = 0
	var internal_layers := TerrainRules.border_layers(Vector2i(1, 1), Callable(self, "terrain_from_external_corner_map").bind(internal_map), catalog.terrain_catalog_data, 41721)
	assert_equal(internal_layers.size(), 1, "internal water corner emits one border layer")
	assert_equal(int(internal_layers[0]["border_id"]), 2, "internal grass shoreline uses the matching desert/water corner sprite")
	assert_equal(int(internal_layers[0]["frame"]), 6, "diagonal land uses the internal corner frame")

	var straight_map := {
		Vector2i(1, 1): 0,
		Vector2i(0, 1): 1,
	}
	var straight_layers := TerrainRules.border_layers(Vector2i(1, 1), Callable(self, "terrain_from_external_corner_map").bind(straight_map), catalog.terrain_catalog_data, 41721)
	assert_equal(int(straight_layers[0]["border_id"]), 3, "straight shoreline keeps the grass/water sprite set")
	assert_equal(int(straight_layers[0]["frame"]), 8, "straight shoreline keeps its original edge frame")


func test_shallows_do_not_render_as_open_water() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	assert_equal(TerrainRules.base_texture_kind(22, catalog.terrain_catalog_data), "water_dark", "source deep water keeps its own RoR texture")
	assert_equal(TerrainRules.base_texture_kind(4, catalog.terrain_catalog_data), "sand", "source Shallows does not use the flat open-water placeholder")
	assert_true(4 in TerrainRules.WATER_TERRAIN_IDS, "source Shallows remains water-domain terrain for scenario placement")


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


func terrain_from_external_corner_map(cell: Vector2i, terrain_map: Dictionary) -> int:
	return int(terrain_map.get(cell, 0))


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
