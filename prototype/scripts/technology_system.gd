class_name RoRTechnologySystem
extends RefCounted

const AGE_TECHNOLOGY_IDS: Array[int] = [100, 101, 102, 103]

var catalog: Dictionary = {}
var team_states: Dictionary = {}


func configure(object_catalog: Dictionary) -> void:
	catalog = object_catalog
	team_states.clear()


func reset() -> void:
	team_states.clear()


func reset_team(team: int) -> void:
	team_states.erase(team)


func initialize_team(team: int) -> Array:
	var state := _state(team)
	if state["researched"].has(100):
		return []
	return complete_research(team, 100)


func technology(technology_id: int) -> Dictionary:
	return catalog.get("technologies", {}).get(String.num_int64(technology_id), {})


func effect_commands(technology_id: int) -> Array:
	var record := technology(technology_id)
	var bundle_id := int(record.get("effect_bundle_id", -1))
	if bundle_id < 0:
		return []
	return catalog.get("effect_bundles", {}).get(String.num_int64(bundle_id), {}).get("commands", []).duplicate(true)


func apply_effect_bundle(team: int, effect_bundle_id: int) -> Array:
	if effect_bundle_id < 0:
		return []
	var commands: Array = catalog.get("effect_bundles", {}).get(String.num_int64(effect_bundle_id), {}).get("commands", []).duplicate(true)
	for command_value in commands:
		_register_persistent_effect(team, command_value)
	return commands


func is_researched(team: int, technology_id: int) -> bool:
	return _state(team)["researched"].has(technology_id)


func is_researching(team: int, technology_id: int) -> bool:
	return _state(team)["researching"].has(technology_id)


func prerequisites_met(team: int, technology_id: int) -> bool:
	return _requirement_satisfied(team, technology_id, {})


func direct_prerequisites_met(team: int, technology_id: int) -> bool:
	var record := technology(technology_id)
	if record.is_empty():
		return false
	var required_count := maxi(0, int(record.get("required_technology_count", 0)))
	if required_count == 0:
		return true
	var satisfied := 0
	var valid := 0
	for value in record.get("required_technology_ids", []):
		var requirement_id := int(value)
		if requirement_id < 0:
			continue
		valid += 1
		if _requirement_satisfied(team, requirement_id, {}):
			satisfied += 1
	return satisfied >= mini(required_count, valid)


func can_research(team: int, technology_id: int, research_location_id: int = -1) -> String:
	var record := technology(technology_id)
	if record.is_empty():
		return "unknown_technology"
	if is_researched(team, technology_id):
		return "already_researched"
	if is_researching(team, technology_id):
		return "already_researching"
	if bool(_state(team)["disabled_technologies"].get(technology_id, false)):
		return "technology_disabled"
	var expected_location := int(record.get("research_location_id", -1))
	if research_location_id >= 0 and expected_location >= 0 and research_location_id != expected_location:
		return "wrong_research_location"
	if not direct_prerequisites_met(team, technology_id):
		return "missing_prerequisites"
	return ""


func is_technology_disabled(team: int, technology_id: int) -> bool:
	return bool(_state(team)["disabled_technologies"].get(technology_id, false))


func disable_technology(team: int, technology_id: int) -> void:
	if technology_id >= 0:
		_state(team)["disabled_technologies"][technology_id] = true


func mark_researching(team: int, technology_id: int) -> void:
	_state(team)["researching"][technology_id] = true


func cancel_research(team: int, technology_id: int) -> void:
	_state(team)["researching"].erase(technology_id)


func complete_research(team: int, technology_id: int) -> Array:
	var state := _state(team)
	state["researching"].erase(technology_id)
	if state["researched"].has(technology_id):
		return []
	state["researched"][technology_id] = true
	if technology_id in AGE_TECHNOLOGY_IDS:
		state["current_age"] = technology_id
	var commands := effect_commands(technology_id)
	for command_value in commands:
		_register_persistent_effect(team, command_value)
	return commands


