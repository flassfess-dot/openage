class_name RoRNavigationService
extends RefCounted

var pathfinder: Variant
var next_request_id: int = 1
var results_by_request: Dictionary = {}


func _init(pathfinder_instance: Variant = null) -> void:
	pathfinder = pathfinder_instance


func set_pathfinder(pathfinder_instance: Variant) -> void:
	pathfinder = pathfinder_instance


func reset() -> void:
	next_request_id = 1
	results_by_request.clear()


func clear_observations() -> void:
	results_by_request.clear()


func request_path(entity_id: int, start: Vector2, requested_goal: Vector2, movement_domain: String = "land", restriction_id: int = -1, purpose: String = "move") -> Dictionary:
	var request_id := next_request_id
	next_request_id += 1
	var grid_revision := int(pathfinder.grid.revision) if pathfinder != null and pathfinder.grid != null else -1
	var path: Array[Vector2] = []
	if pathfinder != null:
		path = pathfinder.find_path(start, requested_goal, movement_domain, restriction_id)
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
		"grid_revision": grid_revision,
		"status": status,
		"reason": "" if status == "resolved" else "no_path",
		"path": path.duplicate(),
	}
	results_by_request[request_id] = result.duplicate(true)
	return result


func result_for(request_id: int) -> Dictionary:
	return results_by_request.get(request_id, {}).duplicate(true)
