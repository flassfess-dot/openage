class_name RoRLauncherTypography
extends RefCounted

static var regular: SystemFont
static var emphasized: SystemFont


static func body_font() -> Font:
	if regular == null:
		regular = _vector_font(PackedStringArray(["Segoe UI", "Noto Sans", "Liberation Sans", "DejaVu Sans"]), 400)
	return regular


static func title_font() -> Font:
	if emphasized == null:
		emphasized = _vector_font(PackedStringArray(["Georgia", "Noto Serif", "Liberation Serif", "DejaVu Serif"]), 700)
	return emphasized


static func _vector_font(names: PackedStringArray, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = names
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.hinting = TextServer.HINTING_LIGHT
	font.disable_embedded_bitmaps = true
	# Menus use a scaled layout canvas. Distance-field glyphs remain sharp at
	# every window scale instead of enlarging a small raster font atlas.
	font.multichannel_signed_distance_field = true
	font.msdf_pixel_range = 16
	font.msdf_size = 64
	return font
