class_name RoRAiPlayer
extends RefCounted

const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const SourceAssignmentGroup := preload("res://scripts/source_ai_assignment_group.gd")
const SourceAttackGroup := preload("res://scripts/source_ai_attack_group.gd")
const SourceCityPlan := preload("res://scripts/source_ai_city_plan.gd")
const SourceCampaignPlanner := preload("res://scripts/source_campaign_ai_planner.gd")
const StrategicPlanner := preload("res://scripts/ai_strategic_planner.gd")
const TacticalPlanner := preload("res://scripts/ai_tactical_planner.gd")
const TransportPlanner := preload("res://scripts/ai_transport_planner.gd")
const SupportPlanner := preload("res://scripts/ai_support_planner.gd")
const Commands := preload("res://scripts/commands.gd")

var team: int
var enabled: bool
var economic_interval: int
var military_interval: int
var formation_name: String
var profile: String
var source_contract: Dictionary
var initial_attack_delay: int
var attack_separation: int
var minimum_attack_group_size: int
var maximum_attack_group_size: int
var enemy_response_distance: float
var use_workers_in_attack_groups: bool
var economic_policy: Dictionary
var last_economic_tick: int = -1
var last_military_tick: int = -1
var last_attack_tick: int = -1
var last_response_tick: int = -1
var last_tribute_tick: int = -1
var decision_index: int = 0
var source_attack_groups: Dictionary = {}
var next_source_attack_group_id: int = 1
var source_assignment_groups: Dictionary = {}
var next_source_assignment_group_id: int = 1
var source_city_plan
var failed_gather_targets: Dictionary = {}


func _init(player_definition: Dictionary) -> void:
	team = int(player_definition.get("team", 0))
	var settings: Dictionary = player_definition.get("ai", {})
	enabled = bool(settings.get("enabled", true))
	economic_interval = maxi(1, int(settings.get("economic_interval_ticks", 20)))
	military_interval = maxi(1, int(settings.get("military_interval_ticks", 40)))
	formation_name = String(settings.get("formation", "RECTANGLE"))
	profile = String(settings.get("profile", "skirmish"))
	initial_attack_delay = maxi(0, int(settings.get("initial_attack_delay_ticks", 0)))
	attack_separation = maxi(0, int(settings.get("attack_separation_ticks", 0)))
	minimum_attack_group_size = maxi(1, int(settings.get("minimum_attack_group_size", 1)))
	maximum_attack_group_size = maxi(minimum_attack_group_size, int(settings.get("maximum_attack_group_size", 9999)))
	enemy_response_distance = maxf(0.0, float(settings.get("enemy_response_distance", 0.0)))
	use_workers_in_attack_groups = bool(settings.get("use_workers_in_attack_groups", true))
	economic_policy = {
		"construction_priorities": settings.get("construction_priorities", []).duplicate(),
		"building_limits": settings.get("building_limits", {}).duplicate(true),
		"housing_buffer": maxi(0, int(settings.get("housing_buffer", 0))),
		"land_worker_target": maxi(0, int(settings.get("land_worker_target", settings.get("worker_target", 0)))),
		"water_worker_target": maxi(0, int(settings.get("water_worker_target", 2))),
		"minimum_workers_before_age_up": maxi(0, int(settings.get("minimum_workers_before_age_up", 0))),
		"age_advance_technology_ids": settings.get("age_advance_technology_ids", []).duplicate(),
		"age_saving_construction_exceptions": settings.get("age_saving_construction_exceptions", []).duplicate(),
		"age_saving_production_exceptions": settings.get("age_saving_production_exceptions", []).duplicate(),
		"structure_gap_fallback_kinds": settings.get("structure_gap_fallback_kinds", []).duplicate(),
		"minimum_structure_gap": maxf(0.0, float(settings.get("minimum_structure_gap", 0.0))),
		"tribute_target_team": int(settings.get("tribute_target_team", -1)),
		"tribute_resource_type_id": int(settings.get("tribute_resource_type_id", 0)),
		"tribute_amount": maxi(0, int(settings.get("tribute_amount", 0))),
		"tribute_reserve": maxi(0, int(settings.get("tribute_reserve", 0))),
		"tribute_cooldown_ticks": maxi(1, int(settings.get("tribute_cooldown_ticks", 600))),
	}
	source_contract = player_definition.get("source_ai", {}).duplicate(true)
	source_city_plan = SourceCityPlan.new(team)


