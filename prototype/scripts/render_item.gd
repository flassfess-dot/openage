class_name RoRRenderItem

enum Layer {
	TERRAIN,
	DECAL,
	SELECTION,
	SHADOW,
	UNIT_BUILDING,
	PROJECTILE_EFFECT,
	AIRBORNE,
	HEALTH_BAR,
	WORLD_MESSAGE,
	UI,
}

const REQUIRED_FIELDS := [
	"layer",
	"elevation",
	"world_anchor",
	"screen_y",
	"stable_id",
	"frame",
	"hotspot",
	"player_color",
	"opacity",
]


static func create(kind: String, layer: int, world_anchor: Vector2, screen_position: Vector2, stable_id: int, data: Variant = null, frame_info: Dictionary = {}, elevation: float = 0.0, player_color: Color = Color.WHITE, opacity: float = 1.0, sub_order: int = 0) -> Dictionary:
	return {
		"kind": kind,
		"layer": layer,
		"elevation": elevation,
		"world_anchor": world_anchor,
		"screen_position": screen_position,
		"screen_y": screen_position.y,
		"stable_id": stable_id,
		"frame": int(frame_info.get("frame_index", 0)),
		"hotspot": frame_info.get("hotspot", Vector2.ZERO),
		"player_color": player_color,
		"opacity": clampf(opacity, 0.0, 1.0),
		"sub_order": sub_order,
		"data": data,
		"frame_info": frame_info,
	}


static func less(left: Dictionary, right: Dictionary) -> bool:
	if int(left["layer"]) != int(right["layer"]):
		return int(left["layer"]) < int(right["layer"])
	if not is_equal_approx(float(left["screen_y"]), float(right["screen_y"])):
		return float(left["screen_y"]) < float(right["screen_y"])
	if not is_equal_approx(float(left["elevation"]), float(right["elevation"])):
		return float(left["elevation"]) < float(right["elevation"])
	if int(left["stable_id"]) != int(right["stable_id"]):
		return int(left["stable_id"]) < int(right["stable_id"])
	return int(left.get("sub_order", 0)) < int(right.get("sub_order", 0))


static func color_for_team(team: int) -> Color:
	match team:
		1: return Color("4a7fda")
		2: return Color("d75a50")
		_: return Color.WHITE
