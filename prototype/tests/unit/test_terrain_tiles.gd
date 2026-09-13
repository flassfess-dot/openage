extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_frame_sets()
	test_seeded_variation()

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
	for terrain_kind in ["grass", "sand", "water"]:
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
	for terrain_kind in ["grass", "sand", "water"]:
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