func needs_decision(next_tick: int) -> bool:
	var military_enabled := profile != "source_campaign_v1" or bool(source_contract.get("runtime_support", {}).get("military_enabled", true))
	return enabled and (last_economic_tick < 0 or next_tick - last_economic_tick >= economic_interval or (military_enabled and (last_military_tick < 0 or next_tick - last_military_tick >= military_interval)))


func collect_commands(snapshot: Dictionary, next_tick: int) -> Array:
	if not enabled:
		return []
	if bool(snapshot.get("match_result", {}).get("over", false)):
		return []
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	if String(snapshot.get("player_state", {}).get("status", "active")) != "active":
		return []
	var result: Array = []
	if profile == "source_campaign_v1":
		var economic_reserved: Dictionary = {}
		if last_economic_tick < 0 or next_tick - last_economic_tick >= economic_interval:
			var economic_commands: Array = SourceCampaignPlanner.plan_economy(snapshot, next_tick, team, source_contract, source_city_plan)
			result.append_array(economic_commands)
			for command in economic_commands:
				for unit_id in command.unit_ids:
					economic_reserved[int(unit_id)] = true
			last_economic_tick = next_tick
		var military_enabled := bool(source_contract.get("runtime_support", {}).get("military_enabled", true))
		if military_enabled and (last_military_tick < 0 or next_tick - last_military_tick >= military_interval):
			var runtime_support: Dictionary = source_contract.get("runtime_support", {})
			var response_enabled := bool(runtime_support.get("defence_response_enabled", false))
			var attack_enabled := bool(runtime_support.get("attack_enabled", military_enabled))
			var defence_enabled := bool(runtime_support.get("defence_enabled", false))
			var exploration_enabled := bool(runtime_support.get("exploration_enabled", false))
			var naval_defence_enabled := bool(runtime_support.get("naval_defence_enabled", false))
			var naval_exploration_enabled := bool(runtime_support.get("naval_exploration_enabled", false))
			var naval_escort_enabled := bool(runtime_support.get("naval_escort_enabled", false))
			var committed_unit_ids: Dictionary = economic_reserved.duplicate()
			if not source_attack_groups.is_empty():
				var lifecycle := SourceCampaignPlanner.plan_attack_group_lifecycle(snapshot, next_tick, team, source_contract, source_attack_groups)
				result.append_array(lifecycle.get("commands", []))
				committed_unit_ids.merge(lifecycle.get("excluded_unit_ids", {}), true)
			if not source_assignment_groups.is_empty():
				var assignment_lifecycle := SourceCampaignPlanner.plan_assignment_group_lifecycle(snapshot, next_tick, team, source_assignment_groups)
				result.append_array(assignment_lifecycle.get("commands", []))
				committed_unit_ids.merge(assignment_lifecycle.get("excluded_unit_ids", {}), true)
			if defence_enabled or exploration_enabled or naval_defence_enabled or naval_exploration_enabled or naval_escort_enabled:
				var assignments := SourceCampaignPlanner.plan_strategic_assignments(snapshot, next_tick, team, source_contract, source_assignment_groups, committed_unit_ids, next_source_assignment_group_id, formation_name)
				result.append_array(assignments.get("commands", []))
				for group in assignments.get("groups", []):
					source_assignment_groups[int(group.group_id)] = group
					next_source_assignment_group_id = maxi(next_source_assignment_group_id, int(group.group_id) + 1)
				for unit_id in assignments.get("unit_ids", []):
					committed_unit_ids[int(unit_id)] = true
			if response_enabled:
				var response := SourceCampaignPlanner.plan_response(snapshot, next_tick, team, source_contract, last_response_tick, committed_unit_ids)
				if bool(response.get("issued", false)):
					result.append_array(response.get("commands", []))
					last_response_tick = next_tick
					for unit_id in response.get("unit_ids", []):
						committed_unit_ids[int(unit_id)] = true
			if attack_enabled:
				var military := SourceCampaignPlanner.plan_military(snapshot, next_tick, team, source_contract, last_attack_tick, decision_index, committed_unit_ids, next_source_attack_group_id, formation_name, _has_active_source_attack_group())
				if bool(military.get("issued", false)):
					result.append_array(military.get("commands", []))
					for group in military.get("groups", []):
						source_attack_groups[int(group.group_id)] = group
						next_source_attack_group_id = maxi(next_source_attack_group_id, int(group.group_id) + 1)
					last_attack_tick = next_tick
					decision_index += 1
				_prune_completed_source_groups()
			_prune_completed_assignment_groups()
			last_military_tick = next_tick
		return result
	var skirmish_reserved_ids: Dictionary = {}
	if last_economic_tick < 0 or next_tick - last_economic_tick >= economic_interval:
		_remember_failed_gather_targets(snapshot)
		var support_commands: Array = SupportPlanner.plan(snapshot, next_tick, team)
		result.append_array(support_commands)
		for command in support_commands:
			for unit_id in command.unit_ids:
				skirmish_reserved_ids[int(unit_id)] = true
		var current_economic_policy := economic_policy.duplicate()
		current_economic_policy["failed_gather_targets"] = failed_gather_targets
		if last_attack_tick >= 0:
			current_economic_policy["wartime_combatant_target"] = maxi(6, minimum_attack_group_size)
		var economic_commands: Array = EconomicPlanner.plan(snapshot, next_tick, team, current_economic_policy, skirmish_reserved_ids)
		result.append_array(economic_commands)
		for command in economic_commands:
			for unit_id in command.unit_ids:
				skirmish_reserved_ids[int(unit_id)] = true
		var tribute_command: Variant = _plan_tribute(snapshot, next_tick)
		if tribute_command != null:
			result.append(tribute_command)
		last_economic_tick = next_tick
	if last_military_tick < 0 or next_tick - last_military_tick >= military_interval:
		var goal := StrategicPlanner.choose_goal(snapshot, team, decision_index)
		decision_index += 1
		var attack_allowed := true
		if profile == "skirmish_policy_v1" and String(goal.get("type", "")) == "attack":
			var responding := _target_threatens_owned_position(snapshot, Vector2(goal.get("position", Vector2.ZERO)))
			attack_allowed = responding or (next_tick >= initial_attack_delay and (last_attack_tick < 0 or next_tick - last_attack_tick >= attack_separation))
		var tactical_commands: Array = []
		if attack_allowed:
			var transport_commands: Array = TransportPlanner.plan(snapshot, next_tick, team, goal, formation_name, skirmish_reserved_ids)
			result.append_array(transport_commands)
			for command in transport_commands:
				for unit_id in command.unit_ids:
					skirmish_reserved_ids[int(unit_id)] = true
			var refresh_stalled_attack := last_attack_tick >= 0 and next_tick - last_attack_tick >= maxi(400, attack_separation)
			tactical_commands = TacticalPlanner.plan(snapshot, next_tick, team, goal, formation_name, minimum_attack_group_size, maximum_attack_group_size, use_workers_in_attack_groups, skirmish_reserved_ids, refresh_stalled_attack)
			result.append_array(tactical_commands)
		elif String(goal.get("type", "")) == "attack" and not goal.get("positions_by_domain", {}).is_empty():
			tactical_commands = TacticalPlanner.plan(snapshot, next_tick, team, {"type": "explore", "positions_by_domain": goal["positions_by_domain"]}, formation_name, minimum_attack_group_size, maximum_attack_group_size, use_workers_in_attack_groups, skirmish_reserved_ids)
			result.append_array(tactical_commands)
		if String(goal.get("type", "")) == "attack" and tactical_commands.any(func(command): return String(command.command_type()) == "attack"):
			last_attack_tick = next_tick
		last_military_tick = next_tick
	return result


