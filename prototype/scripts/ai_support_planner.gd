class_name RoRAiSupportPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const MAX_CANDIDATES := 32
const MAX_SERVICE_DISTANCE_SQUARED := 100.0


static func plan(snapshot: Dictionary, tick: int, team: int) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var own_units: Array = snapshot.get("units", []).filter(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0)
	var workers: Array = own_units.filter(func(unit): return bool(unit.get("components", {}).get("worker", {}).get("enabled", false)) and String(unit.get("task", "idle")) in ["idle", "gather"])
	var healers: Array = own_units.filter(func(unit): return bool(unit.get("components", {}).get("healing", {}).get("enabled", false)) and String(unit.get("task", "idle")) in ["idle", "hold"])
	var repair_targets: Array = snapshot.get("buildings", []).filter(func(entity): return _service_target(entity, allies) and String(entity.get("state", "complete")) == "complete")
	for unit_value in snapshot.get("units", []):
		var unit: Dictionary = unit_value
		if _service_target(unit, allies) and String(unit.get("movement_domain", "land")) == "water":
			repair_targets.append(unit)
	var heal_targets: Array = snapshot.get("units", []).filter(func(entity): return _service_target(entity, allies))
	workers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	healers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	repair_targets.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	heal_targets.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var result: Array = []
	var repair_pair := _nearest_pair(workers.slice(0, MAX_CANDIDATES), repair_targets.slice(0, MAX_CANDIDATES))
	if not repair_pair.is_empty():
		result.append(Commands.RepairCommand.new(tick, [int(repair_pair["actor"].get("id", -1))], int(repair_pair["target"].get("id", -1))))
	var heal_pair := _nearest_pair(healers.slice(0, MAX_CANDIDATES), heal_targets.slice(0, MAX_CANDIDATES), true)
	if not heal_pair.is_empty():
		result.append(Commands.HealCommand.new(tick, [int(heal_pair["actor"].get("id", -1))], int(heal_pair["target"].get("id", -1))))
	return result


static func _service_target(entity: Dictionary, allies: Array) -> bool:
	return int(entity.get("team", 0)) in allies and not bool(entity.get("last_known", false)) and float(entity.get("hp", 0.0)) > 0.0 and float(entity.get("max_hp", 0.0)) > float(entity.get("hp", 0.0)) + 0.0001


static func _nearest_pair(actors: Array, targets: Array, healing: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for actor_value in actors:
		var actor: Dictionary = actor_value
		for target_value in targets:
			var target: Dictionary = target_value
			if healing and int(actor.get("id", -1)) == int(target.get("id", -1)):
				continue
			var distance := Vector2(actor.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(target.get("pos", Vector2.ZERO)))
			if distance > MAX_SERVICE_DISTANCE_SQUARED:
				continue
			if best.is_empty() or distance < best_distance or (is_equal_approx(distance, best_distance) and (int(actor.get("id", -1)) < int(best["actor"].get("id", -1)) or (int(actor.get("id", -1)) == int(best["actor"].get("id", -1)) and int(target.get("id", -1)) < int(best["target"].get("id", -1))))):
				best = {"actor": actor, "target": target}
				best_distance = distance
	return best
