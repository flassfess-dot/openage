class_name RoRScenarioSystem
extends RefCounted

var definition: Dictionary = {}
var condition_states: Dictionary = {}
var group_states: Dictionary = {}
var result: Dictionary = {"over": false, "winner_team": -1, "reason": ""}


func configure(new_definition: Dictionary) -> void:
	definition = new_definition.duplicate(true)
	reset()


func reset() -> void:
	condition_states.clear()
	group_states.clear()
	result = {"over": false, "winner_team": -1, "reason": ""}


func update(context: Dictionary) -> Dictionary:
	var events: Array[Dictionary] = []
	if definition.is_empty() or bool(result.get("over", false)):
		return {"events": events, "result": result.duplicate(true)}
	var participants: Array = definition.get("participants", []).duplicate()
	participants.sort_custom(func(left, right): return int(left.get("team", 0)) < int(right.get("team", 0)))
	for participant_value in participants:
		var participant: Dictionary = participant_value
		var team := int(participant.get("team", 0))
		var participant_status := String(context.get("player_states", {}).get(team, {}).get("status", "active"))
		if participant_status != "active":
			continue
		var group_results: Array[bool] = []
		for group_value in participant.get("groups", []):
			var group: Dictionary = group_value
			var condition_results: Array[bool] = []
			for condition_value in group.get("conditions", []):
				var condition: Dictionary = condition_value
				var state := _evaluate_condition(condition, context)
				var condition_id := String(condition.get("id", ""))
				var was_achieved := bool(condition_states.get(condition_id, {}).get("achieved", false))
				condition_states[condition_id] = state
				if bool(state["achieved"]) != was_achieved:
					events.append({
						"type": "scenario_condition_changed",
						"payload": {
							"condition_id": condition_id,
							"team": team,
							"achieved": bool(state["achieved"]),
							"current": int(state.get("current", 0)),
							"required": int(state.get("required", 0)),
						},
					})
				condition_results.append(bool(state["achieved"]))
			var achieved := _combine(condition_results, String(group.get("mode", "all")))
			var group_id := String(group.get("id", ""))
			var was_group_achieved := bool(group_states.get(group_id, false))
			group_states[group_id] = achieved
			if achieved != was_group_achieved:
				events.append({
					"type": "scenario_group_changed",
					"payload": {"group_id": group_id, "team": team, "achieved": achieved},
				})
			group_results.append(achieved)
		if _combine(group_results, String(participant.get("completion_mode", "any"))):
			result = {"over": true, "winner_team": team, "reason": "scenario"}
			events.append({
				"type": "scenario_completed",
				"payload": {"winner_team": team, "reason": "scenario"},
			})
			break
	return {"events": events, "result": result.duplicate(true)}


func canonical_state() -> Dictionary:
	return {
		"definition": definition.duplicate(true),
		"condition_states": condition_states.duplicate(true),
		"group_states": group_states.duplicate(true),
		"result": result.duplicate(true),
	}


func presentation_state(observer_team: int) -> Dictionary:
	var participant: Dictionary = {}
	for value in definition.get("participants", []):
		if int(value.get("team", 0)) == observer_team:
			participant = value
			break
	return {
		"active": not participant.is_empty() and not bool(result.get("over", false)),
		"participant": participant.duplicate(true),
		"condition_states": condition_states.duplicate(true),
		"group_states": group_states.duplicate(true),
		"result": result.duplicate(true),
	}


