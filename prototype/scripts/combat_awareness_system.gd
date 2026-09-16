class_name RoRCombatAwarenessSystem
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const PerceptionService := preload("res://scripts/perception_service.gd")

var perception := PerceptionService.new()
var last_world_signature: Array = []


func reset() -> void:
	last_world_signature.clear()


func collect_commands(world, tick: int) -> Array:
	if world == null:
		return []
	var world_signature := _world_signature(world)
	if world_signature == last_world_signature:
		return []
	last_world_signature = world_signature
	var units: Array = world.get_combat_attackers()
	units.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var assigned := _assigned_attacker_counts(units)
	var commands: Array = []

	for unit_value in units:
		var unit: Dictionary = unit_value
		if not _eligible_for_awareness(world, unit):
			continue
		var stance := String(unit.get("stance", "passive"))
		if stance == "passive":
			continue
		var current_target = world.find_combat_target(int(unit.get("target_id", -1)))
		if String(unit.get("task", "idle")) == "attack" and _target_remains_valid(world, unit, current_target):
			continue

		var query_range := _query_range(unit, stance)
		var options := {
			"range": query_range,
			"assigned_attackers": assigned,
			"visibility": func(team: int, entity: Dictionary): return world.is_entity_visible_to(team, entity),
			"alliance": func(first_team: int, second_team: int): return world.are_teams_allied(first_team, second_team),
			"hostility": func(observer: Dictionary, entity: Dictionary): return world.can_autonomously_target(observer, entity),
			"reachability": func(observer: Dictionary, entity: Dictionary): return world.can_unit_reach_entity(observer, entity),
		}
		if bool(unit.get("attack_autonomous", false)):
			var active_leash_origin := Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO)))
			var active_chase_range := float(unit.get("chase_range", 0.0))
			options["target_filter"] = func(_observer: Dictionary, entity: Dictionary): return active_leash_origin.distance_to(Vector2(entity.get("pos", Vector2.ZERO))) <= active_chase_range + 0.0001
		if stance == "defensive":
			var retaliation_target_id := int(unit.get("retaliation_target_id", -1))
			if retaliation_target_id < 0:
				retaliation_target_id = _assistance_target_id(world, unit, units)
			if retaliation_target_id < 0:
				continue
			options["allowed_ids"] = {retaliation_target_id: true}
		elif stance == "stand_ground":
			options["target_filter"] = func(observer: Dictionary, entity: Dictionary): return world.is_unit_in_attack_range(observer, entity)
		elif String(unit.get("task", "idle")) not in ["idle", "move", "attack_move", "attack"]:
			continue

		var nearby_targets: Array = world.query_combat_entities_near(Vector2(unit.get("pos", Vector2.ZERO)), query_range + float(unit.get("footprint_radius", 0.0)))
		var target = perception.best_target(unit, nearby_targets, options)
		if target == null:
			continue
		var target_id := int(target["id"])
		var policy := {
			"autonomous": true,
			"trigger": "retaliation" if stance == "defensive" else "stance",
			"leash_origin": Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO))) if bool(unit.get("attack_autonomous", false)) else Vector2(unit.get("pos", Vector2.ZERO)),
			"chase_range": float(unit.get("chase_range", _query_range(unit, stance))),
		}
		commands.append(Commands.AttackCommand.new(tick, [int(unit["id"])], target_id, policy))
		assigned[target_id] = int(assigned.get(target_id, 0)) + 1
	return commands


func _world_signature(world) -> Array:
	var result: Array = [bool(world.battle_over)]
	for entity_value in world.get_units() + world.get_buildings():
		var entity: Dictionary = entity_value
		result.append([
			int(entity.get("id", -1)),
			int(entity.get("team", 0)),
			Vector2(entity.get("pos", Vector2.ZERO)),
			float(entity.get("hp", 0.0)),
			String(entity.get("task", "idle")),
			int(entity.get("target_id", -1)),
			String(entity.get("stance", "passive")),
			int(entity.get("retaliation_target_id", -1)),
			bool(entity.get("attack_autonomous", false)),
			bool(entity.get("combat_enabled", false)),
			float(entity.get("acquisition_range", 0.0)),
			float(entity.get("chase_range", 0.0)),
			float(entity.get("attack_range", 0.0)),
			String(entity.get("state", "")),
		])
	return result


func _eligible_for_awareness(world, unit: Dictionary) -> bool:
	if float(unit.get("hp", 0.0)) <= 0.0 or not bool(unit.get("combat_enabled", false)):
		return false
	if world.entity_is_static(unit) and String(unit.get("state", "complete")) != "complete":
		return false
	var team := int(unit.get("team", 0))
	return team > 0 and not world.battle_over


func _target_remains_valid(world, unit: Dictionary, target: Variant) -> bool:
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return false
	if world.are_teams_allied(int(unit.get("team", 0)), int(target.get("team", 0))):
		return false
	if bool(unit.get("attack_autonomous", false)) and not world.can_autonomously_target(unit, target):
		return false
	if not world.is_entity_visible_to(int(unit.get("team", 0)), target):
		return false
	if String(unit.get("stance", "passive")) == "stand_ground" and not world.is_unit_in_attack_range(unit, target):
		return false
	if bool(unit.get("attack_autonomous", false)):
		var origin := Vector2(unit.get("combat_leash_origin", unit.get("pos", Vector2.ZERO)))
		if origin.distance_to(Vector2(target.get("pos", Vector2.ZERO))) > float(unit.get("chase_range", 0.0)) + 0.0001:
			return false
	return true


func _assistance_target_id(world, unit: Dictionary, units: Array) -> int:
	var allies: Array = []
	var unit_team := int(unit.get("team", 0))
	var unit_position := Vector2(unit.get("pos", Vector2.ZERO))
	var assist_range := float(unit.get("acquisition_range", 0.0))
	for ally_value in units:
		var ally: Dictionary = ally_value
		if int(ally.get("id", -1)) == int(unit.get("id", -1)) or float(ally.get("hp", 0.0)) <= 0.0:
			continue
		if not world.are_teams_allied(unit_team, int(ally.get("team", 0))):
			continue
		var retaliation_target_id := int(ally.get("retaliation_target_id", -1))
		if retaliation_target_id < 0 or unit_position.distance_to(Vector2(ally.get("pos", Vector2.ZERO))) > assist_range:
			continue
		if world.find_combat_target(retaliation_target_id) == null:
			continue
		allies.append({"ally_id": int(ally.get("id", -1)), "target_id": retaliation_target_id, "distance_squared": unit_position.distance_squared_to(Vector2(ally.get("pos", Vector2.ZERO)))})
	allies.sort_custom(func(left, right):
		if not is_equal_approx(float(left["distance_squared"]), float(right["distance_squared"])):
			return float(left["distance_squared"]) < float(right["distance_squared"])
		return int(left["ally_id"]) < int(right["ally_id"])
	)
	return -1 if allies.is_empty() else int(allies[0]["target_id"])


func _query_range(unit: Dictionary, stance: String) -> float:
	if stance == "stand_ground":
		return maxf(0.85, float(unit.get("attack_range", 0.0)))
	return maxf(0.0, float(unit.get("acquisition_range", 0.0)))


func _assigned_attacker_counts(units: Array) -> Dictionary:
	var counts: Dictionary = {}
	for unit_value in units:
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0 or String(unit.get("task", "")) != "attack":
			continue
		var target_id := int(unit.get("target_id", -1))
		if target_id >= 0:
			counts[target_id] = int(counts.get(target_id, 0)) + 1
	return counts
