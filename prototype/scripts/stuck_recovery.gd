class_name RoRStuckRecovery

const LOCAL_REPATH_TICK: int = 6
const PRIORITY_BOOST_TICK: int = 12
const GLOBAL_REPATH_TICK: int = 18
const STOP_TICK: int = 30


# Measure forward progress along the active leg, rather than velocity. A
# circling actor moves every tick but cannot improve its best leg distance.
# Replanning the same order does not reset the escalation budget.
static func update_route_progress(unit: Dictionary) -> String:
	var goal: Vector2 = unit.get("destination", unit["target"])
	var leg: Vector2 = unit["target"]
	var revision := int(unit.get("components", {}).get("order", {}).get("revision", 0))
	var distance := Vector2(unit["pos"]).distance_to(leg)
	var watch: Dictionary = unit.get("navigation_progress", {})
	if watch.is_empty() or (revision == 0 and Vector2(watch["goal"]).distance_squared_to(goal) > 0.01) or int(watch["order_revision"]) != revision:
		reset(unit)
		watch = {"goal": goal, "leg": leg, "best": distance, "order_revision": revision}
		unit["navigation_progress"] = watch
		return ""
	if Vector2(watch["leg"]).distance_squared_to(leg) > 0.0001:
		var forward := float(watch["best"]) - Vector2(unit["pos"]).distance_to(Vector2(watch["leg"]))
		watch["leg"] = leg
		watch["best"] = distance
		return update_squared(unit, forward * forward if forward >= 0.015 else 0.0)
	var improvement := float(watch["best"]) - distance
	# Accumulate slow forward movement instead of requiring a minimum speed.
	if improvement >= 0.015:
		watch["best"] = distance
		return update_squared(unit, improvement * improvement)
	return update_squared(unit, 0.0)


static func update(unit: Dictionary, progress_distance: float) -> String:
	return update_squared(unit, progress_distance * progress_distance)


static func update_squared(unit: Dictionary, progress_distance_squared: float) -> String:
	if progress_distance_squared > 0.000001:
		if int(unit["stuck_ticks"]) != 0:
			unit["stuck_ticks"] = 0
		var base_priority := int(unit["base_push_priority"])
		if int(unit["push_priority"]) != base_priority:
			unit["push_priority"] = base_priority
		var reason := String(unit["diagnostic_reason"])
		if not reason.is_empty() and reason.begins_with("stuck_"):
			unit["diagnostic_reason"] = ""
		return ""
	unit["stuck_ticks"] = int(unit["stuck_ticks"]) + 1
	match int(unit["stuck_ticks"]):
		LOCAL_REPATH_TICK:
			unit["diagnostic_reason"] = "stuck_local_repath"
			return "local_repath"
		PRIORITY_BOOST_TICK:
			unit["push_priority"] = int(unit["base_push_priority"]) + 2
			unit["diagnostic_reason"] = "stuck_priority_boost"
			return "priority_boost"
		GLOBAL_REPATH_TICK:
			unit["diagnostic_reason"] = "stuck_global_repath"
			return "global_repath"
		STOP_TICK:
			unit["diagnostic_reason"] = "stuck_stopped_nearest_valid"
			return "stop"
	return ""


static func reset(unit: Dictionary) -> void:
	unit.erase("navigation_progress")
	if int(unit["stuck_ticks"]) != 0:
		unit["stuck_ticks"] = 0
	var base_priority := int(unit["base_push_priority"])
	if int(unit["push_priority"]) != base_priority:
		unit["push_priority"] = base_priority
