class_name RoRAiTacticalPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")


static func plan(snapshot: Dictionary, tick: int, team: int, goal: Dictionary, formation_name: String = "RECTANGLE", minimum_group_size: int = 1, maximum_group_size: int = 9999, include_workers: bool = true) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var candidates: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0 and (include_workers or not bool(entity.get("components", {}).get("worker", {}).get("enabled", false))) and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) and String(entity.get("task", "idle")) in ["idle", "hold"]
	)
	var stranded: Array = candidates.filter(func(entity): return String(entity.get("diagnostic_reason", "")) == "no_path")
	var fighters: Array = candidates.filter(func(entity): return String(entity.get("diagnostic_reason", "")) != "no_path")
	var result := _recovery_commands(snapshot, tick, stranded)
	if fighters.is_empty():
		return result
	var goal_type := String(goal.get("type", "wait"))
	var groups: Dictionary = {}
	for fighter in fighters:
		var domain := String(fighter.get("movement_domain", fighter.get("components", {}).get("movement", {}).get("domain", "land")))
		if not groups.has(domain):
			groups[domain] = []
		groups[domain].append(fighter)
	var domains: Array = groups.keys()
	domains.sort()
	for domain_value in domains:
		var domain := String(domain_value)
		var group: Array = groups[domain]
		group.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
		if String(goal.get("type", "wait")) == "attack" and group.size() < maxi(1, minimum_group_size):
			continue
		if group.size() > maxi(1, maximum_group_size):
			group = group.slice(0, maxi(1, maximum_group_size))
		var ids: Array[int] = []
		var center := Vector2.ZERO
		for fighter in group:
			ids.append(int(fighter.get("id", -1)))
			center += Vector2(fighter.get("pos", Vector2.ZERO))
		center /= float(group.size())
		if goal_type == "attack":
			var target_domains: Array = goal.get("target_domains", [String(goal.get("target_domain", "land"))])
			if domain not in target_domains:
				continue
			result.append(Commands.AttackCommand.new(tick, ids, int(goal.get("target_id", -1))))
		elif goal_type == "explore":
			var positions: Dictionary = goal.get("positions_by_domain", {})
			if positions.has(domain):
				var destination := Vector2(positions[domain])
				if ids.size() > 1:
					var forward := (destination - center).normalized()
					result.append(Commands.FormationMoveCommand.new(tick, ids, destination, formation_name, forward))
				else:
					result.append(Commands.AttackMoveCommand.new(tick, ids, destination))
	return result


static func _recovery_commands(snapshot: Dictionary, tick: int, stranded: Array) -> Array:
	var result: Array = []
	stranded.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	for fighter_value in stranded:
		var fighter: Dictionary = fighter_value
		var domain := String(fighter.get("movement_domain", "land"))
		var origin := Vector2(fighter.get("pos", Vector2.ZERO))
		var best: Variant = null
		var best_distance := INF
		var navigation: Dictionary = snapshot.get("navigation", {})
		var known: Array = navigation.get("reachable", {}).get(domain, []) if navigation.has("reachable") else navigation.get(domain, [])
		for position_value in known:
			var position := Vector2(position_value)
			var distance := origin.distance_squared_to(position)
			if distance <= 0.01:
				continue
			if distance < best_distance - 0.000001 or (is_equal_approx(distance, best_distance) and (best == null or position.y < Vector2(best).y or (is_equal_approx(position.y, Vector2(best).y) and position.x < Vector2(best).x))):
				best = position
				best_distance = distance
		if best is Vector2:
			result.append(Commands.AttackMoveCommand.new(tick, [int(fighter.get("id", -1))], best))
	return result
