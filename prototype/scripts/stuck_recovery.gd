class_name RoRStuckRecovery

const LOCAL_REPATH_TICK: int = 6
const PRIORITY_BOOST_TICK: int = 12
const GLOBAL_REPATH_TICK: int = 18
const STOP_TICK: int = 30


static func update(unit: Dictionary, progress_distance: float) -> String:
	if progress_distance > 0.001:
		unit["stuck_ticks"] = 0
		unit["push_priority"] = int(unit.get("base_push_priority", unit.get("push_priority", 1)))
		if String(unit.get("diagnostic_reason", "")).begins_with("stuck_"):
			unit["diagnostic_reason"] = ""
		return ""
	unit["stuck_ticks"] = int(unit.get("stuck_ticks", 0)) + 1
	match int(unit["stuck_ticks"]):
		LOCAL_REPATH_TICK:
			unit["diagnostic_reason"] = "stuck_local_repath"
			return "local_repath"
		PRIORITY_BOOST_TICK:
			unit["push_priority"] = int(unit.get("base_push_priority", unit.get("push_priority", 1))) + 2
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
	unit["stuck_ticks"] = 0
	unit["push_priority"] = int(unit.get("base_push_priority", unit.get("push_priority", 1)))
