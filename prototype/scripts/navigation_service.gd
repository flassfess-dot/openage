class_name RoRNavigationService
extends RefCounted

const MAX_OBSERVED_RESULTS := 1024
var first_observed_request_id: int = 1

var pathfinder: Variant
var next_request_id: int = 1
var results_by_request: Dictionary = {}


func _init(pathfinder_instance: Variant = null) -> void:
	pathfinder = pathfinder_instance


func set_pathfinder(pathfinder_instance: Variant) -> void:
	pathfinder = pathfinder_instance


func reset() -> void:
	next_request_id = 1
	clear_observations()


func clear_observations() -> void:
	results_by_request.clear()
	first_observed_request_id = next_request_id


func _observe(result: Dictionary) -> void:
	# Request IDs remain authoritative and monotonic; old diagnostic payloads
	# are a bounded window, not an ever-growing copy of all simulation paths.
	if results_by_request.is_empty(): first_observed_request_id = int(result["request_id"])
	while results_by_request.size() >= MAX_OBSERVED_RESULTS:
		results_by_request.erase(first_observed_request_id)
		first_observed_request_id += 1
	results_by_request[int(result["request_id"])] = result.duplicate(true)


func request_paths(requests: Array, planner, coordinator) -> Array:
	var inputs: Array = []
	for request in requests:
		inputs.append({"start": request["start"], "goal": request["goal"], "domain": request["domain"], "restriction": request["restriction"], "clearance": request["clearance"]})
	var paths: Array = planner.find_paths_batch(inputs, coordinator)
	var results: Array = []
	var grid_revision := int(pathfinder.grid.revision) if pathfinder != null and pathfinder.grid != null else -1
	for index in range(requests.size()):
		var request: Dictionary = requests[index]
		var path: Array[Vector2] = []
		path.assign(paths[index])
		var result := {"request_id": next_request_id, "entity_id": request["entity_id"], "purpose": request["purpose"], "start": request["start"], "requested_goal": request["goal"], "resolved_goal": path.back() if not path.is_empty() else request["start"], "movement_domain": request["domain"], "restriction_id": request["restriction"], "clearance_radius": request["clearance"], "grid_revision": grid_revision, "status": "resolved" if not path.is_empty() else "unreachable", "reason": "" if not path.is_empty() else "no_path", "path": path}
		next_request_id += 1
		_observe(result)
		results.append(result)
	return results

func request_path(entity_id: int, start: Vector2, requested_goal: Vector2, movement_domain: String = "land", restriction_id: int = -1, purpose: String = "move", clearance_radius: float = 0.0, known_planner: Variant = null) -> Dictionary:
	var request_id := next_request_id
	next_request_id += 1
	var grid_revision := int(pathfinder.grid.revision) if pathfinder != null and pathfinder.grid != null else -1
	var path: Array[Vector2] = []
	var planner: Variant = known_planner if known_planner != null else pathfinder
	if planner != null:
		path = planner.find_path(start, requested_goal, movement_domain, restriction_id, clearance_radius)
	var status := "resolved" if not path.is_empty() else "unreachable"
	var result := {
		"request_id": request_id,
		"entity_id": entity_id,
		"purpose": purpose,
		"start": start,
		"requested_goal": requested_goal,
		"resolved_goal": path[path.size() - 1] if not path.is_empty() else start,
		"movement_domain": movement_domain,
		"restriction_id": restriction_id,
		"clearance_radius": clearance_radius,
		"grid_revision": grid_revision,
		"status": status,
		"reason": "" if status == "resolved" else "no_path",
		"path": path.duplicate(),
	}
	_observe(result)
	return result


func register_prevalidated_direct_path(entity_id: int, start: Vector2, requested_goal: Vector2, movement_domain: String = "land", restriction_id: int = -1, purpose: String = "formation_segment", clearance_radius: float = 0.0) -> Dictionary:
	var request_id := next_request_id
	next_request_id += 1
	var grid_revision := int(pathfinder.grid.revision) if pathfinder != null and pathfinder.grid != null else -1
	var path: Array[Vector2] = [requested_goal]
	var result := {
		"request_id": request_id,
		"entity_id": entity_id,
		"purpose": purpose,
		"start": start,
		"requested_goal": requested_goal,
		"resolved_goal": requested_goal,
		"movement_domain": movement_domain,
		"restriction_id": restriction_id,
		"clearance_radius": clearance_radius,
		"grid_revision": grid_revision,
		"status": "resolved",
		"reason": "",
		"path": path.duplicate(),
	}
	_observe(result)
	if pathfinder != null and pathfinder.performance_probe != null:
		pathfinder.performance_probe.increment("navigation.prevalidated_group_segments")
	return result


func result_for(request_id: int) -> Dictionary:
	return results_by_request.get(request_id, {}).duplicate(true)
