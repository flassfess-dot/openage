class_name RoRPerceptionService
extends RefCounted


func query(observer: Dictionary, candidates: Array, options: Dictionary = {}) -> Array[Dictionary]:
	var observer_id := int(observer.get("id", -1))
	var observer_team := int(observer.get("team", 0))
	var observer_position := Vector2(observer.get("pos", Vector2.ZERO))
	var query_range := maxf(0.0, float(options.get("range", observer.get("acquisition_range", 0.0))))
	var visibility: Callable = options.get("visibility", Callable())
	var alliance: Callable = options.get("alliance", Callable())
	var hostility: Callable = options.get("hostility", Callable())
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
		if hostility.is_valid() and not bool(hostility.call(observer, candidate)):
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


func best_combat_target(world, observer: Dictionary, candidates: Array, assigned_attackers: Dictionary, query_range: float, stance: String, allowed_target_id: int = -1, hostility_prevalidated: bool = false) -> Variant:
	# Reachability runs a full route query per candidate, which dominated dense
	# awareness loops. The ranking is a total order (entity ID breaks ties), so
	# when the globally best candidate is reachable it is also the best of the
	# reachable subset. Probe once; only an unreachable winner pays the exact
	# filtered rescan.
	var best: Variant = _best_combat_target_pass(world, observer, candidates, assigned_attackers, query_range, stance, allowed_target_id, hostility_prevalidated, false)
	if best == null:
		return null
	if world.can_unit_reach_entity(observer, best):
		return best
	return _best_combat_target_pass(world, observer, candidates, assigned_attackers, query_range, stance, allowed_target_id, hostility_prevalidated, true)


func _best_combat_target_pass(world, observer: Dictionary, candidates: Array, assigned_attackers: Dictionary, query_range: float, stance: String, allowed_target_id: int, hostility_prevalidated: bool, check_reachability: bool) -> Variant:
	var observer_id := int(observer.get("id", -1))
	var observer_team := int(observer.get("team", 0))
	var observer_position := Vector2(observer.get("pos", Vector2.ZERO))
	var observer_radius := float(observer.get("footprint_radius", 0.0))
	var autonomous := bool(observer.get("attack_autonomous", false))
	var leash_origin := Vector2(observer.get("combat_leash_origin", observer_position))
	var chase_range := float(observer.get("chase_range", 0.0))
	var best: Variant = null
	var best_threat_rank := 2147483647
	var best_assigned := 2147483647
	var best_class_rank := 2147483647
	var best_distance_squared := INF
	var best_id := 9223372036854775807
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		var candidate_id := int(candidate.get("id", -1))
		var candidate_team := int(candidate.get("team", 0))
		if candidate_id < 0 or candidate_id == observer_id or float(candidate.get("hp", 0.0)) <= 0.0:
			continue
		if allowed_target_id >= 0 and candidate_id != allowed_target_id:
			continue
		if candidate_team <= 0 or candidate_team == observer_team:
			continue
		if not hostility_prevalidated:
			# Resolve diplomacy once. The generic world facade performs the same
			# relation lookup both for the allied and autonomous-target predicates,
			# which is needlessly expensive in the dense awareness loop.
			var relation := String(world.team_relation(observer_team, candidate_team))
			if relation == "ally":
				continue
			if relation == "neutral":
				var tags: Array = candidate.get("behavior_tags", [])
				if not world.entity_is_static(candidate) and not ("military" in tags or ("combatant" in tags and "worker" not in tags)):
					continue
			elif relation != "enemy":
				continue
		if not world.is_entity_visible_to(observer_team, candidate):
			continue
		var candidate_position := Vector2(candidate.get("pos", Vector2.ZERO))
		var allowed_chase := chase_range + 0.0001
		if autonomous and leash_origin.distance_squared_to(candidate_position) > allowed_chase * allowed_chase:
			continue
		if stance == "stand_ground" and not world.is_unit_in_attack_range(observer, candidate):
			continue
		var distance_squared := observer_position.distance_squared_to(candidate_position)
		var combined_range := maxf(0.0, query_range) + observer_radius + float(candidate.get("footprint_radius", 0.0))
		if distance_squared > combined_range * combined_range + 0.000001:
			continue
		if check_reachability and not world.can_unit_reach_entity(observer, candidate):
			continue
		var threat_rank := _threat_rank(observer_id, candidate)
		var assigned_count := int(assigned_attackers.get(candidate_id, 0))
		var class_rank := _class_rank(candidate)
		if _combat_rank_precedes(threat_rank, assigned_count, class_rank, distance_squared, candidate_id, best_threat_rank, best_assigned, best_class_rank, best_distance_squared, best_id):
			best = candidate
			best_threat_rank = threat_rank
			best_assigned = assigned_count
			best_class_rank = class_rank
			best_distance_squared = distance_squared
			best_id = candidate_id
	return best


static func _combat_rank_precedes(threat_rank: int, assigned: int, class_rank: int, distance_squared: float, entity_id: int, best_threat_rank: int, best_assigned: int, best_class_rank: int, best_distance_squared: float, best_id: int) -> bool:
	if threat_rank != best_threat_rank:
		return threat_rank < best_threat_rank
	if assigned != best_assigned:
		return assigned < best_assigned
	if class_rank != best_class_rank:
		return class_rank < best_class_rank
	if not is_equal_approx(distance_squared, best_distance_squared):
		return distance_squared < best_distance_squared
	return entity_id < best_id


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
