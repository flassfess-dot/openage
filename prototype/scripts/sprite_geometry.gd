class_name RoRSpriteGeometry


static func source_to_screen(source: Vector2, anchor: Vector2, scale: float, hotspot: Vector2, mirrored: bool) -> Vector2:
	var local := (source - hotspot) * scale
	if mirrored:
		local.x = -local.x
	return anchor + local

static func screen_to_source(screen: Vector2, anchor: Vector2, scale: float, hotspot: Vector2, mirrored: bool) -> Vector2:
	if scale <= 0.0:
		return hotspot
	var local := (screen - anchor) / scale
	if mirrored:
		local.x = -local.x
	return hotspot + local

static func anchored_rectangle(texture_size: Vector2, hotspot: Vector2, scale: float) -> Rect2:
	return Rect2(-hotspot * scale, texture_size * scale)
