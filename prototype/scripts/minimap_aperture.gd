class_name RoRMinimapAperture
extends RefCounted

static var rows: Array = []


static func mask_rows() -> Array:
	if rows.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/hud/minimap-mask.json"))
		if parsed is Array:
			rows = parsed
	return rows


static func contains(point: Vector2, rectangle: Rect2) -> bool:
	if not rectangle.has_point(point):
		return false
	var native_point := (point - rectangle.position) / rectangle.size * Vector2(219, 109)
	var y := clampi(floori(native_point.y), 0, 108)
	var mask := mask_rows()
	if mask.size() != 109:
		return false
	var row: Array = mask[y]
	return native_point.x >= float(row[0]) and native_point.x < float(row[0] + row[1])


static func frame_texture(shell: Texture2D) -> Texture2D:
	if shell == null:
		return null
	var image := shell.get_image().get_region(Rect2i(792, 0, 232, 126))
	image.convert(Image.FORMAT_RGBA8)
	var mask := mask_rows()
	for y in range(mask.size()):
		var row: Array = mask[y]
		for x in range(int(row[0]), int(row[0] + row[1])):
			image.set_pixel(x + 4, y + 7, Color.TRANSPARENT)
	return ImageTexture.create_from_image(image)
