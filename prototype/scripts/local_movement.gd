class_name RoRLocalMovement

const Footprint := preload("res://scripts/footprint.gd")


static func calculate(unit: Dictionary, target: Vector2, neighbors: Array, navigation_grid, delta: float) -> Dictionary:
	var reason := calculate_into(unit, target, neighbors, navigation_grid, delta)
	return {"desired_velocity": unit["desired_velocity"], "actual_velocity": unit["actual_velocity"], "reason": reason}


static func calculate_into(unit: Dictionary, target: Vector2, neighbors: Array, navigation_grid, delta: float) -> String:
	var position: Vector2 = unit["pos"]
	var difference := target - position
	var speed := maxf(0.0, float(unit.get("speed", 0.0)) * float(unit.get("cohesion_speed_scale", 1.0)))
	var desired := difference.normalized() * speed if difference.length_squared() > 0.000001 else Vector2.ZERO
	var has_desired := desired.length_squared() > 0.0
	var desired_normalized := desired.normalized() if has_desired else Vector2.ZERO
	var lateral_normalized := Vector2(-desired.y, desired.x).normalized() if has_desired else Vector2.ZERO
	var unit_id := int(unit.get("id", 0))
	var own_radius := float(unit.get("footprint_radius", Footprint.DEFAULT_MOBILE_RADIUS))
	var own_clearance := float(unit.get("minimum_clearance", Footprint.DEFAULT_CLEARANCE))
	var own_priority := int(unit.get("push_priority", 1))
	var avoidance := Vector2.ZERO
	for other in neighbors:
		if float(other.get("hp", 1.0)) <= 0.0:
			continue
		var other_position: Vector2 = other.get("previous_pos", other.get("pos", position))
		var gap := position - other_position
		var distance := gap.length()
		var safe_distance := own_radius + float(other.get("footprint_radius", Footprint.DEFAULT_MOBILE_RADIUS)) + maxf(own_clearance, float(other.get("minimum_clearance", Footprint.DEFAULT_CLEARANCE)))
		if distance <= 0.0001:
			var sign_value := -1.0 if unit_id < int(other.get("id", 0)) else 1.0
			gap = Vector2(0.0, sign_value)
			distance = 0.0001
		if distance < safe_distance * 1.6:
			var strength := clampf((safe_distance * 1.6 - distance) / (safe_distance * 1.6), 0.0, 1.0)
			var gap_normalized := gap.normalized()
			var other_priority := int(other.get("push_priority", 1))
			var displacement_share := 0.5 if own_priority == other_priority else (0.75 if own_priority < other_priority else 0.25)
			avoidance += gap_normalized * speed * strength * displacement_share
			var to_other := -gap_normalized
			if has_desired and desired_normalized.dot(to_other) > 0.55:
				avoidance += lateral_normalized * speed * strength * 0.55

	var velocity := desired + avoidance
	if velocity.length() > speed and speed > 0.0:
		velocity = velocity.normalized() * speed
	var reason := ""
	if not _position_walkable(position + velocity * delta, float(unit.get("footprint_radius", 0.3)), navigation_grid, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
		reason = "local_obstacle"
		velocity = _walkable_alternative(unit, desired, position, speed, delta, navigation_grid)
		if velocity == Vector2.ZERO:
			reason = "local_blocked"
	unit["desired_velocity"] = desired
	unit["actual_velocity"] = velocity
	return reason


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