func _remember_failed_gather_targets(snapshot: Dictionary) -> void:
	if not failed_gather_targets.is_empty():
		var live_workers: Dictionary = {}
		for unit_value in snapshot.get("units", []):
			var unit: Dictionary = unit_value
			if int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0:
				live_workers[int(unit.get("id", -1))] = true
		var available_resources: Dictionary = {}
		for resource_value in snapshot.get("resources", []):
			if int(resource_value.get("amount", 0)) > 0:
				available_resources[int(resource_value.get("id", -1))] = true
		for worker_id_value in failed_gather_targets.keys():
			if not live_workers.has(int(worker_id_value)):
				failed_gather_targets.erase(worker_id_value)
				continue
			var failures: Dictionary = failed_gather_targets[worker_id_value]
			for resource_id_value in failures.keys():
				if not available_resources.has(int(resource_id_value)):
					failures.erase(resource_id_value)
			if failures.is_empty():
				failed_gather_targets.erase(worker_id_value)
	for unit_value in snapshot.get("units", []):
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) != team:
			continue
		var order: Dictionary = unit.get("components", {}).get("order", {})
		if String(order.get("type", "")) != "gather" or not bool(order.get("completed", false)) or String(order.get("completion_reason", "")) not in ["no_approach_slot", "no_path", "local_blocked"]:
			continue
		var target_id := int(order.get("target_entity_id", -1))
		if target_id < 0:
			continue
		var worker_id := int(unit.get("id", -1))
		var failures: Dictionary = failed_gather_targets.get(worker_id, {})
		failures[target_id] = true
		failed_gather_targets[worker_id] = failures


