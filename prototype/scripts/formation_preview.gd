class_name RoRFormationPreview

const Geometry := preload("res://scripts/formation_geometry.gd")


static func build(member_count: int, formation_type: String, destination: Vector2, forward: Vector2, spacing: float = 1.0) -> Dictionary:
	if member_count <= 0 or forward.length_squared() <= 0.0001:
		return {}
	var normalized_forward := forward.normalized()
	var local := Geometry.local_slots(member_count, formation_type, spacing)
	return {
		"destination": destination,
		"forward": normalized_forward,
		"slots": Geometry.world_slots(local, destination, normalized_forward),
	}
