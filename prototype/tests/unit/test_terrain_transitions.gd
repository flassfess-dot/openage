extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_tables()
	test_neighbor_masks()
	test_transparent_border_assets()

	if failures.is_empty():
		print("T-002 terrain transition tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_tables() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var data: Dictionary = catalog.terrain_catalog_data
	assert_equal(data.get("terrain_count"), 32, "RoR terrain count")
	assert_equal(data.get("border_count"), 16, "RoR border count")
	assert_equal(data.get("terrains", {}).get("0", {}).get("name"), "Grass", "grass ID")
	assert_equal(data.get("terrains", {}).get("1", {}).get("name"), "Water", "water ID")
	assert_equal(data.get("terrains", {}).get("2", {}).get("replacement_terrain_id"), 6, "beach uses desert underlay")
	assert_equal(data.get("terrains", {}).get("10", {}).get("replacement_terrain_id"), 0, "forest floor uses grass underlay")
	assert_equal(data.get("terrains", {}).get("0", {}).get("borders", [])[1], 3, "grass-water table border")
	assert_equal(data.get("terrains", {}).get("0", {}).get("borders", [])[6], 6, "grass-desert table border")
	assert_equal(data.get("terrains", {}).get("2", {}).get("borders", [])[1], 2, "beach-water table border")
	assert_equal(data.get("terrains", {}).get("22", {}).get("borders", [])[1], 7, "dark water uses the source water transition")
	assert_true(data.get("edge_masks", []).any(func(item): return item["file"] == "data2/TileEdge.Dat"), "expansion TileEdge is cataloged")
	assert_true(data.get("edge_masks", []).any(func(item): return item["kind"] == "fog"), "BlkEdge mask is cataloged")


func test_neighbor_masks() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var data: Dictionary = catalog.terrain_catalog_data
	var center := Vector2i(5, 5)
	var cells := {center: 0}
	var provider := func(cell: Vector2i) -> int: return int(cells.get(cell, 0))
	var cases := {
		Vector2i(-1, 0): 8,
		Vector2i(0, -1): 11,
		Vector2i(1, 0): 9,
		Vector2i(0, 1): 10,
	}
	for offset in cases:
		cells.clear()
		cells[center] = 0
		cells[center + offset] = 1
		var layers := TerrainRules.border_layers(center, provider, data, 41721)
		assert_equal(layers.size(), 1, "single water edge has one border")
		assert_equal(layers[0]["border_id"], 3, "single water edge uses original border 3")
		assert_equal(layers[0]["frame"], cases[offset], "single edge orientation %s" % offset)

	cells.clear()
	cells[center] = 0
	cells[center + Vector2i(-1, 0)] = 2
	cells[center + Vector2i(0, -1)] = 2
	var style1 := TerrainRules.border_layers(center, provider, data, 41721)
	assert_equal(style1.size(), 2, "style 1 combines two transparent edge strips")
	assert_equal(style1[0]["frame"], 0, "style 1 upper-left strip")
	assert_equal(style1[1]["frame"], 1, "style 1 upper-right strip")
	cells.clear()
	cells[center] = 22
	cells[center + Vector2i.RIGHT] = 1
	var dark_water_layers := TerrainRules.border_layers(center, provider, data, 41721)
	assert_equal(dark_water_layers.size(), 1, "dark and ordinary water share a visible transition")
	assert_equal(dark_water_layers[0]["border_id"], 7, "water seam uses source border 7")
	cells.clear()
	cells[center] = 0
	cells[center + Vector2i.LEFT] = 1
	cells[center + Vector2i.RIGHT] = 1
	cells[center + Vector2i.UP] = 1
	var narrow_bay_layers := TerrainRules.border_layers(center, provider, data, 41721)
	assert_equal(narrow_bay_layers.size(), 3, "tight bays draw all three water edges instead of the first only")


func test_transparent_border_assets() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	for border_id in [2, 3, 4, 5, 6, 7]:
		var frames: Array = catalog.terrain_border_textures.get(border_id, [])
		assert_true(not frames.is_empty(), "border %d textures load" % border_id)
		for frame in range(frames.size()):
			var name: String = TerrainRules.BORDER_ASSET_NAMES[border_id]
			var semantics: Dictionary = catalog.get_texture_metadata(name, frame).get("semanticPixels", {})
			assert_true(int(semantics.get("transparency", 0)) > 0, "border %d frame %d retains transparency" % [border_id, frame])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
