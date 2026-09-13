class_name RoRFormationCombat

const MELEE_RANGE_THRESHOLD: float = 1.0
const CONTACT_ARC_STEP: float = PI / 4.0
const RANGED_LATERAL_SPACING: float = 0.75


static func role_for(unit: Dictionary) -> String:
	return "ranged" if float(unit.get("attack_range", 0.0)) > MELEE_RANGE_THRESHOLD else "melee"


static func destination(unit: Dictionary, target: Dictionary) -> Vector2:
	var approach: Vector2 = unit.get("combat_approach", unit["pos"] - target["pos"])
	if approach.length_squared() <= 0.0001:
		approach = Vector2(-1, 0)
	approach = approach.normalized()
	var lateral := Vector2(-approach.y, approach.x)
	var index := int(unit.get("combat_slot_index", 0))
	if role_for(unit) == "ranged":
		var count := maxi(1, int(unit.get("combat_slot_count", 1)))
		var offset := (float(index) - float(count - 1) * 0.5) * RANGED_LATERAL_SPACING
		var minimum_range := float(unit.get("components", {}).get("combat", {}).get("range_min", 0.0))
		var occupied_radius := float(target.get("footprint_radius", 0.3)) + float(unit.get("footprint_radius", 0.3))
		var stand_off := maxf(maxf(1.2, float(unit.get("attack_range", 1.2)) * 0.82), minimum_range + occupied_radius + 0.15)
		return target["pos"] + approach * stand_off + lateral * offset
	var ring := index / 8
	var position_in_ring := index % 8
	var signed_step := 0
	if position_in_ring > 0:
		signed_step = (position_in_ring + 1) / 2
		if position_in_ring % 2 == 0:
			signed_step = -signed_step
	var angle := float(signed_step) * CONTACT_ARC_STEP
	var target_radius := float(target.get("footprint_radius", 0.3))
	var unit_radius := float(unit.get("footprint_radius", 0.3))
	var contact_radius := target_radius + unit_radius + 0.08 + float(ring) * (unit_radius * 2.0 + 0.12)
	return target["pos"] + approach.rotated(angle) * contact_radius


static func assign_slots(units: Array, target: Dictionary) -> void:
	var melee: Array = []
	var ranged: Array = []
	var ordered := units.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	for unit in ordered:
		if role_for(unit) == "ranged":
			ranged.append(unit)
		else:
			melee.append(unit)
	_assign_role_slots(melee, target, "melee")
	_assign_role_slots(ranged, target, "ranged")


static func _assign_role_slots(units: Array, target: Dictionary, role: String) -> void:
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var approach: Vector2 = unit["pos"] - target["pos"]
		if approach.length_squared() <= 0.0001:
			var formation_forward: Vector2 = unit.get("formation_forward", Vector2(1, 0))
			approach = -formation_forward if formation_forward.length_squared() > 0.0001 else Vector2(-1, 0)
		unit["combat_role"] = role
		unit["combat_slot_index"] = index
		unit["combat_slot_count"] = units.size()
		unit["combat_approach"] = approach.normalized()
		unit["combat_destination"] = destination(unit, target)
