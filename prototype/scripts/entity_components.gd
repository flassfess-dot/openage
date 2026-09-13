class_name RoREntityComponents

const COMPONENT_NAMES: Array[String] = [
	"transform",
	"ownership",
	"health",
	"movement",
	"footprint",
	"vision",
	"combat",
	"conversion",
	"healing",
	"resource_carrier",
	"cargo",
	"trade",
	"worker",
	"production",
	"technology",
	"animation_state",
]


static func for_unit(entity_id: int, team: int, civilization_id: int, kind: String, position: Vector2, elevation: float, stats: Dictionary, source: Dictionary, footprint: Dictionary, facing: int) -> Dictionary:
	var combat_source: Dictionary = source.get("combat", {})
	var resource_source: Dictionary = source.get("resources", {})
	var production_source: Dictionary = source.get("production", {})
	var attacks: Array = combat_source.get("attacks", stats.get("attacks", [])).duplicate(true)
	var armors: Array = combat_source.get("armors", stats.get("armors", [])).duplicate(true)
	var max_health := float(source.get("health", stats.get("hit_points", 25.0)))
	var terrain_restriction := int(source.get("links", {}).get("terrain_restriction", stats.get("terrain_restriction", -1)))
	var movement_domain := "water" if terrain_restriction == 3 else "land"
	var capacity := float(resource_source.get("capacity", stats.get("resource_capacity", 0.0)))
	var population_cost := 0
	for cost_value in resource_source.get("cost", stats.get("resource_cost", [])):
		var cost: Dictionary = cost_value
		if int(cost.get("type_id", -1)) == 4:
			population_cost = maxi(0, int(cost.get("amount", 0)))
			break
	var unit_class := int(source.get("unit_class", -1))
	var behavior_tags: Array = stats.get("behavior_tags", [])
	var command_data: Array = source.get("commands", []).duplicate(true)
	var conversion_command: Dictionary = {}
	var healing_command: Dictionary = {}
	for command_value in command_data:
		var command: Dictionary = command_value
		match int(command.get("type", command.get("type_id", -1))):
			104: conversion_command = command
			105: healing_command = command
	var conversion_enabled := not conversion_command.is_empty()
	var conversion_runtime: Dictionary = stats.get("runtime", {}).get("conversion", {})
	var healing_runtime: Dictionary = stats.get("runtime", {}).get("healing", {})
	var cargo_runtime: Dictionary = stats.get("runtime", {}).get("cargo", {})
	var trade_runtime: Dictionary = stats.get("runtime", {}).get("trade", {})
	var projectile_impact_runtime: Dictionary = stats.get("runtime", {}).get("projectile_impact", {})
	var trade_command: Dictionary = {}
	for command_value in command_data:
		var command: Dictionary = command_value
		if int(command.get("type", command.get("type_id", -1))) == 111:
			trade_command = command
			break
	var allowed_trade_input_ids: Array[int] = []
	for resource_type_value in trade_runtime.get("allowed_input_resource_type_ids", [0, 1, 2]):
		allowed_trade_input_ids.append(int(resource_type_value))
	var conversion_interval := maxf(0.1, float(combat_source.get("attack_period", stats.get("attack_period", 1.5))))
	var minimum_chants := maxi(1, int(conversion_runtime.get("minimum_chants", roundi(float(conversion_command.get("work_value2", 3.0))))))
	return {
		"transform": {
			"position": position,
			"previous_position": position,
			"elevation": elevation,
			"facing": facing,
			"movement_facing": facing,
			"desired_facing": facing,
			"action_facing": facing,
		},
		"ownership": {
			"player_id": team,
			"team_id": team,
			"civilization_id": civilization_id,
		},
		"health": {
			"current": max_health,
			"maximum": max_health,
			"alive": max_health > 0.0,
		},
		"movement": {
			"speed": float(source.get("speed", stats.get("speed", 1.1))),
			"turn_speed": float(source.get("turn_speed", stats.get("turn_speed", 0.0))),
			"terrain_restriction": terrain_restriction,
			"domain": movement_domain,
			"target": position,
			"destination": position,
			"path": [],
			"path_index": 0,
			"path_request_id": 0,
			"path_status": "idle",
			"path_grid_revision": 0,
			"desired_velocity": Vector2.ZERO,
			"actual_velocity": Vector2.ZERO,
		},
		"footprint": footprint.duplicate(true),
		"vision": {
			"range": float(source.get("line_of_sight", stats.get("line_of_sight", 0.0))),
			"enabled": float(source.get("line_of_sight", stats.get("line_of_sight", 0.0))) > 0.0,
		},
		"combat": {
			"attacks": attacks,
			"armors": armors,
			"attack_period": float(combat_source.get("attack_period", stats.get("attack_period", 0.0))),
			"range_min": float(combat_source.get("range_min", stats.get("range_min", 0.0))),
			"range_max": float(combat_source.get("range_max", stats.get("range", 0.0))),
			"blast_range": float(combat_source.get("blast_range", 0.0)),
			"friendly_fire": bool(projectile_impact_runtime.get("friendly_fire", false)),
			"blast_falloff": String(projectile_impact_runtime.get("blast_falloff", "none")),
			"impact_effect_graphic_id": int(projectile_impact_runtime.get("impact_effect_graphic_id", -1)),
			"accuracy": int(combat_source.get("accuracy", stats.get("accuracy", 0))),
			"projectile_id": int(combat_source.get("projectile_id", stats.get("projectile_id", -1))),
			"frame_delay": int(combat_source.get("frame_delay", stats.get("attack_frame_delay", 0))),
			"weapon_offset": combat_source.get("weapon_offset", stats.get("weapon_offset", [0.0, 0.0, 0.0])).duplicate(),
			"target_id": -1,
			"cooldown": 0.0,
			"stance": "passive",
			"acquisition_range": 0.0,
			"chase_range": 0.0,
			"retaliation_target_id": -1,
		},
		"conversion": {
			"enabled": conversion_enabled,
			"faith": 100.0 if conversion_enabled else 0.0,
			"max_faith": 100.0,
			"recharge_rate": 2.0,
			"target_id": -1,
			"chant_elapsed": 0.0,
			"chants": 0,
			"min_chants": minimum_chants,
			"max_chants": maxi(minimum_chants, int(conversion_runtime.get("maximum_chants", 100))),
			"chant_interval": conversion_interval,
			"base_success_chance": clampf(float(conversion_runtime.get("base_success_chance", conversion_command.get("work_value1", 0.30))), 0.0, 1.0),
			"chance_multiplier": 1.0,
			"building_range": maxf(0.0, float(conversion_runtime.get("building_range", 1.0))),
			"resistant_target_multiplier": clampf(float(conversion_runtime.get("resistant_target_multiplier", 0.25)), 0.0, 1.0),
			"active": false,
		},
		"healing": {
			"enabled": not healing_command.is_empty(),
			"base_rate": maxf(0.0, float(healing_command.get("work_value1", 0.0))),
			"range": maxf(0.0, float(healing_runtime.get("range", 4.0))),
			"bonus_resource_id": int(healing_runtime.get("bonus_resource_id", 56)),
			"rate_multiplier": 1.0,
			"target_id": -1,
			"restored_amount": 0.0,
			"active": false,
		},
		"resource_carrier": {
			"capacity": capacity,
			"amount": 0.0,
			"resource_type_id": -1,
		},
		"cargo": {
			"enabled": bool(cargo_runtime.get("enabled", false)) or "transport" in behavior_tags,
			"capacity": maxi(0, int(cargo_runtime.get("capacity", roundi(capacity)))),
			"passenger_ids": [],
			"allowed_domains": cargo_runtime.get("allowed_domains", ["land"]).duplicate(),
		},
		"trade": {
			"enabled": bool(trade_runtime.get("enabled", false)) or not trade_command.is_empty(),
			"target_building_source_id": int(trade_command.get("unit_id", -1)),
			"source_input_resource_id": int(trade_command.get("resource_in", -1)),
			"output_resource_type_id": int(trade_runtime.get("output_resource_type_id", trade_command.get("resource_out", 3))),
			"source_work_value": float(trade_command.get("work_value1", 0.0)),
			"transaction_amount": maxi(1, int(trade_runtime.get("transaction_amount", roundi(capacity)))),
			"pool_initial": float(trade_runtime.get("pool_initial", 0.0)),
			"pool_maximum": maxf(1.0, float(trade_runtime.get("pool_maximum", 100.0))),
			"pool_recovery_per_second": maxf(0.0, float(trade_runtime.get("pool_recovery_per_second", 1.0))),
			"allowed_input_resource_type_ids": allowed_trade_input_ids,
			"selected_input_resource_type_id": int(trade_runtime.get("default_input_resource_type_id", 1)),
			"profit_policy": String(trade_runtime.get("profit_policy", "ror_distance_calibration_pending_v1")),
			"target_dock_id": -1,
			"home_dock_id": -1,
			"stage": "idle",
			"approach_position": position,
			"cargo_goods": 0,
			"cargo_gold": 0,
			"trip_count": 0,
		},
		"worker": {
			"enabled": (unit_class == 4 or "worker" in behavior_tags) and not command_data.is_empty(),
			"work_rate": float(source.get("work_rate", stats.get("work_rate", 0.0))),
			"commands": command_data,
			"task_group": int(source.get("links", {}).get("task_group", 0)),
			"drop_site_ids": resource_source.get("drop_site_ids", []).duplicate(),
			"resource_id": -1,
			"action_cooldown": 0.0,
		},
		"production": {
			"queue": [],
			"progress": 0.0,
			"creation_time": int(production_source.get("creation_time", stats.get("creation_time", 0))),
			"train_location_id": int(production_source.get("train_location_id", -1)),
			"population_cost": population_cost,
		},
		"technology": {
			"available_ids": [],
			"researched_ids": [],
			"active_research_id": int(production_source.get("research_id", -1)),
			"progress": 0.0,
		},
		"animation_state": {
			"state": "Idle",
			"elapsed": 0.0,
			"frame": 0,
			"events_fired": {},
		},
		"order": {
			"type": "none",
			"phase": "RepeatOrComplete",
			"target_entity_id": -1,
			"target_position": position,
			"repeat": false,
			"completed": true,
			"completion_reason": "idle",
			"revision": 0,
			"history": [],
		},
		"identity": {
			"entity_id": entity_id,
			"kind": kind,
			"source_unit_id": int(source.get("unit_id", stats.get("unit_id", -1))),
			"source_key": String(source.get("key", "")),
		},
	}