func _plan_tribute(snapshot: Dictionary, tick: int) -> Variant:
	var recipient := int(economic_policy.get("tribute_target_team", -1))
	var requested := int(economic_policy.get("tribute_amount", 0))
	var resource_type_id := int(economic_policy.get("tribute_resource_type_id", 0))
	if recipient <= 0 or recipient == team or requested <= 0 or resource_type_id not in [0, 1, 2, 3]:
		return null
	var player_state: Dictionary = snapshot.get("player_state", {})
	if recipient not in player_state.get("allies", []):
		return null
	if last_tribute_tick >= 0 and tick - last_tribute_tick < int(economic_policy.get("tribute_cooldown_ticks", 600)):
		return null
	var resource_name: String = ["food", "wood", "stone", "gold"][resource_type_id]
	var available := int(player_state.get(resource_name, 0)) - int(economic_policy.get("tribute_reserve", 0))
	var amount := mini(requested, available)
	if amount <= 0:
		return null
	last_tribute_tick = tick
	return Commands.TributeCommand.new(tick, recipient, resource_type_id, amount)


func _target_threatens_owned_position(snapshot: Dictionary, target_position: Vector2) -> bool:
	if enemy_response_distance <= 0.0:
		return false
	for category in ["buildings", "units"]:
		for entity_value in snapshot.get(category, []):
			var entity: Dictionary = entity_value
			if int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0 and Vector2(entity.get("pos", Vector2.ZERO)).distance_to(target_position) <= enemy_response_distance:
				return true
	return false


