class_name RoRInterfaceLayout
extends RefCounted

const TOP_HEIGHT := 20.0
const BOTTOM_HEIGHT := 126.0
const REFERENCE_WIDTHS := [640, 800, 1024]
const WIDE_LEFT_WIDTH := 304.0
const WIDE_RIGHT_WIDTH := 308.0
const WIDE_RIGHT_SOURCE_X := 716.0

const REFERENCE_REGIONS := {
	640: {
		"command": Rect2(136, 4, 270, 118),
		"selection": Rect2(4, 4, 128, 118),
		"minimap": Rect2(412, 4, 220, 114),
	},
	800: {
		"command": Rect2(136, 4, 270, 118),
		"selection": Rect2(4, 4, 128, 118),
		"minimap": Rect2(572, 4, 220, 114),
	},
	1024: {
		"command": Rect2(136, 4, 270, 118),
		"selection": Rect2(4, 4, 128, 118),
		"minimap": Rect2(796, 4, 220, 114),
	},
}


static func for_viewport(viewport_size: Vector2) -> Dictionary:
	var source_width := source_width_for(viewport_size.x)
	var panel_top := viewport_size.y - BOTTOM_HEIGHT
	var regions: Dictionary = REFERENCE_REGIONS[source_width]
	var command: Rect2 = regions["command"]
	var selection: Rect2 = regions["selection"]
	var minimap: Rect2 = regions["minimap"]
	var expanded := viewport_size.x > 1024.0
	if expanded:
		command = Rect2(command.position, command.size)
		minimap = Rect2(Vector2(viewport_size.x - (1024.0 - minimap.position.x), minimap.position.y), minimap.size)
		selection = Rect2(selection.position, selection.size)
	elif viewport_size.x < float(source_width):
		var clipped_width := maxf(320.0, viewport_size.x)
		var factor := clipped_width / float(source_width)
		command = Rect2(command.position * factor, command.size * Vector2(factor, 1.0))
		selection = Rect2(selection.position * Vector2(factor, 1.0), selection.size * Vector2(factor, 1.0))
		minimap = Rect2(minimap.position * Vector2(factor, 1.0), minimap.size * Vector2(factor, 1.0))
	var bottom_origin := Vector2(0.0, panel_top)
	return {
		"viewport": viewport_size,
		"source_width": source_width,
		"expanded": expanded,
		"top": Rect2(0.0, 0.0, viewport_size.x, TOP_HEIGHT),
		"world": Rect2(0.0, TOP_HEIGHT, viewport_size.x, maxf(1.0, viewport_size.y - TOP_HEIGHT - BOTTOM_HEIGHT)),
		"status_overlay": Rect2(maxf(0.0, viewport_size.x - 148.0), TOP_HEIGHT + 6.0, 140.0, 37.0),
		"bottom": Rect2(0.0, panel_top, viewport_size.x, BOTTOM_HEIGHT),
		"command": Rect2(command.position + bottom_origin, command.size),
		"selection": Rect2(selection.position + bottom_origin, selection.size),
		"minimap": Rect2(minimap.position + bottom_origin, minimap.size),
		"wide_split": {
			"left_width": WIDE_LEFT_WIDTH,
			"right_width": WIDE_RIGHT_WIDTH,
			"right_source_x": WIDE_RIGHT_SOURCE_X,
		},
	}


static func source_width_for(viewport_width: float) -> int:
	if viewport_width < 720.0:
		return 640
	if viewport_width < 912.0:
		return 800
	return 1024


static func shell_asset_name(source_width: int, style_index: int = 0) -> String:
	return "hud_shell_%d_%d" % [source_width, clampi(style_index, 0, 4)]
