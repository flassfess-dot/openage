extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const GOLDEN_SIZE := Vector2i(1700, 900)
const EXPECTED_RGBA_SHA256 := "ca5ae034a7a28d8c6bc47c08ce2914c9a83a53eccf62bf49fd6b1c0722ece6ea"
const SOURCES := [13, 14, 15, 16, 17, 18, 19, 20, 21, 250, 277]
const CELL_WIDTH := 150

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var image := build_golden(catalog)
	var output_directory := ProjectSettings.globalize_path("res://qa/golden")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var output_path := output_directory.path_join("naval-presentations.png")
	assert_equal(image.save_png(output_path), OK, "naval golden screenshot can be saved")
	var digest_context := HashingContext.new()
	digest_context.start(HashingContext.HASH_SHA256)
	digest_context.update(image.get_data())
	var digest: String = digest_context.finish().hex_encode()
	assert_equal(digest, EXPECTED_RGBA_SHA256, "naval golden RGBA hash")
	assert_equal(image.get_size(), GOLDEN_SIZE, "naval golden dimensions")

	if failures.is_empty():
		print("I12-019F naval presentation golden passed (%s)" % output_path)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func build_golden(catalog) -> Image:
	var canvas := Image.create(GOLDEN_SIZE.x, GOLDEN_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("0d1921"))
	canvas.fill_rect(Rect2i(0, 225, GOLDEN_SIZE.x, 225), Color("101f28"))
	canvas.fill_rect(Rect2i(0, 675, GOLDEN_SIZE.x, 225), Color("101f28"))
	for index in range(SOURCES.size()):
		var source_id: int = SOURCES[index]
		var x := 25 + index * CELL_WIDTH + CELL_WIDTH / 2
		var state := "attack" if source_id in [19, 20, 21, 250, 277] else "idle"
		blend_frame_info(canvas, catalog.unit_frame_info(ship(source_id, 1, 100.0), state), Vector2i(x, 205))
		blend_frame_info(canvas, catalog.unit_frame_info(ship(source_id, 2, 100.0), state), Vector2i(x, 420))
		blend_frame_info(canvas, catalog.unit_frame_info(ship(source_id, 1, 10.0), state), Vector2i(x, 650))
		blend_frame_info(canvas, catalog.unit_frame_info(ship(source_id, 2, 0.0), "death"), Vector2i(x, 850))
	var impact: Dictionary = catalog.effect_frame_info({"graphic_id": 270, "team": 1, "elapsed": 0.25})
	blend_frame_info(canvas, impact, Vector2i(GOLDEN_SIZE.x - 70, 850))
	return canvas


func ship(source_id: int, team: int, hp: float) -> Dictionary:
	return {
		"id": source_id,
		"kind": alias_for_source(source_id),
		"source_unit_id": source_id,
		"team": team,
		"facing": 7,
		"anim": 0.16,
		"hp": hp,
		"max_hp": 100.0,
		"components": {"ownership": {"civilization_id": 13}},
	}


func alias_for_source(source_id: int) -> String:
	if source_id in [13, 14]:
		return "fishing_boat"
	if source_id in [15, 16]:
		return "trade_boat"
	if source_id in [17, 18]:
		return "transport"
	if source_id in [19, 20, 21]:
		return "scout_ship"
	return "catapult_trireme"


func blend_frame_info(canvas: Image, root: Dictionary, anchor: Vector2i) -> void:
	var layers: Array = []
	if root.get("texture") != null:
		layers.append(root)
	for part in root.get("composite_parts", []):
		layers.append(part)
	layers.sort_custom(func(left, right): return int(left.get("graphic_layer", 20)) < int(right.get("graphic_layer", 20)))
	for layer in layers:
		var texture: Texture2D = layer.get("texture")
		if texture == null:
			continue
		var source := texture.get_image()
		if bool(layer.get("mirrored", false)):
			source = source.duplicate()
			source.flip_x()
		var hotspot: Vector2 = layer.get("hotspot", Vector2(source.get_width() * 0.5, source.get_height()))
		var screen_offset: Vector2 = layer.get("screen_offset", Vector2.ZERO)
		var position := anchor + Vector2i(roundi(screen_offset.x - hotspot.x), roundi(screen_offset.y - hotspot.y))
		canvas.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), position)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
