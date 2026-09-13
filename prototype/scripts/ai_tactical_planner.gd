class_name RoRAiTacticalPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")


static func plan(snapshot: Dictionary, tick: int, team: int, goal: Dictionary, formation_name: String = "RECTANGLE") -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var fighters: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0 and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) and String(entity.get("task", "idle")) in ["idle", "hold"]
	)
	if fighters.is_empty():
		return []
	var goal_type := String(goal.get("type", "wait"))
	var groups: Dictionary = {}
	for fighter in fighters:
		var domain := String(fighter.get("movement_domain", fighter.get("components", {}).get("movement", {}).get("domain", "land")))
		if not groups.has(domain):
			groups[domain] = []
		groups[domain].append(fighter)
	var result: Array = []
	var domains: Array = groups.keys()
	domains.sort()
	for domain_value in domains:
		var domain := String(domain_value)
		var group: Array = groups[domain]
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
				result.append(Commands.AttackMoveCommand.new(tick, ids, Vector2(positions[domain])))
	return result
