class_name RoRStuckRecovery

const LOCAL_REPATH_TICK: int = 6
const PRIORITY_BOOST_TICK: int = 12
const GLOBAL_REPATH_TICK: int = 18
const STOP_TICK: int = 30


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
	if int(unit["stuck_ticks"]) != 0:
		unit["stuck_ticks"] = 0
	var base_priority := int(unit["base_push_priority"])
	if int(unit["push_priority"]) != base_priority:
		unit["push_priority"] = base_priority
