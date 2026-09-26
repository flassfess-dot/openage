class_name RoRProjectileMotion

const Coordinates := preload("res://scripts/coordinates.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")


static func spawn_position(attacker: Dictionary, target_position: Vector2, weapon_offset: Array) -> Vector2:
	var origin: Vector2 = attacker.get("pos", Vector2.ZERO)
	var forward := (target_position - origin).normalized()
	if forward == Vector2.ZERO:
		forward = Vector2(0.0, -1.0)
	var right := Vector2(-forward.y, forward.x)
	var lateral := float(weapon_offset[0]) if weapon_offset.size() > 0 else 0.0
	var forward_offset := float(weapon_offset[1]) if weapon_offset.size() > 1 else 0.0
	return origin + right * lateral + forward * forward_offset


static func aim_position(attacker: Dictionary, target: Dictionary, projectile_speed: float, smart_mode: bool, accuracy: int, projectile_entity_id: int) -> Dictionary:
	var origin: Vector2 = attacker.get("pos", Vector2.ZERO)
	var target_position: Vector2 = target.get("pos", Vector2.ZERO)
	if smart_mode and projectile_speed > 0.0:
		var travel_time := origin.distance_to(target_position) / projectile_speed
		var target_velocity: Vector2 = target.get("actual_velocity", Vector2.ZERO)
		target_position += target_velocity * travel_time
	var roll := posmod(projectile_entity_id * 1103515245 + int(attacker.get("id", 0)) * 12345 + int(target.get("id", 0)) * 2654435761, 100)
	var accurate := roll < clampi(accuracy, 0, 100)
	if not accurate:
		var direction := (target_position - origin).normalized()
		if direction == Vector2.ZERO:
			direction = Vector2.RIGHT
		var side := -1.0 if posmod(projectile_entity_id + int(target.get("id", 0)), 2) == 0 else 1.0
		var miss_distance := maxf(0.5, float(target.get("footprint_radius", 0.3)) * 2.0 + 0.2)
		target_position += Vector2(-direction.y, direction.x) * miss_distance * side
	return {"position": target_position, "accurate": accurate, "roll": roll}


static func advance(projectile: Dictionary, delta: float) -> bool:
	projectile["previous_pos"] = projectile["pos"]
	projectile["previous_visual_height"] = float(projectile.get("visual_height", 0.0))
	var destination: Vector2 = projectile["target_position"]
	var difference: Vector2 = destination - projectile["pos"]
	var movement := maxf(0.0, float(projectile.get("speed", 0.0))) * maxf(0.0, delta)
	var arrived := difference.length() <= movement or difference.length_squared() <= 0.000001
	if arrived:
		projectile["pos"] = destination
	else:
		projectile["pos"] += difference.normalized() * movement
	projectile["elapsed"] = float(projectile.get("elapsed", 0.0)) + maxf(0.0, delta)
	var total_distance := maxf(0.0001, float(projectile.get("total_distance", 0.0001)))
	var travelled := Vector2(projectile["origin"]).distance_to(Vector2(projectile["pos"]))
	var progress := clampf(travelled / total_distance, 0.0, 1.0)
	var ground_elevation := lerpf(float(projectile.get("origin_elevation", 0.0)), float(projectile.get("target_elevation", 0.0)), progress)
	var launch_height := float(projectile.get("launch_height", 0.0)) * (1.0 - progress)
	var arc_height := 4.0 * absf(float(projectile.get("arc", 0.0))) * total_distance * progress * (1.0 - progress)
	projectile["visual_height"] = launch_height + arc_height
	projectile["elevation"] = ground_elevation + float(projectile["visual_height"])
	return arrived


static func logical_facing(projectile: Dictionary, angle_count: int = 72) -> int:
	var position := Vector2(projectile.get("pos", Vector2.ZERO))
	var previous := Vector2(projectile.get("previous_pos", position))
	var screen_direction := Coordinates.iso_raw(position - previous)
	var height_delta := float(projectile.get("visual_height", 0.0)) - float(projectile.get("previous_visual_height", projectile.get("visual_height", 0.0)))
	screen_direction.y -= height_delta * TerrainElevation.ELEVATION_PIXEL_STEP
	if screen_direction.length_squared() <= 0.000001:
		screen_direction = Coordinates.iso_raw(Vector2(projectile.get("target_position", Vector2.ZERO)) - position)
	if screen_direction.length_squared() <= 0.000001:
		return 0
	return FacingConvention.logical_for_screen(screen_direction, angle_count)
