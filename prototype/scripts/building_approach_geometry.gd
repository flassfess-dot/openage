extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")

static func perimeter_candidates(worker: Dictionary, building: Dictionary, map_size: Vector2i) -> Array[Vector2]:
	var half_size: Vector2 = building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))
	# Keep all mobile-radius probes outside the whole navigation cell occupied by
	# the building. Half-cell clearance is required even when the visual polygon
	# itself ends earlier inside that cell.
	var padding := float(worker.get("footprint_radius", 0.3)) + 0.55
	var side_fractions := [-0.75, -0.25, 0.25, 0.75]
	var offsets: Array[Vector2] = []
	for fraction in side_fractions:
		offsets.append(Vector2(float(fraction) * half_size.x, -half_size.y - padding))
		offsets.append(Vector2(half_size.x + padding, float(fraction) * half_size.y))
		offsets.append(Vector2(float(fraction) * half_size.x, half_size.y + padding))
		offsets.append(Vector2(-half_size.x - padding, float(fraction) * half_size.y))
	var result: Array[Vector2] = []
	for offset in offsets:
		result.append(Coordinates.clamp_world(Vector2(building["pos"]) + offset, map_size))
	return result
