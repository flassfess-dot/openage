extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const GOLDEN_SIZE := Vector2i(1700, 900)
# An explicit source-frame oracle replaces the old image of misdirected
# 16-angle ships. These SE facets were chosen from inspected source PNGs;
# neither UnitPresentationRegistry nor GraphicDescriptor builds the reference.
const REFERENCE_LAYERS := {
	13: [["fishing_boat_idle", 1, 42]],
	14: [["fishing_ship_idle", 1, 44]],
	15: [["trade_boat_idle", 1, 49]],
	16: [["merchant_ship_idle", 1, 50]],
	17: [["transport_hull", 1, 51], ["transport_sail", 9, 45]],
	18: [["heavy_transport_hull", 1, 54], ["heavy_transport_sail", 18, 46]],
	19: [["scout_ship_hull", 1, 57], ["transport_sail", 9, 45]],
	20: [["war_galley_hull", 1, 61], ["transport_sail", 9, 45]],
	21: [["trireme_hull", 2, 65], ["trireme_oars", 2, 67], ["heavy_transport_sail", 18, 46]],
	250: [["trireme_hull", 2, 65], ["catapult_trireme_weapon", 2, 70], ["heavy_transport_sail", 18, 46]],
	277: [["trireme_hull", 2, 65], ["catapult_trireme_weapon", 2, 70], ["heavy_transport_sail", 18, 46]],
}
const REFERENCE_FIRE := {13: 328, 14: 328, 15: 328, 16: 327, 17: 328, 18: 330, 19: 327, 20: 328, 21: 329, 250: 330, 277: 330}
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
	var reference := build_reference_golden(catalog)
	assert_equal(reference.save_png(output_directory.path_join("naval-presentations-reference.png")), OK, "independent naval reference can be saved")
	var reference_hash := HashingContext.new()
	reference_hash.start(HashingContext.HASH_SHA256)
	reference_hash.update(reference.get_data())
	assert_equal(digest, reference_hash.finish().hex_encode(), "naval pixels match independently selected southeast source facets")
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


func build_reference_golden(catalog) -> Image:
	var canvas := Image.create(GOLDEN_SIZE.x, GOLDEN_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("0d1921"))
	canvas.fill_rect(Rect2i(0, 225, GOLDEN_SIZE.x, 225), Color("101f28"))
	canvas.fill_rect(Rect2i(0, 675, GOLDEN_SIZE.x, 225), Color("101f28"))
	for index in range(SOURCES.size()):
		var source_id: int = SOURCES[index]
		var x := 25 + index * CELL_WIDTH + CELL_WIDTH / 2
		for row in range(3):
			var team := 2 if row == 1 else 1
			var parts: Array = []
			for pin in REFERENCE_LAYERS[source_id]:
				var name: String = ("enemy_" if team == 2 else "") + String(pin[0])
				parts.append(reference_layer(catalog, name, int(pin[1]), int(pin[2]), true))
			if row == 2:
				# At the fixture's 0.16 seconds, original 20-frame fire is on frame 3.
				var fire_id: int = REFERENCE_FIRE[source_id]
				parts.append(reference_layer(catalog, "graphic_%d_p1" % fire_id, 3, fire_id, false))
			var y: int = [205, 420, 650][row]
			var base: Dictionary = parts.pop_front()
			base["composite_parts"] = parts
			blend_frame_info(canvas, base, Vector2i(x, y))
		var death_name := "enemy_fishing_boat_death"
		var death_graphic := 176
		if source_id in [18, 20]:
			death_name = "enemy_heavy_transport_death"
			death_graphic = 175
		elif source_id in [21, 250, 277]:
			death_name = "enemy_trireme_death"
			death_graphic = 174
		blend_frame_info(canvas, reference_layer(catalog, death_name, 0, death_graphic, false), Vector2i(x, 850))
	# 0.25 seconds / original 0.0465-second catapult impact = source frame 5.
	blend_frame_info(canvas, reference_layer(catalog, "graphic_270_p1", 5, 270, false), Vector2i(GOLDEN_SIZE.x - 70, 850))
	return canvas


func reference_layer(catalog, asset_name: String, frame: int, graphic_id: int, mirrored: bool) -> Dictionary:
	var metadata: Dictionary = catalog.get_texture_metadata(asset_name, frame)
	if metadata.is_empty():
		failures.append("missing naval reference source %s frame %d" % [asset_name, frame])
		return {}
	var texture: Texture2D = load("res://assets/generated/%s" % String(metadata["file"]))
	var hotspot: Array = metadata.get("hotspot", [0, 0])
	var graphic: Dictionary = catalog.graphics_catalog_data["graphics"][str(graphic_id)]
	return {"texture": texture, "hotspot": Vector2(hotspot[0], hotspot[1]), "mirrored": mirrored, "graphic_layer": int(graphic.get("layer", 20))}


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
