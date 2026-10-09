class_name RoRSelectionResolver

const SpriteGeometry := preload("res://scripts/sprite_geometry.gd")
const MAX_HIT_IMAGES := 256
const MAX_HIT_IMAGE_BYTES := 16 * 1024 * 1024
static var hit_images: Dictionary = {}
static var hit_image_bytes := 0

static func clear_hit_images() -> void:
	for id in hit_images.keys():
		_forget_hit_image(id)

static func _forget_hit_image(id: int) -> void:
	var entry: Dictionary = hit_images.get(id, {})
	if entry.is_empty():
		return
	var texture = entry["texture"].get_ref()
	var callback := _forget_hit_image.bind(id)
	if texture != null and texture.changed.is_connected(callback):
		texture.changed.disconnect(callback)
	hit_image_bytes -= int(entry["bytes"])
	hit_images.erase(id)

static func _hit_image(texture: Texture2D) -> Image:
	# Imported sprites are immutable between Resource.changed notifications.
	# Dynamic ImageTexture/ViewportTexture updates have no such guarantee.
	if not texture is CompressedTexture2D:
		return texture.get_image()
	var id := texture.get_instance_id()
	var entry: Dictionary = hit_images.get(id, {})
	if not entry.is_empty():
		if entry["texture"].get_ref() == texture:
			return entry["image"]
		_forget_hit_image(id)
	var image := texture.get_image()
	if image == null:
		return null
	var bytes := image.get_data().size()
	if bytes > MAX_HIT_IMAGE_BYTES:
		return image
	while not hit_images.is_empty() and (hit_images.size() >= MAX_HIT_IMAGES or hit_image_bytes + bytes > MAX_HIT_IMAGE_BYTES):
		_forget_hit_image(int(hit_images.keys()[0]))
	hit_images[id] = {"texture": weakref(texture), "image": image, "bytes": bytes}
	hit_image_bytes += bytes
	texture.changed.connect(_forget_hit_image.bind(id))
	return image



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
	var image := _hit_image(texture)
	return image != null and image.get_pixelv(pixel).a > 0.05

static func prioritized_box_hits(unit_hits: Array, building_hits: Array) -> Array:
	return unit_hits if not unit_hits.is_empty() else building_hits

static func apply_selection(eligible_entities: Array, hits: Array, shift_pressed: bool) -> void:
	if not shift_pressed:
		for entity in eligible_entities:
			entity["selected"] = false
	for entity in hits:
		entity["selected"] = not bool(entity.get("selected", false)) if shift_pressed else true
