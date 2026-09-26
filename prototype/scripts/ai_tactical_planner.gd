class_name RoRAiTacticalPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")


static func plan(snapshot: Dictionary, tick: int, team: int, goal: Dictionary, formation_name: String = "RECTANGLE", minimum_group_size: int = 1, maximum_group_size: int = 9999, include_workers: bool = true, reserved_unit_ids: Dictionary = {}, refresh_stalled_attack: bool = false) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var candidates: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0 and not reserved_unit_ids.has(int(entity.get("id", -1))) and (include_workers or not bool(entity.get("components", {}).get("worker", {}).get("enabled", false))) and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) and String(entity.get("task", "idle")) in ["idle", "hold"]
	)
	var stranded: Array = candidates.filter(func(entity): return String(entity.get("diagnostic_reason", "")) == "no_path")
	var fighters: Array = candidates.filter(func(entity): return String(entity.get("diagnostic_reason", "")) != "no_path")
	var result := _recovery_commands(snapshot, tick, stranded)
	if refresh_stalled_attack and String(goal.get("type", "")) == "attack":
		result.append_array(_stalled_attack_commands(snapshot, tick, team, goal, include_workers, reserved_unit_ids))
	if fighters.is_empty():
		return result
	var goal_type := String(goal.get("type", "wait"))
	var ongoing_attack_domains: Dictionary = {}
	if goal_type == "attack":
		for entity_value in snapshot.get("units", []):
			var entity: Dictionary = entity_value
			if int(entity.get("team", 0)) != team or float(entity.get("hp", 0.0)) <= 0.0:
				continue
			if String(entity.get("task", "")) != "attack" or int(entity.get("target_id", -1)) != int(goal.get("target_id", -1)):
				continue
			if not include_workers and bool(entity.get("components", {}).get("worker", {}).get("enabled", false)):
				continue
			ongoing_attack_domains[String(entity.get("movement_domain", entity.get("components", {}).get("movement", {}).get("domain", "land")))] = true
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
			if domain in target_domains:
				if group.size() >= maxi(1, minimum_group_size) or ongoing_attack_domains.has(domain):
					var ground_unit_id := _attack_ground_candidate(group, snapshot, team, Vector2(goal.get("position", Vector2.ZERO)))
					if ground_unit_id >= 0:
						ids.erase(ground_unit_id)
						result.append(Commands.AttackGroundCommand.new(tick, [ground_unit_id], Vector2(goal.get("position", Vector2.ZERO))))
					if not ids.is_empty():
						result.append(Commands.AttackCommand.new(tick, ids, int(goal.get("target_id", -1))))
				continue
		if goal_type in ["attack", "explore"]:
			var positions: Dictionary = goal.get("positions_by_domain", {})
			if positions.has(domain):
				var destination := Vector2(positions[domain])
				if ids.size() > 1:
					var forward := (destination - center).normalized()
					result.append(Commands.FormationMoveCommand.new(tick, ids, destination, formation_name, forward))
				else:
					result.append(Commands.AttackMoveCommand.new(tick, ids, destination))
	return result


static func _stalled_attack_commands(snapshot: Dictionary, tick: int, team: int, goal: Dictionary, include_workers: bool, reserved_unit_ids: Dictionary) -> Array:
	var target_id := int(goal.get("target_id", -1))
	var target_visible := false
	for category in ["units", "buildings"]:
		for entity_value in snapshot.get(category, []):
			var entity: Dictionary = entity_value
			if int(entity.get("id", -1)) == target_id and not bool(entity.get("last_known", false)) and float(entity.get("hp", 0.0)) > 0.0:
				target_visible = true
				break
		if target_visible:
			break
	if not target_visible:
		return []
	var stalled_ids: Array[int] = []
	for entity_value in snapshot.get("units", []):
		var entity: Dictionary = entity_value
		var entity_id := int(entity.get("id", -1))
		var reason := String(entity.get("diagnostic_reason", ""))
		if int(entity.get("team", 0)) != team or float(entity.get("hp", 0.0)) <= 0.0 or reserved_unit_ids.has(entity_id):
			continue
		if not include_workers and bool(entity.get("components", {}).get("worker", {}).get("enabled", false)):
			continue
		if not (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])):
			continue
		if String(entity.get("task", "")) not in ["attack", "attack_move"] or not (reason in ["local_obstacle", "no_path"] or reason.begins_with("stuck_")):
			continue
		stalled_ids.append(entity_id)
	stalled_ids.sort()
	if stalled_ids.is_empty():
		return []
	return [Commands.AttackCommand.new(tick, stalled_ids.slice(0, 8), target_id)]


static func _attack_ground_candidate(group: Array, snapshot: Dictionary, team: int, target_position: Vector2) -> int:
	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var relations: Dictionary = snapshot.get("player_state", {}).get("relations", {})
	var examined := 0
	for fighter_value in group:
		var fighter: Dictionary = fighter_value
		var combat: Dictionary = fighter.get("components", {}).get("combat", {})
		if int(combat.get("projectile_id", fighter.get("projectile_id", -1))) < 0:
			continue
		var blast_range := float(combat.get("blast_range", fighter.get("blast_range", 0.0)))
		if blast_range <= 0.0:
			continue
		examined += 1
		if examined > 8:
			break
		var enemy_count := 0
		var unsafe := false
		for category in ["units", "buildings"]:
			for entity_value in snapshot.get(category, []):
				var entity: Dictionary = entity_value
				if bool(entity.get("last_known", false)) or float(entity.get("hp", 0.0)) <= 0.0:
					continue
				if Vector2(entity.get("pos", Vector2.ZERO)).distance_squared_to(target_position) > blast_range * blast_range:
					continue
				var owner := int(entity.get("team", 0))
				if owner in allies:
					unsafe = true
					break
				if owner > 0 and String(relations.get(owner, "enemy")) == "enemy":
					enemy_count += 1
			if unsafe:
				break
		if not unsafe and enemy_count >= 2:
			return int(fighter.get("id", -1))
	return -1


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