func _evaluate_condition(condition: Dictionary, context: Dictionary) -> Dictionary:
	match String(condition.get("type", "")):
		"create_in_area":
			var count := _count_entities_in_area(condition, context.get("units", []), context.get("buildings", []))
			var required := int(condition.get("required_count", 1))
			return {"achieved": count >= required, "current": count, "required": required}
		"destroy_player":
			var target_team := int(condition.get("target_team", -1))
			var target_status := String(context.get("player_states", {}).get(target_team, {}).get("status", "active"))
			if target_status != "active":
				return {"achieved": true, "current": 0, "required": 0}
			var remaining := 0
			for unit in context.get("units", []):
				if int(unit.get("team", 0)) == target_team and float(unit.get("hp", 0.0)) > 0.0:
					remaining += 1
			for building in context.get("buildings", []):
				if int(building.get("team", 0)) == target_team and float(building.get("hp", 0.0)) > 0.0:
					remaining += 1
			return {"achieved": remaining == 0, "current": 0 if remaining == 0 else 1, "required": 0}
		"destroy_object":
			var target_id := int(condition.get("target_scenario_object_id", -1))
			for collection_name in ["units", "buildings", "resource_nodes", "objectives"]:
				for entity in context.get(collection_name, []):
					if int(entity.get("scenario_object_id", -1)) != target_id:
						continue
					var alive := bool(entity.get("active", true))
					if entity.has("hp"):
						alive = alive and float(entity.get("hp", 0.0)) > 0.0
					elif entity.has("amount"):
						alive = alive and int(entity.get("amount", 0)) > 0
					return {"achieved": not alive, "current": 1 if alive else 0, "required": 0}
			return {"achieved": true, "current": 0, "required": 0}
		"destroy_count":
			var target_ids: Array = condition.get("target_scenario_object_ids", [])
			var alive_ids: Dictionary = {}
			for collection_name in ["units", "buildings", "resource_nodes", "objectives"]:
				for entity in context.get(collection_name, []):
					var scenario_id := int(entity.get("scenario_object_id", -1))
					if not target_ids.has(scenario_id):
						continue
					var alive := bool(entity.get("active", true))
					if entity.has("hp"):
						alive = alive and float(entity.get("hp", 0.0)) > 0.0
					elif entity.has("amount"):
						alive = alive and int(entity.get("amount", 0)) > 0
					if alive:
						alive_ids[scenario_id] = true
			var destroyed := target_ids.size() - alive_ids.size()
			var required := int(condition.get("required_count", 1))
			return {"achieved": destroyed >= required, "current": destroyed, "required": required}
		"bring_object_to_area":
			var target_id := int(condition.get("target_scenario_object_id", -1))
			var area: Array = condition.get("area", [])
			for collection_name in ["units", "buildings", "resource_nodes", "objectives"]:
				for entity in context.get(collection_name, []):
					if int(entity.get("scenario_object_id", -1)) != target_id:
						continue
					var alive := bool(entity.get("active", true))
					if entity.has("hp"):
						alive = alive and float(entity.get("hp", 0.0)) > 0.0
					var position: Vector2 = entity.get("pos", Vector2.ZERO)
					var inside := alive and _position_in_area(position, area)
					return {"achieved": inside, "current": 1 if inside else 0, "required": 1}
			return {"achieved": false, "current": 0, "required": 1}
	return {"achieved": false, "current": 0, "required": 1}


func _count_entities_in_area(condition: Dictionary, units: Array, buildings: Array) -> int:
	return _count_collection_in_area(condition, units, false) + _count_collection_in_area(condition, buildings, true)


func _count_collection_in_area(condition: Dictionary, entities: Array, require_complete: bool) -> int:
	var count := 0
	var team := int(condition.get("team", 0))
	var source_unit_id := int(condition.get("source_unit_id", -1))
	var kind := String(condition.get("kind", ""))
	var area: Array = condition.get("area", [])
	if area.size() != 4:
		return 0
	for entity in entities:
		if int(entity.get("team", 0)) != team or float(entity.get("hp", 0.0)) <= 0.0:
			continue
		if require_complete and String(entity.get("state", "complete")) != "complete":
			continue
		if source_unit_id >= 0:
			if int(entity.get("source_unit_id", -1)) != source_unit_id:
				continue
		elif String(entity.get("kind", "")) != kind:
			continue
		var position: Vector2 = entity.get("pos", Vector2.ZERO)
		if _position_in_area(position, area):
			count += 1
	return count


func _position_in_area(position: Vector2, area: Array) -> bool:
	return area.size() == 4 and position.x >= float(area[0]) and position.y >= float(area[1]) and position.x <= float(area[2]) and position.y <= float(area[3])


func _combine(values: Array[bool], mode: String) -> bool:
	if values.is_empty():
		return false
	if mode == "any":
		return values.any(func(value): return value)
	return values.all(func(value): return value)
