class_name RoRFormationPreview

const Selection := preload("res://scripts/formation_selection.gd")
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


static func build_selection(units: Array, groups: Dictionary, destination: Vector2, forward: Vector2) -> Dictionary:
	if units.is_empty() or forward.length_squared() <= 0.0001:
		return {}
	var center := Vector2.ZERO
	var batches: Dictionary = {}
	for unit in units:
		center += Vector2(unit["pos"])
		var key := "%d:%s" % [int(unit.get("formation_group_id", -1)), Selection.type_for(unit, groups)]
		if not batches.has(key): batches[key] = []
		batches[key].append(unit)
	center /= float(units.size())
	var slots: Array[Vector2] = []
	var keys: Array = batches.keys()
	keys.sort()
	for key in keys:
		var members: Array = batches[key]
		var batch_center := Vector2.ZERO
		var spacing := 1.0
		for unit in members:
			batch_center += Vector2(unit["pos"])
			spacing = maxf(spacing, float(unit.get("footprint_radius", 0.3)) * 2.0 + float(unit.get("minimum_clearance", 0.0)) + 0.08)
		batch_center /= float(members.size())
		var target := destination + batch_center - center if batches.size() > 1 else destination
		var preview := build(members.size(), Selection.type_for(members[0], groups), target, forward, spacing)
		slots.append_array(preview["slots"])
	var direction := forward.normalized()
	var right := Vector2(direction.y, -direction.x)
	var tip := destination + direction * 1.6
	return {"slots": slots, "heading": [destination, tip, tip - direction * 0.4 + right * 0.3, tip - direction * 0.4 - right * 0.3]}
