class_name RoRPerceptionService
extends RefCounted


func query(observer: Dictionary, candidates: Array, options: Dictionary = {}) -> Array[Dictionary]:
	var observer_id := int(observer.get("id", -1))
	var observer_team := int(observer.get("team", 0))
	var observer_position := Vector2(observer.get("pos", Vector2.ZERO))
	var query_range := maxf(0.0, float(options.get("range", observer.get("acquisition_range", 0.0))))
	var visibility: Callable = options.get("visibility", Callable())
	var alliance: Callable = options.get("alliance", Callable())
	var reachability: Callable = options.get("reachability", Callable())
	var target_filter: Callable = options.get("target_filter", Callable())
	var assigned_attackers: Dictionary = options.get("assigned_attackers", {})
	var allowed_ids: Dictionary = options.get("allowed_ids", {})
	var results: Array[Dictionary] = []

	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var candidate_id := int(candidate.get("id", -1))
		var candidate_team := int(candidate.get("team", 0))
		if candidate_id < 0 or candidate_id == observer_id or float(candidate.get("hp", 0.0)) <= 0.0:
			continue
		if not allowed_ids.is_empty() and not allowed_ids.has(candidate_id):
			continue
		if candidate_team <= 0 or candidate_team == observer_team:
			continue
		if alliance.is_valid() and bool(alliance.call(observer_team, candidate_team)):
			continue
		if visibility.is_valid() and not bool(visibility.call(observer_team, candidate)):
			continue
		if target_filter.is_valid() and not bool(target_filter.call(observer, candidate)):
			continue
		var distance_squared := observer_position.distance_squared_to(Vector2(candidate.get("pos", Vector2.ZERO)))
		var combined_range := query_range + float(observer.get("footprint_radius", 0.0)) + float(candidate.get("footprint_radius", 0.0))
		if distance_squared > combined_range * combined_range + 0.000001:
			continue
		if reachability.is_valid() and not bool(reachability.call(observer, candidate)):
			continue
		results.append({
			"entity": candidate,
			"entity_id": candidate_id,
			"distance_squared": distance_squared,
			"threat_rank": _threat_rank(observer_id, candidate),
			"class_rank": _class_rank(candidate),
			"assigned_attackers": int(assigned_attackers.get(candidate_id, 0)),
		})

	results.sort_custom(_candidate_less)
	return results


func best_target(observer: Dictionary, candidates: Array, options: Dictionary = {}) -> Variant:
	var results := query(observer, candidates, options)
	return null if results.is_empty() else results[0]["entity"]


static func _candidate_less(left: Dictionary, right: Dictionary) -> bool:
	for key in ["threat_rank", "assigned_attackers", "class_rank"]:
		if int(left[key]) != int(right[key]):
			return int(left[key]) < int(right[key])
	if not is_equal_approx(float(left["distance_squared"]), float(right["distance_squared"])):
		return float(left["distance_squared"]) < float(right["distance_squared"])
	return int(left["entity_id"]) < int(right["entity_id"])


static func _threat_rank(observer_id: int, candidate: Dictionary) -> int:
	if String(candidate.get("task", "idle")) == "attack" and int(candidate.get("target_id", -1)) == observer_id:
		return 0
	return 1


static func _class_rank(candidate: Dictionary) -> int:
	var tags: Array = candidate.get("behavior_tags", [])
	if "military" in tags or ("combatant" in tags and "worker" not in tags):
		return 0
	if "worker" in tags:
		return 1
	if "static" in tags:
		return 2
	return 1