func research_cost(team: int, technology_id: int) -> Dictionary:
	var result: Dictionary = {}
	for cost_value in technology(technology_id).get("resource_costs", []):
		var cost: Dictionary = cost_value
		if bool(cost.get("enabled", false)) and int(cost.get("type_id", -1)) >= 0:
			result[int(cost["type_id"])] = int(cost.get("amount", 0))
	for resource_id in _state(team)["technology_cost_modifiers"].get(technology_id, {}):
		var operations: Array = _state(team)["technology_cost_modifiers"][technology_id][resource_id]
		var value := float(result.get(resource_id, 0))
		for operation in operations:
			value = _apply_operator(value, int(operation["operator"]), float(operation["value"]))
		result[resource_id] = maxi(0, roundi(value))
	return result


func research_time(team: int, technology_id: int) -> float:
	var value := float(technology(technology_id).get("research_time", 0.0))
	for operation in _state(team)["technology_time_modifiers"].get(technology_id, []):
		value = _apply_operator(value, int(operation["operator"]), float(operation["value"]))
	return maxf(0.05, value)


func available_technology_ids(team: int, research_location_id: int = -1) -> Array[int]:
	var result: Array[int] = []
	for key in catalog.get("technologies", {}):
		var technology_id := int(key)
		var record: Dictionary = catalog["technologies"][key]
		if int(record.get("research_location_id", -1)) < 0:
			continue
		if research_location_id >= 0 and int(record.get("research_location_id", -1)) != research_location_id:
			continue
		if can_research(team, technology_id, research_location_id) == "":
			result.append(technology_id)
	result.sort()
	return result


func available_automatic_technology_ids(team: int) -> Array[int]:
	var result: Array[int] = []
	for key in catalog.get("technologies", {}):
		var technology_id := int(key)
		var record: Dictionary = catalog["technologies"][key]
		if not _is_automatic_connector(record, technology_id):
			continue
		if can_research(team, technology_id) == "":
			result.append(technology_id)
	result.sort()
	return result


func _is_automatic_connector(record: Dictionary, technology_id: int) -> bool:
	# RoR expresses both invisible building connectors and named zero-time unit
	# availability entries as technologies. Neither is a player research action:
	# the entire effect bundle only enables objects once its prerequisites exist.
	# Classifying the source semantics keeps this independent of internal type IDs.
	if float(record.get("research_time", 0.0)) > 0.0:
		return false
	if int(record.get("required_technology_count", 0)) <= 0:
		return false
	var commands := effect_commands(technology_id)
	if commands.is_empty():
		return false
	for command_value in commands:
		var command: Dictionary = command_value
		if int(command.get("type_id", -1)) != 2 or int(command.get("attr_a", -1)) < 0:
			return false
	return true


func set_object_enabled(team: int, object_id: int, enabled: bool) -> void:
	_state(team)["object_availability"][object_id] = enabled


func disable_scenario_object(team: int, object_id: int) -> void:
	if object_id >= 0:
		_state(team)["scenario_disabled_objects"][object_id] = true


func is_object_enabled(team: int, object_id: int, catalog_default: bool = true) -> bool:
	if bool(_state(team)["scenario_disabled_objects"].get(object_id, false)):
		return false
	return bool(_state(team)["object_availability"].get(object_id, catalog_default))


func starting_technology_ids(team: int, maximum_completed_age: int) -> Array[int]:
	var result: Array[int] = []
	for key in catalog.get("technologies", {}):
		var technology_id := int(key)
		if technology_id in AGE_TECHNOLOGY_IDS or is_technology_disabled(team, technology_id):
			continue
		var record: Dictionary = catalog["technologies"][key]
		if int(record.get("technology_type", 0)) == 0:
			continue
		if int(record.get("research_location_id", -1)) < 0:
			continue
		if int(record.get("language", {}).get("name_id", 0)) <= 0:
			continue
		if _required_age(technology_id, {}) <= maximum_completed_age:
			result.append(technology_id)
	result.sort()
	return result


func _required_age(technology_id: int, visiting: Dictionary) -> int:
	if technology_id in AGE_TECHNOLOGY_IDS:
		return technology_id
	if visiting.has(technology_id):
		return 100
	var record := technology(technology_id)
	if record.is_empty():
		return 100
	visiting[technology_id] = true
	var required_age := 100
	for value in record.get("required_technology_ids", []):
		var requirement_id := int(value)
		if requirement_id >= 0:
			required_age = maxi(required_age, _required_age(requirement_id, visiting))
	visiting.erase(technology_id)
	return required_age


