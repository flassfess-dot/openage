class_name RoRAiStrategicPlanner
extends RefCounted


static func choose_goal(snapshot: Dictionary, team: int, decision_index: int) -> Dictionary:
	if int(snapshot.get("observer_team", -1)) != team:
		return {"type": "wait", "reason": "foreign_snapshot"}
	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var targets: Array = []
	for category in ["units", "buildings"]:
		for entity_value in snapshot.get(category, []):
			var entity: Dictionary = entity_value
			var owner := int(entity.get("team", 0))
			if owner > 0 and owner != team and not allies.has(owner) and float(entity.get("hp", 0.0)) > 0.0:
				targets.append(entity)
	if not targets.is_empty():
		targets.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
		var target: Dictionary = targets[0]
		var target_domains: Array = target.get("target_domains", [])
		if target_domains.is_empty():
			var fallback_domain := String(target.get("movement_domain", "land"))
			target_domains = [fallback_domain if fallback_domain in ["land", "water"] else "land"]
		return {"type": "attack", "target_id": int(target["id"]), "position": Vector2(target.get("pos", Vector2.ZERO)), "target_domain": String(target_domains[0]), "target_domains": target_domains.duplicate()}
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
	for domain in ["land", "water"]:
		var known: Array = snapshot.get("navigation", {}).get(domain, [])
		if not known.is_empty():
			positions_by_domain[domain] = known[posmod(decision_index + team, known.size())]
	if not positions_by_domain.has("land"):
		positions_by_domain["land"] = points[posmod(decision_index + team, points.size())]
	return {"type": "explore", "position": positions_by_domain["land"], "positions_by_domain": positions_by_domain}