func presentation_options() -> Dictionary:
	if profile == "source_campaign_v1":
		var source_numbers: Dictionary = SourceCampaignPlanner.strategic_number_values(source_contract)
		var extermination_enabled := int(source_numbers.get(49, -1)) == 3
		var exploration_enabled := bool(source_contract.get("runtime_support", {}).get("exploration_enabled", false))
		var naval_exploration_enabled := bool(source_contract.get("runtime_support", {}).get("naval_exploration_enabled", false))
		var naval_attack_enabled := bool(source_contract.get("runtime_support", {}).get("naval_attack_enabled", false))
		var map_knowledge_required := extermination_enabled or exploration_enabled or naval_exploration_enabled or naval_attack_enabled
		var production_requests: Array = []
		var requested_build_site_kinds: Array = ["house"]
		for entry_value in source_contract.get("build_order", []):
			var entry: Dictionary = entry_value
			var entry_type := String(entry.get("type", ""))
			if entry_type == "building":
				var building_alias := String(entry.get("runtime_alias", ""))
				if not building_alias.is_empty() and building_alias not in requested_build_site_kinds:
					requested_build_site_kinds.append(building_alias)
			else:
				production_requests.append({
					"type": entry_type,
					"source_id": int(entry.get("source_id", -1)),
					"producer_source_unit_id": int(entry.get("producer_source_unit_id", -1)),
					"runtime_alias": String(entry.get("runtime_alias", "")),
				})
		var preferred_build_sites: Dictionary = {}
		var strict_preferred_build_site_kinds: Array = []
		var maximum_build_sites_per_kind := 4
		if source_city_plan != null and source_city_plan.enabled and source_city_plan.initialized and "wall" in requested_build_site_kinds:
			preferred_build_sites["wall"] = source_city_plan.preferred_wall_sites()
			strict_preferred_build_site_kinds.append("wall")
			maximum_build_sites_per_kind = maxi(maximum_build_sites_per_kind, preferred_build_sites["wall"].size())
		return {
			"compact_entities": true,
			"include_navigation": map_knowledge_required,
			"include_build_sites": false,
			"include_fog_cells": map_knowledge_required,
			"include_projectiles": false,
			"include_scenario": false,
			"include_worker_command_options": false,
			"requested_production_only": true,
			"production_requests": production_requests,
			"requested_build_site_kinds": requested_build_site_kinds,
			"maximum_build_sites_per_kind": maximum_build_sites_per_kind,
			"build_site_search_radius": source_city_plan.recommended_search_radius() if source_city_plan != null and source_city_plan.enabled else 12,
			# Static navigation revision and worker land-component membership both
			# invalidate this cache. A long time cap prevents periodic full placement
			# scans from coinciding with every strategic decision.
			"build_site_cache_ticks": 1200,
			"minimum_structure_gap": float(economic_policy.get("minimum_structure_gap", 0.0)),
			"preferred_build_sites": preferred_build_sites,
			"strict_preferred_build_site_kinds": strict_preferred_build_site_kinds,
		}
	if profile in ["skirmish_policy_v1", "skirmish"]:
		return {
			"compact_entities": true,
			"include_navigation": true,
			"include_build_sites": false,
			"include_fog_cells": false,
			"include_projectiles": false,
			"include_scenario": false,
			"include_worker_command_options": false,
			"requested_build_site_kinds": economic_policy.get("construction_priorities", []).duplicate(),
			"planning_technology_ids": economic_policy.get("age_advance_technology_ids", []).duplicate(),
			"maximum_build_sites_per_kind": 12,
			"build_site_search_radius": 12,
			"minimum_structure_gap": float(economic_policy.get("minimum_structure_gap", 0.0)),
		}
	return {}


