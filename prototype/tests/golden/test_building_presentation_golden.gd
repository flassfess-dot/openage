extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const GOLDEN_SIZE := Vector2i(1024, 640)
const EXPECTED_RGBA_SHA256 := "0a5127aeb2dd835ca5fb17808dfc495c010350626e7eae06744cefed99b47cf2"
const ANIMATION_TIME := 0.35

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var image := build_golden(catalog)
	var output_directory := ProjectSettings.globalize_path("res://qa/golden")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var output_path := output_directory.path_join("building-presentations.png")
	assert_equal(image.save_png(output_path), OK, "building golden screenshot can be saved")
	var digest_context := HashingContext.new()
	digest_context.start(HashingContext.HASH_SHA256)
	digest_context.update(image.get_data())
	var digest: String = digest_context.finish().hex_encode()
	assert_equal(digest, EXPECTED_RGBA_SHA256, "building golden RGBA hash")
	assert_equal(image.get_size(), GOLDEN_SIZE, "building golden dimensions")

	if failures.is_empty():
		print("G-009 building presentation golden passed (%s)" % output_path)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func build_golden(catalog) -> Image:
	var canvas := Image.create(GOLDEN_SIZE.x, GOLDEN_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("101820"))
	var entries := [
		{"kind": "town_center", "source": 109, "graphic": 598, "team": 1, "hp": 600.0, "anchor": Vector2i(170, 230)},
		{"kind": "barracks", "source": 12, "graphic": 13, "team": 2, "hp": 350.0, "anchor": Vector2i(500, 230)},
		{"kind": "house", "source": 70, "graphic": 817, "team": 1, "hp": 75.0, "anchor": Vector2i(820, 230)},
		{"kind": "granary", "source": 68, "graphic": 863, "team": 2, "hp": 140.0, "anchor": Vector2i(170, 540)},
		{"kind": "storage_pit", "source": 103, "graphic": 515, "team": 1, "hp": 350.0, "anchor": Vector2i(500, 540)},
		{"kind": "archery_range", "source": 87, "graphic": 873, "team": 2, "hp": 350.0, "anchor": Vector2i(820, 540)},
	]
	for entry in entries:
		var data := building(String(entry["kind"]), int(entry["source"]), int(entry["graphic"]), int(entry["team"]), float(entry["hp"]))
		var info: Dictionary = catalog.building_frame_info(data, ANIMATION_TIME)
		blend_frame_info(canvas, info, entry["anchor"])

	var common_foundation := building("barracks", 12, 13, 1, 35.0)
	common_foundation["state"] = "foundation"
	common_foundation["construction_stage"] = 1
	blend_frame_info(canvas, catalog.building_frame_info(common_foundation), Vector2i(350, 605))
	var house_foundation := building("house", 70, 817, 2, 12.0)
	house_foundation["state"] = "foundation"
	house_foundation["construction_stage"] = 2
	blend_frame_info(canvas, catalog.building_frame_info(house_foundation), Vector2i(660, 605))
	return canvas


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


func building(kind: String, source_unit_id: int, graphic_id: int, team: int, hp: float) -> Dictionary:
	return {
		"id": source_unit_id,
		"kind": kind,
		"team": team,
		"source_unit_id": source_unit_id,
		"display_graphic_id": graphic_id,
		"state": "complete",
		"construction_stage": 3,
		"hp": hp,
		"max_hp": 600.0 if kind == "town_center" else 350.0,
		"components": {"ownership": {"civilization_id": 13}},
	}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
