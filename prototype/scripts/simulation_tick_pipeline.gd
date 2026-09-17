class_name RoRSimulationTickPipeline
extends RefCounted

var active_systems: Array[Dictionary] = []
var completed_systems: Array[Dictionary] = []
var performance_probe: Variant = null


func clear() -> void:
	active_systems.clear()
	completed_systems.clear()


func set_performance_probe(probe: Variant) -> void:
	performance_probe = probe


func add_active(system_name: String, executor: Callable) -> void:
	_add(active_systems, system_name, executor)


func add_completed(system_name: String, executor: Callable) -> void:
	_add(completed_systems, system_name, executor)


func run(match_completed: bool, context: Dictionary) -> Array[String]:
	var executed: Array[String] = []
	var systems: Array[Dictionary] = completed_systems if match_completed else active_systems
	for system in systems:
		var executor: Callable = system["executor"]
		assert(executor.is_valid(), "Invalid simulation system executor: %s" % system["name"])
		var started := Time.get_ticks_usec() if performance_probe != null else 0
		executor.call(context)
		if performance_probe != null:
			performance_probe.observe_microseconds("simulation.system.%s" % String(system["name"]), Time.get_ticks_usec() - started)
		executed.append(String(system["name"]))
	return executed


func system_order(match_completed: bool = false) -> Array[String]:
	var result: Array[String] = []
	var systems: Array[Dictionary] = completed_systems if match_completed else active_systems
	for system in systems:
		result.append(String(system["name"]))
	return result


func _add(target: Array[Dictionary], system_name: String, executor: Callable) -> void:
	assert(not system_name.is_empty(), "Simulation system name must not be empty")
	assert(executor.is_valid(), "Simulation system executor must be valid")
	for existing in target:
		assert(String(existing["name"]) != system_name, "Duplicate simulation system: %s" % system_name)
	target.append({"name": system_name, "executor": executor})