func current_age(team: int) -> int:
	return int(_state(team).get("current_age", 100))


func researched_ids(team: int) -> Array[int]:
	var result: Array[int] = []
	for value in _state(team)["researched"].keys():
		result.append(int(value))
	result.sort()
	return result


func persistent_entity_effects(team: int) -> Array:
	return _state(team)["entity_effects"].duplicate(true)


func resolved_unit_id(team: int, source_id: int) -> int:
	var upgrades: Dictionary = _state(team)["unit_upgrades"]
	var resolved := source_id
	var visited: Dictionary = {}
	while upgrades.has(resolved) and not visited.has(resolved):
		visited[resolved] = true
		resolved = int(upgrades[resolved])
	return resolved


func technology_name_id(technology_id: int) -> int:
	return int(technology(technology_id).get("language", {}).get("name_id", 0))


func _requirement_satisfied(team: int, technology_id: int, visiting: Dictionary) -> bool:
	if is_researched(team, technology_id):
		return true
	if visiting.has(technology_id):
		return false
	var record := technology(technology_id)
	if record.is_empty() or int(record.get("technology_type", -1)) != 0:
		return false
	var required_count := maxi(0, int(record.get("required_technology_count", 0)))
	if required_count == 0:
		return true
	visiting[technology_id] = true
	var satisfied := 0
	var valid := 0
	for value in record.get("required_technology_ids", []):
		var child_id := int(value)
		if child_id < 0:
			continue
		valid += 1
		if _requirement_satisfied(team, child_id, visiting.duplicate()):
			satisfied += 1
	visiting.erase(technology_id)
	return satisfied >= mini(required_count, valid)


func _register_persistent_effect(team: int, command_value: Variant) -> void:
	var command: Dictionary = command_value
	var state := _state(team)
	var raw_type := int(command.get("type_id", -1))
	var effect_type := raw_type
	if effect_type in [10, 11, 12, 13, 14, 15, 16]:
		effect_type -= 10
	elif effect_type in [20, 21, 22, 23, 24, 25, 26]:
		effect_type -= 20
	match effect_type:
		0, 4, 5:
			state["entity_effects"].append(command.duplicate(true))
		2:
			state["object_availability"][int(command.get("attr_a", -1))] = int(command.get("attr_b", 0)) != 0
		3:
			state["unit_upgrades"][int(command.get("attr_a", -1))] = int(command.get("attr_b", -1))
		101:
			var technology_id := int(command.get("attr_a", -1))
			var resource_id := int(command.get("attr_b", -1))
			if not state["technology_cost_modifiers"].has(technology_id):
				state["technology_cost_modifiers"][technology_id] = {}
			if not state["technology_cost_modifiers"][technology_id].has(resource_id):
				state["technology_cost_modifiers"][technology_id][resource_id] = []
			state["technology_cost_modifiers"][technology_id][resource_id].append({"operator": 0 if int(command.get("attr_c", 0)) == 0 else 4, "value": float(command.get("attr_d", 0.0))})
		102:
			state["disabled_technologies"][int(command.get("attr_d", -1))] = true
		103:
			var technology_id := int(command.get("attr_a", -1))
			if not state["technology_time_modifiers"].has(technology_id):
				state["technology_time_modifiers"][technology_id] = []
			state["technology_time_modifiers"][technology_id].append({"operator": 0 if int(command.get("attr_c", 0)) == 0 else 4, "value": float(command.get("attr_d", 0.0))})


func _state(team: int) -> Dictionary:
	if not team_states.has(team):
		team_states[team] = {
			"researched": {},
			"researching": {},
			"current_age": 100,
			"object_availability": {},
			"scenario_disabled_objects": {},
			"disabled_technologies": {},
			"unit_upgrades": {},
			"entity_effects": [],
			"technology_cost_modifiers": {},
			"technology_time_modifiers": {},
		}
	return team_states[team]


func _apply_operator(current: float, operator: int, value: float) -> float:
	match operator:
		0:
			return value
		4:
			return current + value
		5:
			return current * value
	return current
