class_name RoRDiagnostics


static func unit_snapshot(unit: Dictionary, fixed_step_seconds: float) -> Dictionary:
	var position: Vector2 = unit["pos"]
	var previous_position: Vector2 = unit.get("previous_pos", position)
	var target: Vector2 = unit.get("target", position)
	var actual_velocity: Vector2 = unit.get("actual_velocity", Vector2.ZERO)
	if not unit.has("actual_velocity") and fixed_step_seconds > 0.0:
		actual_velocity = (position - previous_position) / fixed_step_seconds

	var desired_velocity: Vector2 = unit.get("desired_velocity", Vector2.ZERO)
	if not unit.has("desired_velocity") and String(unit.get("task", "idle")) in ["move", "attack", "gather"]:
		var difference := target - position
		if difference.length_squared() > 0.0001:
			desired_velocity = difference.normalized() * float(unit.get("speed", 0.0))

	return {
		"id": int(unit.get("id", -1)),
		"position": position,
		"target": target,
		"footprint_radius": float(unit.get("footprint_radius", 0.31)),
		"actual_velocity": actual_velocity,
		"desired_velocity": desired_velocity,
		"facing": int(unit.get("facing", 0)),
		"movement_facing": int(unit.get("movement_facing", unit.get("facing", 0))),
		"desired_facing": int(unit.get("desired_facing", unit.get("facing", 0))),
		"action_facing": int(unit.get("action_facing", unit.get("facing", 0))),
		"path_request_id": int(unit.get("path_request_id", 0)),
		"path_status": String(unit.get("path_status", "idle")),
		"path_grid_revision": int(unit.get("path_grid_revision", -1)),
		"order": String(unit.get("task", "idle")),
		"animation": String(unit.get("anim_state", "idle")),
		"stance": String(unit.get("stance", "passive")),
		"target_id": int(unit.get("target_id", -1)),
		"acquisition_range": float(unit.get("acquisition_range", 0.0)),
		"chase_range": float(unit.get("chase_range", 0.0)),
		"attack_autonomous": bool(unit.get("attack_autonomous", false)),
		"formation_group_id": int(unit.get("formation_group_id", -1)),
		"formation_slot_id": int(unit.get("formation_slot_id", -1)),
		"formation_slot_mode": String(unit.get("formation_slot_mode", "none")),
		"diagnostic_reason": String(unit.get("diagnostic_reason", "")),
	}
