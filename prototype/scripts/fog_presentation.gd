class_name RoRFogPresentation
extends RefCounted

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")

# Unknown terrain must not leak through the shroud. Explored terrain remains
# deliberately readable while current visibility is represented by no overlay.
const UNKNOWN_WORLD_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_WORLD_COLOR := Color(0.035, 0.045, 0.055, 0.48)
const UNKNOWN_MINIMAP_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_MINIMAP_COLOR := Color(0.025, 0.035, 0.045, 0.58)


static func color_for_state(state: int, minimap: bool = false) -> Color:
	if state == FogOfWar.UNKNOWN:
		return UNKNOWN_MINIMAP_COLOR if minimap else UNKNOWN_WORLD_COLOR
	return EXPLORED_MINIMAP_COLOR if minimap else EXPLORED_WORLD_COLOR


static func terrain_conforming_run_polygon(run: Dictionary, projector: Callable, snap_to_pixels: bool = true) -> PackedVector2Array:
	var y := int(run.get("y", 0))
	var x_from := int(run.get("x_from", 0))
	var x_to := int(run.get("x_to", x_from))
	if not projector.is_valid() or x_to <= x_from:
		return PackedVector2Array()
	# Sampling every cell boundary keeps the shroud attached to the elevation
	# mesh. A four-corner row quad opens gaps when intermediate vertices differ
	# in height. Collinear projected samples are then removed, so flat runs keep
	# the old four-vertex cost without losing any elevation bend.
	var top := PackedVector2Array()
	for x in range(x_from, x_to + 1):
		top.append(_project(Vector2(x, y), projector, snap_to_pixels))
	var bottom := PackedVector2Array()
	for x in range(x_to, x_from - 1, -1):
		bottom.append(_project(Vector2(x, y + 1), projector, snap_to_pixels))
	var points := _simplify_chain(top)
	points.append_array(_simplify_chain(bottom))
	return points


static func _simplify_chain(source: PackedVector2Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in source:
		while result.size() >= 2:
			var previous := result[result.size() - 2]
			var current := result[result.size() - 1]
			if absf((current - previous).cross(point - current)) > 0.0001:
				break
			result.remove_at(result.size() - 1)
		result.append(point)
	return result


static func _project(world: Vector2, projector: Callable, snap_to_pixels: bool) -> Vector2:
	var screen: Vector2 = projector.call(world)
	return PixelScaling.snap_screen(screen) if snap_to_pixels else screen
