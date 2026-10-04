class_name RoRMobileCollision


static func is_solid_animal(unit: Dictionary) -> bool:
	if unit.has("solid_animal"):
		return bool(unit["solid_animal"])
	var tags: Array = unit.get("behavior_tags", [])
	return "predator" in tags or "huntable" in tags or String(unit.get("kind", "")) in ["gazelle", "elephant", "lion", "alligator", "crocodile"] and int(unit.get("team", 0)) == 0


static func constrain(unit: Dictionary, velocity: Vector2, neighbors: Array, delta: float) -> Vector2:
	if delta <= 0.0:
		return velocity
	var origin := Vector2(unit["pos"])
	var solid_self := is_solid_animal(unit)
	var original_velocity := velocity
	for other in neighbors:
		if float(other.get("hp", 0.0)) <= 0.0 or not (solid_self or is_solid_animal(other)):
			continue
		var center := Vector2(other.get("previous_pos", other["pos"]))
		var gap := origin - center
		var radius := float(unit["footprint_radius"]) + float(other["footprint_radius"]) + 0.03
		var step := velocity * delta
		if not _crosses(gap, step, radius):
			continue
		# Try a tangent, then stop. Existing overlapping scenario spawns may escape.
		var normal := gap.normalized()
		velocity -= normal * minf(0.0, velocity.dot(normal))
		if _crosses(gap, velocity * delta, radius):
			velocity = Vector2.ZERO
	if velocity.is_equal_approx(original_velocity):
		return velocity
	# The tangent of a later neighbor must not violate an earlier neighbor.
	for other in neighbors:
		if float(other.get("hp", 0.0)) > 0.0 and (solid_self or is_solid_animal(other)):
			var gap := origin - Vector2(other.get("previous_pos", other["pos"]))
			var radius := float(unit["footprint_radius"]) + float(other["footprint_radius"]) + 0.03
			if _crosses(gap, velocity * delta, radius):
				return Vector2.ZERO
	return velocity


static func _crosses(gap: Vector2, step: Vector2, radius: float) -> bool:
	if step.length_squared() <= 0.000001:
		return false
	if gap.length_squared() < radius * radius:
		return gap.dot(step) < -0.000001
	var fraction := clampf(-gap.dot(step) / step.length_squared(), 0.0, 1.0)
	return (gap + step * fraction).length_squared() < radius * radius - 0.000001
