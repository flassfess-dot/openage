class_name RoRInterfaceLayout
extends RefCounted

const TOP_HEIGHT := 32.0
const SOURCE_TOP_HEIGHT := 20.0
const BOTTOM_HEIGHT := 126.0
const REFERENCE_WIDTHS := [640, 800, 1024]
const WIDE_RIGHT_WIDTH := 232.0
const WIDE_RIGHT_SOURCE_X := 792.0
const COMMAND_CELL_SIZE := 50.0
const COMMAND_GAP := 4.0
# Two rows fit all 18 catalogued buildings plus Back at desktop widths.
const COMMAND_MAX_COLUMNS := 10
const PRODUCTION_MAX_WIDTH := 360.0
const PRODUCTION_GAP := 10.0


static func for_viewport(viewport_size: Vector2) -> Dictionary:
	var width := maxf(320.0, viewport_size.x)
	var narrow := width < 720.0
	var top_height := 64.0 if narrow else TOP_HEIGHT
	var bottom_height := 252.0 if narrow else BOTTOM_HEIGHT
	var panel_top := viewport_size.y - bottom_height
	var minimap_scale := minf(1.0, maxf(0.5, (width - 174.0) / 232.0)) if narrow else 1.0
	var bottom := Rect2(0, panel_top, width, bottom_height)
	var selection := Rect2(4, panel_top + 4, 128, 118)
	var map_plane := Rect2(width - 232, panel_top, 232, 126)
	var production_minimum := 250.0 if width >= 960.0 else 170.0
	var command_space := width - 136.0 - 244.0 - PRODUCTION_GAP - production_minimum
	if narrow:
		map_plane = Rect2(width - 232 * minimap_scale, panel_top + 126, 232 * minimap_scale, 126 * minimap_scale)
		command_space = map_plane.position.x - 12.0
	var columns := clampi(floori((command_space + COMMAND_GAP) / (COMMAND_CELL_SIZE + COMMAND_GAP)), 1, COMMAND_MAX_COLUMNS)
	var command_width := columns * (COMMAND_CELL_SIZE + COMMAND_GAP) - COMMAND_GAP
	var command := Rect2(136, panel_top + 4, command_width, 118)
	var production_left := command.end.x + PRODUCTION_GAP
	var production_width := minf(PRODUCTION_MAX_WIDTH, width - production_left - 244.0)
	var production := Rect2(production_left, panel_top + 4, production_width, 118)
	if narrow:
		command = Rect2(4, panel_top + 130, command_width, 118)
		production = Rect2(136, panel_top + 4, minf(PRODUCTION_MAX_WIDTH, width - 140), 118)
	var minimap := Rect2(map_plane.position + Vector2(4, 7) * minimap_scale, Vector2(219, 109) * minimap_scale)
	return {
		"viewport": viewport_size,
		"source_width": 1024,
		"expanded": width > 1024.0,
		"narrow": narrow,
		"top": Rect2(0, 0, width, top_height),
		"world": Rect2(0, top_height, width, maxf(1, panel_top - top_height)),
		"bottom": bottom,
		"command": command,
		"selection": selection,
		"production": production,
		"minimap": minimap,
		"minimap_plane": map_plane,
		"minimap_scale": minimap_scale,
		"wide_split": {"left_width": 136.0, "right_width": WIDE_RIGHT_WIDTH, "right_source_x": WIDE_RIGHT_SOURCE_X},
	}


static func source_width_for(viewport_width: float) -> int:
	if viewport_width < 720.0:
		return 640
	if viewport_width < 912.0:
		return 800
	return 1024


static func shell_asset_name(source_width: int, style_index: int = 0) -> String:
	return "hud_shell_%d_%d" % [source_width, clampi(style_index, 0, 4)]
