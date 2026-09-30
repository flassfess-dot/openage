class_name RoRAiSupportPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const MAX_CANDIDATES := 32
const MAX_SERVICE_DISTANCE_SQUARED := 100.0


static func plan(snapshot: Dictionary, tick: int, team: int) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var workers: Array = []
	var healers: Array = []
	var repair_targets: Array = []
	var heal_targets: Array = []
	for unit_value in snapshot.get("units", []):
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0:
			var task := String(unit.get("task", "idle"))
			if bool(unit.get("components", {}).get("worker", {}).get("enabled", false)) and task in ["idle", "gather"]:
				workers.append(unit)
			if bool(unit.get("components", {}).get("healing", {}).get("enabled", false)) and task in ["idle", "hold"]:
				healers.append(unit)
		var service_target := _service_target(unit, allies)
		if service_target and String(unit.get("movement_domain", "land")) == "water":
			repair_targets.append(unit)
		if service_target:
			heal_targets.append(unit)
	for building_value in snapshot.get("buildings", []):
		var building: Dictionary = building_value
		if _service_target(building, allies) and String(building.get("state", "complete")) == "complete":
			repair_targets.append(building)
	_sort_by_id_if_needed(workers)
	_sort_by_id_if_needed(healers)
	_sort_by_id_if_needed(repair_targets)
	_sort_by_id_if_needed(heal_targets)
	var result: Array = []
	var repair_pair := _nearest_pair(workers, repair_targets)
	if not repair_pair.is_empty():
		result.append(Commands.RepairCommand.new(tick, [int(repair_pair["actor"].get("id", -1))], int(repair_pair["target"].get("id", -1))))
	var heal_pair := _nearest_pair(healers, heal_targets, true)
	if not heal_pair.is_empty():
		result.append(Commands.HealCommand.new(tick, [int(heal_pair["actor"].get("id", -1))], int(heal_pair["target"].get("id", -1))))
	return result


static func _service_target(entity: Dictionary, allies: Array) -> bool:
	return int(entity.get("team", 0)) in allies and not bool(entity.get("last_known", false)) and float(entity.get("hp", 0.0)) > 0.0 and float(entity.get("max_hp", 0.0)) > float(entity.get("hp", 0.0)) + 0.0001


static func _nearest_pair(actors: Array, targets: Array, healing: bool = false) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for actor_index in range(mini(actors.size(), MAX_CANDIDATES)):
		var actor: Dictionary = actors[actor_index]
		for target_index in range(mini(targets.size(), MAX_CANDIDATES)):
			var target: Dictionary = targets[target_index]
			if healing and int(actor.get("id", -1)) == int(target.get("id", -1)):
				continue
			var distance := Vector2(actor.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(target.get("pos", Vector2.ZERO)))
			if distance > MAX_SERVICE_DISTANCE_SQUARED:
				continue
			if best.is_empty() or distance < best_distance or (is_equal_approx(distance, best_distance) and (int(actor.get("id", -1)) < int(best["actor"].get("id", -1)) or (int(actor.get("id", -1)) == int(best["actor"].get("id", -1)) and int(target.get("id", -1)) < int(best["target"].get("id", -1))))):
				best = {"actor": actor, "target": target}
				best_distance = distance
	return best


static func _sort_by_id_if_needed(entities: Array) -> void:
	var previous_id := -9223372036854775807
	for entity_value in entities:
		var entity_id := int(entity_value.get("id", -1))
		if entity_id < previous_id:
			entities.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
			return
		previous_id = entity_id