static func for_building(entity_id: int, team: int, civilization_id: int, kind: String, position: Vector2, elevation: float, stats: Dictionary, source: Dictionary, footprint: Dictionary) -> Dictionary:
	var components := for_unit(entity_id, team, civilization_id, kind, position, elevation, stats, source, footprint, 0)
	components["movement"]["speed"] = 0.0
	components["movement"]["domain"] = "static"
	components["worker"]["enabled"] = false
	return components


static func for_resource(entity_id: int, kind: String, position: Vector2, elevation: float, amount: int, source: Dictionary, footprint: Dictionary) -> Dictionary:
	var stats := {
		"unit_id": int(source.get("unit_id", -1)),
		"hit_points": float(source.get("health", 1.0)),
		"line_of_sight": float(source.get("line_of_sight", 0.0)),
		"speed": 0.0,
	}
	var components := for_unit(entity_id, 0, 0, kind, position, elevation, stats, source, footprint, 0)
	components["movement"]["domain"] = "static"
	components["worker"]["enabled"] = false
	components["resource_carrier"]["capacity"] = float(amount)
	components["resource_carrier"]["amount"] = float(amount)
	return components


static func sync_dynamic(entity: Dictionary) -> void:
	var components: Dictionary = entity.get("components", {})
	if components.is_empty():
		return
	var transform: Dictionary = components.get("transform", {})
	transform["position"] = entity.get("pos", transform.get("position", Vector2.ZERO))
	transform["previous_position"] = entity.get("previous_pos", transform.get("previous_position", transform["position"]))
	transform["elevation"] = float(entity.get("elevation", transform.get("elevation", 0.0)))
	transform["facing"] = int(entity.get("facing", transform.get("facing", 0)))
	transform["movement_facing"] = int(entity.get("movement_facing", transform.get("movement_facing", transform["facing"])))
	transform["desired_facing"] = int(entity.get("desired_facing", transform.get("desired_facing", transform["facing"])))
	transform["action_facing"] = int(entity.get("action_facing", transform.get("action_facing", transform["facing"])))

	var health: Dictionary = components.get("health", {})
	health["current"] = float(entity.get("hp", health.get("current", 0.0)))
	health["maximum"] = float(entity.get("max_hp", health.get("maximum", 0.0)))
	health["alive"] = float(health["current"]) > 0.0

	var movement: Dictionary = components.get("movement", {})
	for mapping in [
		["target", "target"], ["destination", "destination"], ["path", "path"],
		["path_index", "path_index"], ["desired_velocity", "desired_velocity"],
		["path_request_id", "path_request_id"], ["path_status", "path_status"],
		["path_grid_revision", "path_grid_revision"],
		["actual_velocity", "actual_velocity"], ["speed", "speed"],
		["terrain_restriction", "terrain_restriction"], ["domain", "movement_domain"],
	]:
		if entity.has(mapping[1]):
			movement[mapping[0]] = entity[mapping[1]]

	var combat: Dictionary = components.get("combat", {})
	combat["target_id"] = int(entity.get("target_id", combat.get("target_id", -1)))
	combat["cooldown"] = float(entity.get("cooldown", combat.get("cooldown", 0.0)))
	combat["stance"] = String(entity.get("stance", combat.get("stance", "passive")))
	combat["acquisition_range"] = float(entity.get("acquisition_range", combat.get("acquisition_range", 0.0)))
	combat["chase_range"] = float(entity.get("chase_range", combat.get("chase_range", 0.0)))
	combat["retaliation_target_id"] = int(entity.get("retaliation_target_id", combat.get("retaliation_target_id", -1)))

	var carrier: Dictionary = components.get("resource_carrier", {})
	if entity.has("amount"):
		carrier["amount"] = float(entity["amount"])
	if entity.has("carried_amount"):
		carrier["amount"] = float(entity["carried_amount"])
	if entity.has("carried_resource_type_id"):
		carrier["resource_type_id"] = int(entity["carried_resource_type_id"])

	var worker: Dictionary = components.get("worker", {})
	worker["resource_id"] = int(entity.get("resource_id", worker.get("resource_id", -1)))
	worker["action_cooldown"] = float(entity.get("work", worker.get("action_cooldown", 0.0)))

	var animation: Dictionary = components.get("animation_state", {})
	animation["state"] = String(entity.get("anim_state", animation.get("state", "Idle")))
	animation["elapsed"] = float(entity.get("anim", animation.get("elapsed", 0.0)))
	animation["events_fired"] = entity.get("animation_events_fired", animation.get("events_fired", {}))


static func has_complete_schema(entity: Dictionary) -> bool:
	var components: Dictionary = entity.get("components", {})
	for component_name in COMPONENT_NAMES:
		if not components.has(component_name):
			return false
	return true