func canonical_state() -> Dictionary:
	var group_ids: Array = source_attack_groups.keys()
	group_ids.sort()
	var groups: Array = []
	for group_id in group_ids:
		groups.append(source_attack_groups[group_id].canonical_state())
	var assignment_group_ids: Array = source_assignment_groups.keys()
	assignment_group_ids.sort()
	var assignment_groups: Array = []
	for group_id in assignment_group_ids:
		assignment_groups.append(source_assignment_groups[group_id].canonical_state())
	var failed_gathers: Array = []
	var worker_ids: Array = failed_gather_targets.keys()
	worker_ids.sort()
	for worker_id in worker_ids:
		var resource_ids: Array = failed_gather_targets[worker_id].keys()
		resource_ids.sort()
		failed_gathers.append({"worker_id": int(worker_id), "resource_ids": resource_ids})
	return {
		"team": team,
		"enabled": enabled,
		"profile": profile,
		"last_economic_tick": last_economic_tick,
		"last_military_tick": last_military_tick,
		"last_attack_tick": last_attack_tick,
		"last_response_tick": last_response_tick,
		"last_tribute_tick": last_tribute_tick,
		"decision_index": decision_index,
		"next_source_attack_group_id": next_source_attack_group_id,
		"source_attack_groups": groups,
		"next_source_assignment_group_id": next_source_assignment_group_id,
		"source_assignment_groups": assignment_groups,
		"failed_gather_targets": failed_gathers,
		"source_city_plan": source_city_plan.canonical_state() if source_city_plan != null else {},
	}


func restore_state(data: Dictionary) -> bool:
	if int(data.get("team", team)) != team or String(data.get("profile", profile)) != profile:
		return false
	last_economic_tick = int(data.get("last_economic_tick", -1))
	last_military_tick = int(data.get("last_military_tick", -1))
	last_attack_tick = int(data.get("last_attack_tick", -1))
	last_response_tick = int(data.get("last_response_tick", -1))
	last_tribute_tick = int(data.get("last_tribute_tick", -1))
	decision_index = int(data.get("decision_index", 0))
	next_source_attack_group_id = maxi(1, int(data.get("next_source_attack_group_id", 1)))
	next_source_assignment_group_id = maxi(1, int(data.get("next_source_assignment_group_id", 1)))
	var restored_city_plan = SourceCityPlan.from_state(data.get("source_city_plan", {}))
	if int(restored_city_plan.team) == team:
		source_city_plan = restored_city_plan
	source_attack_groups.clear()
	for group_value in data.get("source_attack_groups", []):
		var group = SourceAttackGroup.from_state(group_value)
		if int(group.group_id) <= 0 or int(group.team) != team:
			continue
		source_attack_groups[int(group.group_id)] = group
		next_source_attack_group_id = maxi(next_source_attack_group_id, int(group.group_id) + 1)
	source_assignment_groups.clear()
	for group_value in data.get("source_assignment_groups", []):
		var group = SourceAssignmentGroup.from_state(group_value)
		if int(group.group_id) <= 0 or int(group.team) != team:
			continue
		source_assignment_groups[int(group.group_id)] = group
		next_source_assignment_group_id = maxi(next_source_assignment_group_id, int(group.group_id) + 1)
	failed_gather_targets.clear()
	for entry_value in data.get("failed_gather_targets", []):
		var entry: Dictionary = entry_value
		var worker_id := int(entry.get("worker_id", -1))
		if worker_id < 0:
			continue
		var failed: Dictionary = {}
		for resource_id in entry.get("resource_ids", []):
			failed[int(resource_id)] = true
		failed_gather_targets[worker_id] = failed
	return true


func _prune_completed_source_groups() -> void:
	var completed: Array[int] = []
	for group_id_value in source_attack_groups.keys():
		if String(source_attack_groups[group_id_value].state) == SourceAttackGroup.COMPLETE:
			completed.append(int(group_id_value))
	completed.sort()
	while completed.size() > 64:
		source_attack_groups.erase(completed.pop_front())


func _has_active_source_attack_group() -> bool:
	for group_value in source_attack_groups.values():
		if String(group_value.state) in [SourceAttackGroup.ATTACKING, SourceAttackGroup.EXTERMINATING]:
			return true
	return false


func _prune_completed_assignment_groups() -> void:
	var completed: Array[int] = []
	for group_id_value in source_assignment_groups.keys():
		if String(source_assignment_groups[group_id_value].state) == SourceAssignmentGroup.COMPLETE:
			completed.append(int(group_id_value))
	completed.sort()
	while completed.size() > 64:
		source_assignment_groups.erase(completed.pop_front())
