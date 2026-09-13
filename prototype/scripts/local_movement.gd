class_name RoRLocalMovement

const Footprint := preload("res://scripts/footprint.gd")


static func calculate(unit: Dictionary, target: Vector2, neighbors: Array, navigation_grid, delta: float) -> Dictionary:
	var position: Vector2 = unit["pos"]
	var difference := target - position
	var speed := maxf(0.0, float(unit.get("speed", 0.0)) * float(unit.get("cohesion_speed_scale", 1.0)))
	var desired := difference.normalized() * speed if difference.length_squared() > 0.000001 else Vector2.ZERO
	var avoidance := Vector2.ZERO
	for other in neighbors:
		if float(other.get("hp", 1.0)) <= 0.0:
			continue
		var other_position: Vector2 = other.get("previous_pos", other.get("pos", position))
		var gap := position - other_position
		var distance := gap.length()
		var safe_distance := Footprint.separation_distance(unit, other)
		if distance <= 0.0001:
			var sign_value := -1.0 if int(unit.get("id", 0)) < int(other.get("id", 0)) else 1.0
			gap = Vector2(0.0, sign_value)
			distance = 0.0001
		if distance < safe_distance * 1.6:
			var strength := clampf((safe_distance * 1.6 - distance) / (safe_distance * 1.6), 0.0, 1.0)
			avoidance += gap.normalized() * speed * strength * Footprint.displacement_share(unit, other)
			var to_other := -gap.normalized()
			if desired.length_squared() > 0.0 and desired.normalized().dot(to_other) > 0.55:
				avoidance += Vector2(-desired.y, desired.x).normalized() * speed * strength * 0.55

	var velocity := desired + avoidance
	if velocity.length() > speed and speed > 0.0:
		velocity = velocity.normalized() * speed
	var reason := ""
	if not _position_walkable(position + velocity * delta, float(unit.get("footprint_radius", 0.3)), navigation_grid, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
		reason = "local_obstacle"
		velocity = _walkable_alternative(unit, desired, position, speed, delta, navigation_grid)
		if velocity == Vector2.ZERO:
			reason = "local_blocked"
	return {"desired_velocity": desired, "actual_velocity": velocity, "reason": reason}


static func _walkable_alternative(unit: Dictionary, desired: Vector2, position: Vector2, speed: float, delta: float, navigation_grid) -> Vector2:
	if desired.length_squared() <= 0.000001:
		return Vector2.ZERO
	var angles := [PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]
	if int(unit.get("id", 0)) % 2 == 0:
		angles = [-PI / 4.0, PI / 4.0, -PI / 2.0, PI / 2.0]
	for angle in angles:
		var candidate := desired.rotated(float(angle)).normalized() * speed
		if _position_walkable(position + candidate * delta, float(unit.get("footprint_radius", 0.3)), navigation_grid, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
			return candidate
	return Vector2.ZERO


static func _position_walkable(position: Vector2, radius: float, navigation_grid, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	if navigation_grid == null:
		return true
	return navigation_grid.is_position_walkable_for(position, radius, movement_domain, restriction_id)
