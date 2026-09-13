class_name RoRFacingConvention
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")

# Genie/SLP clockwise screen convention. Only S..N are stored for the usual
# 8-angle/mirroring-mode-6 sprites; NE..SE mirror source blocks 3..1.
const LABELS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]


static func logical_for_world(direction: Vector2, angle_count: int = 8) -> int:
	return logical_for_screen(Coordinates.iso_raw(direction), angle_count)


static func logical_for_screen(direction: Vector2, angle_count: int = 8) -> int:
	if direction.length_squared() <= 0.0001:
		return 0
	var count := maxi(1, angle_count)
	# Positive screen X is east/right, while increasing logical SLP angles from
	# south rotate toward west/left. Negating X is therefore intentional.
	var angle := atan2(-direction.x, direction.y)
	return posmod(roundi(angle / (TAU / float(count))), count)


static func screen_vector(logical_facing: int, angle_count: int = 8) -> Vector2:
	var count := maxi(1, angle_count)
	var angle := float(posmod(logical_facing, count)) * TAU / float(count)
	return Vector2(-sin(angle), cos(angle))


static func label(logical_facing: int) -> String:
	return LABELS[posmod(logical_facing, LABELS.size())]
