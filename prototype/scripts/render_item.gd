class_name RoRRenderItem

const PlayerPalette := preload("res://scripts/player_palette.gd")

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
		"wall_depth_tie": data is Dictionary and String(data.get("kind", "")) == "wall",
		"data": data,
		"frame_info": frame_info,
	}


static func less(left: Dictionary, right: Dictionary) -> bool:
	if int(left["layer"]) != int(right["layer"]):
		return int(left["layer"]) < int(right["layer"])
	return less_same_layer(left, right)


static func less_same_layer(left: Dictionary, right: Dictionary) -> bool:
	if not is_equal_approx(float(left["screen_y"]), float(right["screen_y"])):
		return float(left["screen_y"]) < float(right["screen_y"])
	if not is_equal_approx(float(left["elevation"]), float(right["elevation"])):
		return float(left["elevation"]) < float(right["elevation"])
	if int(left.get("sub_order", 0)) != int(right.get("sub_order", 0)):
		return int(left.get("sub_order", 0)) < int(right.get("sub_order", 0))
	# Neighboring wall sprites share edge pixels at equal projected depth.
	# Resolve them spatially so creating the same rows in reverse is identical.
	var left_wall := bool(left.get("wall_depth_tie", false))
	var right_wall := bool(right.get("wall_depth_tie", false))
	if left_wall != right_wall:
		return left_wall
	if left_wall:
		var left_anchor: Vector2 = left["world_anchor"]
		var right_anchor: Vector2 = right["world_anchor"]
		if not is_equal_approx(left_anchor.x, right_anchor.x):
			return left_anchor.x < right_anchor.x
		if not is_equal_approx(left_anchor.y, right_anchor.y):
			return left_anchor.y < right_anchor.y
	if int(left["stable_id"]) != int(right["stable_id"]):
		return int(left["stable_id"]) < int(right["stable_id"])
	return false


static func color_for_team(team: int) -> Color:
	return PlayerPalette.shade(clampi(team, 1, 8), 3) if team > 0 else Color.WHITE
