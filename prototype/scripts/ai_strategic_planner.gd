class_name RoRAiStrategicPlanner
extends RefCounted


static func choose_goal(snapshot: Dictionary, team: int, decision_index: int) -> Dictionary:
	if int(snapshot.get("observer_team", -1)) != team:
		return {"type": "wait", "reason": "foreign_snapshot"}
	var player_state: Dictionary = snapshot.get("player_state", {})
	var allies: Array = player_state.get("allies", [team])
	var relations: Dictionary = player_state.get("relations", {})
	var target: Dictionary = {}
	var target_id := 2147483647
	for category in ["units", "buildings"]:
		for entity_value in snapshot.get(category, []):
			var entity: Dictionary = entity_value
			var owner := int(entity.get("team", 0))
			var relation := String(relations.get(owner, "ally" if allies.has(owner) else "enemy"))
			var entity_id := int(entity.get("id", -1))
			if owner > 0 and owner != team and relation == "enemy" and float(entity.get("hp", 0.0)) > 0.0 and not bool(entity.get("last_known", false)) and entity_id < target_id:
				target = entity
				target_id = entity_id
	if not target.is_empty():
		var target_domains: Array = target.get("target_domains", [])
		if target_domains.is_empty():
			var fallback_domain := String(target.get("movement_domain", "land"))
			target_domains = [fallback_domain if fallback_domain in ["land", "water"] else "land"]
		return {
			"type": "attack",
			"target_id": int(target["id"]),
			"position": Vector2(target.get("pos", Vector2.ZERO)),
			"target_domain": String(target_domains[0]),
			"target_domains": target_domains.duplicate(),
			"positions_by_domain": _exploration_positions(snapshot, team, decision_index, target_domains, false),
		}
	var positions_by_domain := _exploration_positions(snapshot, team, decision_index)
	if positions_by_domain.is_empty():
		return {"type": "wait", "reason": "no_reachable_exploration_surface"}
	var primary_position: Vector2 = positions_by_domain.get("land", positions_by_domain.values()[0])
	return {"type": "explore", "position": primary_position, "positions_by_domain": positions_by_domain}


static func _exploration_positions(snapshot: Dictionary, team: int, decision_index: int, excluded_domains: Array = [], allow_land_fallback: bool = true) -> Dictionary:
	if "land" in excluded_domains and "water" in excluded_domains:
		return {}
	var size: Vector2i = snapshot.get("map_size", Vector2i(24, 24))
	var inset := Vector2(2.5, 2.5)
	var points := [
		inset,
		Vector2(size.x - inset.x, inset.y),
		Vector2(size.x - inset.x, size.y - inset.y),
		Vector2(inset.x, size.y - inset.y),
		Vector2(size) * 0.5,
	]
	var positions_by_domain: Dictionary = {}
	var owned_positions: Array[Vector2] = []
	for entity_value in snapshot.get("buildings", []):
		var entity: Dictionary = entity_value
		if int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0:
			owned_positions.append(Vector2(entity.get("pos", Vector2.ZERO)))
	if owned_positions.is_empty():
		for entity_value in snapshot.get("units", []):
			var entity: Dictionary = entity_value
			if int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0:
				owned_positions.append(Vector2(entity.get("pos", Vector2.ZERO)))
	var home_center := Vector2(size) * 0.5
	if not owned_positions.is_empty():
		home_center = Vector2.ZERO
		for position in owned_positions:
			home_center += position
		home_center /= float(owned_positions.size())
	for domain in ["land", "water"]:
		if domain in excluded_domains:
			continue
		var navigation: Dictionary = snapshot.get("navigation", {})
		var has_reachability := navigation.has("reachable")
		var frontier_source: Dictionary = navigation.get("reachable_frontier", {}) if has_reachability else navigation.get("frontier", {})
		var frontier: Array = frontier_source.get(domain, []).duplicate()
		if not frontier.is_empty():
			positions_by_domain[domain] = exploration_target(frontier, home_center, decision_index)
			continue
		var known_source: Dictionary = navigation.get("reachable", {}) if has_reachability else navigation
		var known: Array = known_source.get(domain, [])
		if not known.is_empty():
			positions_by_domain[domain] = known[posmod(decision_index + team, known.size())]
	if allow_land_fallback and "land" not in excluded_domains and not positions_by_domain.has("land"):
		if not snapshot.get("navigation", {}).has("reachable"):
			positions_by_domain["land"] = points[posmod(decision_index + team, points.size())]
	return positions_by_domain


static func exploration_target(points: Array, origin: Vector2, decision_index: int) -> Vector2:
	# Retain only the four ordered extrema used by the exploration policy.
	var best: Array = []
	for point_value in points:
		var point := Vector2(point_value)
		var slot := 0
		while slot < best.size():
			var current: Vector2 = best[slot]
			var distance := point.distance_squared_to(origin)
			var current_distance := current.distance_squared_to(origin)
			if distance > current_distance and not is_equal_approx(distance, current_distance): break
			if is_equal_approx(distance, current_distance) and (point.y < current.y or (is_equal_approx(point.y, current.y) and point.x < current.x)): break
			slot += 1
		if slot < 4:
			best.insert(slot, point)
			if best.size() > 4: best.pop_back()
	return best[posmod(decision_index, best.size())] if not best.is_empty() else origin
