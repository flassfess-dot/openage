class_name RoRHUDTypography
extends RefCounted

static var regular: SystemFont
static var emphasized: SystemFont


static func body_font() -> Font:
	if regular == null:
		regular = SystemFont.new()
		regular.font_names = PackedStringArray(["Arial", "Liberation Sans", "DejaVu Sans"])
		regular.font_weight = 400
	return regular


static func title_font() -> Font:
	if emphasized == null:
		emphasized = SystemFont.new()
		emphasized.font_names = PackedStringArray(["Arial", "Liberation Sans", "DejaVu Sans"])
		emphasized.font_weight = 600
	return emphasized
