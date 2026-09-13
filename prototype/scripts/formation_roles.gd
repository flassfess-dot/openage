class_name RoRFormationRoles

const HEAVY_INFANTRY := "heavy_infantry"
const LIGHT_INFANTRY := "light_infantry"
const RANGED := "ranged"
const PRIEST := "priest"
const SIEGE := "siege"
const CIVILIAN := "civilian"


static func role_for(kind: String) -> String:
	var normalized := kind.to_lower()
	if normalized in ["archer", "bowman", "slinger", "chariot_archer"] or "archer" in normalized:
		return RANGED
	if "priest" in normalized or "healer" in normalized:
		return PRIEST
	if "catapult" in normalized or "ballista" in normalized or "helepolis" in normalized or "stone_thrower" in normalized or "siege" in normalized:
		return SIEGE
	if normalized in ["villager", "trade_boat", "fishing_boat"]:
		return CIVILIAN
	if normalized in ["clubman", "swordsman", "hoplite", "phalanx", "legion"]:
		return HEAVY_INFANTRY
	return LIGHT_INFANTRY


static func slot_cost(kind: String, slot: Dictionary, slots: Array) -> float:
	if slots.is_empty():
		return 0.0
	var front := -INF
	var back := INF
	var widest := 0.0
	for candidate in slots:
		var local: Vector2 = candidate.get("local", candidate.get("world", Vector2.ZERO))
		front = maxf(front, local.y)
		back = minf(back, local.y)
		widest = maxf(widest, absf(local.x))
	var position: Vector2 = slot.get("local", slot.get("world", Vector2.ZERO))
	var middle := (front + back) * 0.5
	match role_for(kind):
		HEAVY_INFANTRY:
			return (front - position.y) * 4.0 + absf(position.x) * 0.05
		RANGED:
			return (position.y - back) * 4.0
		PRIEST:
			return absf(position.x) * 4.0 + absf(position.y - middle)
		SIEGE:
			return (widest - absf(position.x)) * 4.0 + (position.y - back)
		CIVILIAN:
			return absf(position.y - middle) + absf(position.x) * 0.25
		_:
			return absf(position.y - middle)
