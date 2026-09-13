class_name RoRScenarioDefinition
extends RefCounted


static func normalize(source: Dictionary, known_teams: Dictionary, map_size: Vector2i) -> Dictionary:
	if source.is_empty():
		return {"value": {}, "errors": []}
	var result := source.duplicate(true)
	var errors: Array[String] = []
	if int(result.get("schema_version", 0)) != 1:
		errors.append("scenario_schema_version_unsupported")
	var seen_ids: Dictionary = {}
	var participants: Array = result.get("participants", [])
	for participant_value in participants:
		if not participant_value is Dictionary:
			errors.append("scenario_participant_invalid")
			continue
		var participant: Dictionary = participant_value
		var team := int(participant.get("team", 0))
		if not known_teams.has(team):
			errors.append("scenario_participant_team_unknown:%d" % team)
		var completion_mode := String(participant.get("completion_mode", "any"))
		if completion_mode not in ["all", "any"]:
			errors.append("scenario_participant_mode_invalid:%d" % team)
		participant["completion_mode"] = completion_mode
		var groups: Array = participant.get("groups", [])
		if groups.is_empty():
			errors.append("scenario_participant_groups_required:%d" % team)
		for group_value in groups:
			if not group_value is Dictionary:
				errors.append("scenario_group_invalid:%d" % team)
				continue
			var group: Dictionary = group_value
			var group_id := String(group.get("id", ""))
			_register_id(group_id, "scenario_group_id", seen_ids, errors)
			var group_mode := String(group.get("mode", "all"))
			if group_mode not in ["all", "any"]:
				errors.append("scenario_group_mode_invalid:%s" % group_id)
			group["mode"] = group_mode
			var conditions: Array = group.get("conditions", [])
			if conditions.is_empty():
				errors.append("scenario_group_conditions_required:%s" % group_id)
			for condition_value in conditions:
				if not condition_value is Dictionary:
					errors.append("scenario_condition_invalid:%s" % group_id)
					continue
				_normalize_condition(condition_value, known_teams, map_size, seen_ids, errors)
	result["participants"] = participants
	return {"value": result, "errors": errors}


static func _normalize_condition(condition: Dictionary, known_teams: Dictionary, map_size: Vector2i, seen_ids: Dictionary, errors: Array[String]) -> void:
	var condition_id := String(condition.get("id", ""))
	_register_id(condition_id, "scenario_condition_id", seen_ids, errors)
	match String(condition.get("type", "")):
		"create_in_area":
			var team := int(condition.get("team", 0))
			if not known_teams.has(team):
				errors.append("scenario_condition_team_unknown:%s" % condition_id)
			if int(condition.get("source_unit_id", -1)) < 0 or String(condition.get("kind", "")).is_empty():
				errors.append("scenario_condition_object_unknown:%s" % condition_id)
			if int(condition.get("required_count", 0)) <= 0:
				errors.append("scenario_condition_count_invalid:%s" % condition_id)
			var area_values: Array = condition.get("area", [])
			if area_values.size() != 4:
				errors.append("scenario_condition_area_required:%s" % condition_id)
				return
			var area := [
				float(area_values[0]),
				float(area_values[1]),
				float(area_values[2]),
				float(area_values[3]),
			]
			if area[0] > area[2] or area[1] > area[3]:
				errors.append("scenario_condition_area_inverted:%s" % condition_id)
			if area[0] < 0.0 or area[1] < 0.0 or area[2] > map_size.x or area[3] > map_size.y:
				errors.append("scenario_condition_area_out_of_bounds:%s" % condition_id)
			condition["area"] = area
		"destroy_player":
			var target_team := int(condition.get("target_team", 0))
			if not known_teams.has(target_team):
				errors.append("scenario_condition_target_unknown:%s" % condition_id)
		"destroy_object":
			if int(condition.get("target_scenario_object_id", -1)) < 0:
				errors.append("scenario_condition_target_object_invalid:%s" % condition_id)
			var target_team := int(condition.get("target_team", 0))
			if target_team > 0 and not known_teams.has(target_team):
				errors.append("scenario_condition_target_unknown:%s" % condition_id)
		_:
			errors.append("scenario_condition_type_unsupported:%s" % condition_id)


static func _register_id(value: String, label: String, seen_ids: Dictionary, errors: Array[String]) -> void:
	if value.is_empty():
		errors.append("%s_required" % label)
	elif seen_ids.has(value):
		errors.append("%s_duplicate:%s" % [label, value])
	else:
		seen_ids[value] = true
