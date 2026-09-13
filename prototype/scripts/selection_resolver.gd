class_name RoRSelectionResolver

const SpriteGeometry := preload("res://scripts/sprite_geometry.gd")


static func topmost(candidates: Array) -> Variant:
	if candidates.is_empty():
		return null
	var ordered := candidates.duplicate()
	ordered.sort_custom(func(left, right):
		if is_equal_approx(float(left["sort_y"]), float(right["sort_y"])):
			return int(left["id"]) > int(right["id"])
		return float(left["sort_y"]) > float(right["sort_y"])
	)
	return ordered[0]["entity"]

static func texture_hit(mouse: Vector2, anchor: Vector2, scale: float, texture: Texture2D, hotspot: Vector2, mirrored: bool) -> bool:
	if texture == null or scale <= 0.0:
		return false
	var source := SpriteGeometry.screen_to_source(mouse, anchor, scale, hotspot, mirrored)
	var pixel := Vector2i(floori(source.x), floori(source.y))
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= texture.get_width() or pixel.y >= texture.get_height():
		return false
	var image := texture.get_image()
	return image != null and image.get_pixelv(pixel).a > 0.05

static func prioritized_box_hits(unit_hits: Array, building_hits: Array) -> Array:
	return unit_hits if not unit_hits.is_empty() else building_hits

static func apply_selection(eligible_entities: Array, hits: Array, shift_pressed: bool) -> void:
	if not shift_pressed:
		for entity in eligible_entities:
			entity["selected"] = false
	for entity in hits:
		entity["selected"] = not bool(entity.get("selected", false)) if shift_pressed else true
