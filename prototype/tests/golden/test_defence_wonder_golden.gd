extends SceneTree

const AnimationController := preload("res://scripts/animation_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const GOLDEN_SIZE := Vector2i(1280, 720)
const EXPECTED_RGBA_SHA256 := "34e72d619ca5e66ac59b5cece86be15850fe8f43a8d7d86170951c33caea2c4e"
const ANIMATION_TIME := 0.35

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var image := build_golden(catalog)
	var output_directory := ProjectSettings.globalize_path("res://qa/golden")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var output_path := output_directory.path_join("defence-wonder-presentations.png")
	assert_equal(image.save_png(output_path), OK, "defence and Wonder golden screenshot can be saved")
	var digest_context := HashingContext.new()
	digest_context.start(HashingContext.HASH_SHA256)
	digest_context.update(image.get_data())
	var digest: String = digest_context.finish().hex_encode()
	assert_equal(digest, EXPECTED_RGBA_SHA256, "defence and Wonder golden RGBA hash")
	assert_equal(image.get_size(), GOLDEN_SIZE, "defence and Wonder golden dimensions")

	if failures.is_empty():
		print("I12-016 defence and Wonder golden passed (%s)" % output_path)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func build_golden(catalog) -> Image:
	var canvas := Image.create(GOLDEN_SIZE.x, GOLDEN_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("101820"))
	var completed := [
		{"kind": "wall", "source": 72, "graphic": 825, "team": 1, "hp": 200.0, "max_hp": 200.0, "anchor": Vector2i(100, 240)},
		{"kind": "wall", "source": 117, "graphic": 894, "team": 2, "hp": 300.0, "max_hp": 300.0, "anchor": Vector2i(280, 240)},
		{"kind": "wall", "source": 155, "graphic": 889, "team": 1, "hp": 400.0, "max_hp": 400.0, "anchor": Vector2i(460, 240)},
		{"kind": "tower", "source": 79, "graphic": 826, "team": 2, "hp": 100.0, "max_hp": 100.0, "anchor": Vector2i(690, 240)},
		{"kind": "tower", "source": 199, "graphic": 821, "team": 1, "hp": 150.0, "max_hp": 150.0, "anchor": Vector2i(930, 240)},
		{"kind": "wonder", "source": 276, "graphic": 900, "team": 2, "hp": 500.0, "max_hp": 500.0, "anchor": Vector2i(1170, 310)},
	]
	for entry in completed:
		blend_frame_info(canvas, catalog.building_frame_info(building(entry), ANIMATION_TIME), entry["anchor"])

	var damaged_wall := building({"kind": "wall", "source": 117, "graphic": 894, "team": 1, "hp": 80.0, "max_hp": 300.0})
	blend_frame_info(canvas, catalog.building_frame_info(damaged_wall, ANIMATION_TIME), Vector2i(130, 550))
	var damaged_tower := building({"kind": "tower", "source": 79, "graphic": 826, "team": 1, "hp": 20.0, "max_hp": 100.0})
	blend_frame_info(canvas, catalog.building_frame_info(damaged_tower, ANIMATION_TIME), Vector2i(330, 560))
	var damaged_wonder := building({"kind": "wonder", "source": 276, "graphic": 900, "team": 1, "hp": 120.0, "max_hp": 500.0})
	blend_frame_info(canvas, catalog.building_frame_info(damaged_wonder, ANIMATION_TIME), Vector2i(590, 630))

	var attacking_tower := building({"kind": "tower", "source": 199, "graphic": 821, "team": 2, "hp": 150.0, "max_hp": 150.0})
	attacking_tower["anim_state"] = AnimationController.ATTACK_WINDUP
	attacking_tower["anim"] = 0.35
	blend_frame_info(canvas, catalog.building_frame_info(attacking_tower, ANIMATION_TIME), Vector2i(830, 560))

	var wall_foundation := building({"kind": "wall", "source": 72, "graphic": 825, "team": 2, "hp": 40.0, "max_hp": 200.0})
	wall_foundation["state"] = "foundation"
	wall_foundation["construction_stage"] = 1
	blend_frame_info(canvas, catalog.building_frame_info(wall_foundation), Vector2i(980, 650))
	var tower_foundation := building({"kind": "tower", "source": 79, "graphic": 826, "team": 1, "hp": 20.0, "max_hp": 100.0})
	tower_foundation["state"] = "foundation"
	tower_foundation["construction_stage"] = 2
	blend_frame_info(canvas, catalog.building_frame_info(tower_foundation), Vector2i(1090, 650))
	var wonder_foundation := building({"kind": "wonder", "source": 276, "graphic": 900, "team": 2, "hp": 50.0, "max_hp": 500.0})
	wonder_foundation["state"] = "foundation"
	wonder_foundation["construction_stage"] = 2
	blend_frame_info(canvas, catalog.building_frame_info(wonder_foundation), Vector2i(1230, 690))
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


func building(entry: Dictionary) -> Dictionary:
	return {
		"id": int(entry.get("source", -1)),
		"kind": String(entry.get("kind", "")),
		"team": int(entry.get("team", 1)),
		"source_unit_id": int(entry.get("source", -1)),
		"display_graphic_id": int(entry.get("graphic", -1)),
		"state": "complete",
		"construction_stage": 3,
		"death_phase": "alive",
		"hp": float(entry.get("hp", 1.0)),
		"max_hp": float(entry.get("max_hp", 1.0)),
		"anim_state": AnimationController.IDLE,
		"anim": 0.0,
		"facing": 0,
		"components": {"ownership": {"civilization_id": 13}},
	}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
