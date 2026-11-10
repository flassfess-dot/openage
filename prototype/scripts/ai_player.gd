class_name RoRAiPlayer
extends RefCounted

static func configure_runtime_cadence(players: Array) -> void:
	for ai in players:
		if String(ai.profile) != "source_campaign_v1": continue
		if int(ai.economic_interval) >= 20: ai.economic_interval = maxi(int(ai.economic_interval), 40)
		if int(ai.military_interval) >= 20: ai.military_interval = maxi(int(ai.military_interval), 40)

const NavigationPolicy := preload("res://scripts/ai_navigation_policy.gd")
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
const StrategyState := preload("res://scripts/ai_strategy_state.gd")
const AdaptiveEconomy := preload("res://scripts/ai_adaptive_economy.gd")
const PlanBudget := preload("res://scripts/ai_plan_budget.gd")
const Operations := preload("res://scripts/ai_operations.gd")
const CompetitiveController := preload("res://scripts/ai_competitive_controller.gd")

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
var navigation_policy := NavigationPolicy.new()
var strategy := StrategyState.new()
var operations := Operations.new()
var failed_gather_expiry: Dictionary = {}
var failed_gather_seen: Dictionary = {}
var last_gather_topology: Variant = null
var planning_metrics: Dictionary = {}
var economic_resource_index: Variant = null
var competitive_controller: Variant = null


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
	# Keep policy extensions in captured definitions; normalized legacy fields win.
	var normalized := economic_policy
	economic_policy = settings.duplicate(true)
	economic_policy.merge(normalized, true)
	economic_policy["competitive"] = String(settings.get("algorithm_version","legacy_adaptive_v1")) == "competitive_v2" and profile != "source_campaign_v1"
	if bool(economic_policy["competitive"]):
		economic_policy.merge(settings.get("competitive_parameters",{}),false)
		economic_policy["capabilities"]=["legal_observation","adaptive_economy","operations","belief_regions","income_ledger","strategic_plans","combat_rollouts","role_micro","action_budget","farm_reserve","garrison","team_intents"]
		competitive_controller = CompetitiveController.new()
		military_interval = 4
		economic_interval = 20
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
	var navigation_reserved := navigation_policy.reserved_units(snapshot, next_tick)
	var result: Array = navigation_policy.recovery_commands(snapshot, next_tick, navigation_reserved)
	if profile == "source_campaign_v1":
		var recovery_count := result.size()
		var economic_reserved: Dictionary = navigation_reserved.duplicate()
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
		var filtered: Array = result.slice(0, recovery_count)
		for command in result.slice(recovery_count):
			if command.unit_ids.is_empty():
				filtered.append(command)
				continue
			var ids: Array[int] = []
			for id in command.unit_ids:
				if not navigation_reserved.has(int(id)): ids.append(int(id))
			if not ids.is_empty():
				command.unit_ids = ids
				filtered.append(command)
		return filtered
	if bool(economic_policy.get("adaptive_strategy", false)):
		result.append_array(_collect_adaptive(snapshot, next_tick, navigation_reserved))
		if competitive_controller != null:
			var admission_started := Time.get_ticks_usec()
			var eligible: Array=[]
			for command in result:
				if not command.params.has("_ai_feedback"):
					command.params["_ai_feedback"]={"key":"competitive:"+String(command.command_type())+":"+str(command.unit_ids)+":"+str(command.params),"cost":{}}
				if not strategy.cooldowns.has(String(command.params["_ai_feedback"].get("key",""))): eligible.append(command)
			result=eligible
			result=competitive_controller.actions.admit(result,next_tick,economic_policy,strategy,operations)
			competitive_controller.micro.record_sent(result,next_tick)
			planning_metrics["admission"]=Time.get_ticks_usec()-admission_started
		return result
	var skirmish_reserved_ids: Dictionary = navigation_reserved
	if last_economic_tick < 0 or next_tick - last_economic_tick >= economic_interval:
		_remember_failed_gather_targets(snapshot)
		var support_snapshot := snapshot.duplicate()
		support_snapshot["units"] = snapshot.get("units", []).filter(func(unit): return not skirmish_reserved_ids.has(int(unit.get("id", -1))))
		var support_commands: Array = SupportPlanner.plan(support_snapshot, next_tick, team)
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


func _collect_adaptive(snapshot: Dictionary, next_tick: int, reserved: Dictionary) -> Array:
	if competitive_controller != null:
		return competitive_controller.plan(self,snapshot,next_tick,reserved)
	var started := Time.get_ticks_usec()
	strategy.observe(snapshot, team, economic_policy)
	var goal: Dictionary = strategy.choose_goal(snapshot, team, economic_policy, decision_index)
	planning_metrics["strategy"] = Time.get_ticks_usec() - started
	decision_index += 1
	var owned := AdaptiveEconomy.own(snapshot.get("buildings", []), team)
	var budget := PlanBudget.new(snapshot.get("player_state", {}), owned)
	var result: Array = []
	if last_economic_tick < 0 or next_tick - last_economic_tick >= economic_interval:
		started = Time.get_ticks_usec()
		_expire_failed_gathers(snapshot)
		_remember_failed_gather_targets(snapshot)
		planning_metrics["failures"] = Time.get_ticks_usec() - started
		var policy := economic_policy.duplicate()
		policy["failed_gather_targets"] = failed_gather_targets
		result.append_array(AdaptiveEconomy.plan(snapshot, next_tick, team, policy, strategy, budget, reserved, planning_metrics, economic_resource_index))
		started = Time.get_ticks_usec()
		var support_snapshot := snapshot.duplicate()
		support_snapshot["units"] = snapshot.get("units", []).filter(func(u): return not reserved.has(int(u.get("id", -1))))
		# Repair costs are charged over time. Keep a wood reserve before assigning
		# repair work; authoritative simulation still charges every repair step.
		var support: Array = SupportPlanner.plan(support_snapshot, next_tick, team, economic_policy, strategy)
		for command in support:
			if String(command.command_type()) == "repair" and int(budget.remaining.get(1, 0)) < int(economic_policy.get("repair_wood_reserve", 60)): continue
			result.append(command)
			for id in command.unit_ids: reserved[int(id)] = true
		var previous_tribute_tick := last_tribute_tick
		var tribute: Variant = _plan_tribute(snapshot, next_tick)
		if tribute != null:
			var cost := {int(tribute.params.get("resource_type_id", -1)): int(tribute.params.get("amount", 0))}
			if budget.reserve(cost):
				tribute.params["_ai_feedback"] = {"key": "tribute", "cost": cost}
				result.append(tribute)
			else: last_tribute_tick = previous_tribute_tick
		last_economic_tick = next_tick
		planning_metrics["support"] = Time.get_ticks_usec() - started
	if last_military_tick < 0 or next_tick - last_military_tick >= military_interval:
		started = Time.get_ticks_usec()
		var responding := String(goal.get("type", "")) == "defend"
		var attack_allowed := responding or (next_tick >= initial_attack_delay and (last_attack_tick < 0 or next_tick - last_attack_tick >= attack_separation))
		goal["landing_threats"] = strategy.enemies(int(snapshot.get("tick", 0)), economic_policy)
		goal["expeditions"] = strategy.expeditions
		goal["minimum_landing_group"] = minimum_attack_group_size
		goal["minimum_naval_escort"] = int(economic_policy.get("minimum_naval_escort", 2))
		goal["landing_danger_limit"] = float(economic_policy.get("landing_danger_limit", 12.0))
		if attack_allowed:
			var transport: Array = TransportPlanner.plan(snapshot, next_tick, team, goal, formation_name, reserved)
			result.append_array(transport)
			for command in transport:
				for id in command.unit_ids: reserved[int(id)] = true
		for unit in snapshot.get("units", []):
			if int(unit.get("team", 0)) == team and String(unit.get("task", "")) == "board": reserved[int(unit["id"])] = true
		var policy := economic_policy.duplicate()
		policy["minimum_attack_group_size"] = minimum_attack_group_size
		policy["maximum_attack_group_size"] = maximum_attack_group_size
		var military: Array = operations.plan(snapshot, next_tick, team, goal, policy, strategy, reserved, formation_name, attack_allowed)
		result.append_array(military)
		if military.any(func(c): return String(c.command_type()) == "attack_move") and last_attack_tick < 0: last_attack_tick = next_tick
		last_military_tick = next_tick
		planning_metrics["military"] = Time.get_ticks_usec() - started
	return result


func collect_feedback(controller, tick: int) -> void:
	if bool(economic_policy.get("adaptive_strategy", false)):
		strategy.feedback(controller, team, tick, economic_policy)


func register_proposal(command, metadata: Dictionary = {}) -> void:
	if bool(economic_policy.get("adaptive_strategy", false)):
		strategy.register(command, metadata if not metadata.is_empty() else {"key": String(command.command_type()) + ":" + str(command.unit_ids), "cost": {}})


func _expire_failed_gathers(snapshot: Dictionary) -> void:
	var tick := int(snapshot.get("tick", 0))
	var alive: Dictionary = {}
	for unit in snapshot.get("units", []):
		if int(unit.get("team", 0)) != team: continue
		alive[int(unit["id"])] = true
		for id in unit.get("components", {}).get("cargo", {}).get("passenger_ids", []): alive[int(id)] = true
	for worker in failed_gather_seen.keys():
		if not alive.has(int(worker)):
			failed_gather_seen.erase(worker)
			failed_gather_expiry.erase(worker)
			failed_gather_targets.erase(worker)
	# Keep the legacy field when restoring a pending decision. New decisions
	# compare the access to each failed target in _remember_failed_gather_targets.
	last_gather_topology = null
	for worker in failed_gather_expiry.keys():
		for resource in failed_gather_expiry[worker].keys():
			if tick >= int(failed_gather_expiry[worker][resource]):
				failed_gather_expiry[worker].erase(resource)
				if failed_gather_targets.has(worker): failed_gather_targets[worker].erase(resource)
		if failed_gather_expiry[worker].is_empty(): failed_gather_expiry.erase(worker)


func _remember_failed_gather_targets(snapshot: Dictionary) -> void:
	var adaptive := bool(economic_policy.get("adaptive_strategy", false))
	var own_units: Dictionary = {}
	var assignments: Dictionary = {}
	var completed: Array = []
	for unit in snapshot.get("units", []):
		if int(unit.get("team", 0)) != team or float(unit.get("hp", 0.0)) <= 0.0: continue
		own_units[int(unit["id"])] = unit
		if String(unit.get("task", "")) == "gather":
			var active_id := int(unit.get("resource_id", -1))
			assignments[active_id] = int(assignments.get(active_id, 0)) + 1
		var order: Dictionary = unit.get("components", {}).get("order", {})
		if String(order.get("type", "")) == "gather" and bool(order.get("completed", false)) and String(order.get("completion_reason", "")) in ["no_approach_slot", "no_path", "local_blocked", "local_obstacle"]:
			completed.append(unit)
	if completed.is_empty() and failed_gather_targets.is_empty(): return

	var available: Dictionary = {}
	for resource in snapshot.get("resources", []):
		if int(resource.get("amount", 0)) > 0: available[int(resource["id"])] = resource
	if adaptive:
		for building in snapshot.get("buildings", []):
			if int(building.get("team", 0)) == team and bool(building.get("harvestable", false)) and int(building.get("amount", 0)) > 0:
				available[int(building["id"])] = building
	var navigation: Dictionary = snapshot.get("navigation", {})
	var reachable: Dictionary = {}
	if adaptive:
		reachable = snapshot["_economy_reachable_cells"] if snapshot.has("_economy_reachable_cells") else EconomicPlanner._reachable_cells_by_domain(navigation)
	var regions: Dictionary = navigation.get("unit_regions", {})
	for worker_id in failed_gather_targets.keys():
		if not own_units.has(worker_id):
			failed_gather_targets.erase(worker_id)
			failed_gather_expiry.erase(worker_id)
			failed_gather_seen.erase(worker_id)
			continue
		var failures: Dictionary = failed_gather_targets[worker_id]
		var expiry: Dictionary = failed_gather_expiry.get(worker_id, {})
		for target_id in failures.keys():
			if not available.has(target_id):
				failures.erase(target_id)
				expiry.erase(target_id)
			elif adaptive:
				var access := _gather_access(own_units[worker_id], available[target_id], reachable, regions, assignments)
				if failures[target_id] is Array and failures[target_id] != access:
					failures.erase(target_id)
					expiry.erase(target_id)
				else:
					# Legacy saves retained the failure and expiry without a local observation.
					failures[target_id] = access
		if failures.is_empty(): failed_gather_targets.erase(worker_id)
		if expiry.is_empty(): failed_gather_expiry.erase(worker_id)
	for unit in completed:
		var order: Dictionary = unit["components"]["order"]
		var target_id := int(order.get("target_entity_id", -1))
		if target_id < 0 or not available.has(target_id): continue
		var worker_id := int(unit.get("id", -1))
		var failures: Dictionary = failed_gather_targets.get(worker_id, {})
		if adaptive:
			var expiry: Dictionary = failed_gather_expiry.get(worker_id, {})
			# A failed slot search may never issue a path request. A new order
			# still has a fresh revision, whereas a retained completed order does not.
			var legacy := [target_id, int(unit.get("path_request_id", 0))]
			var token := legacy.duplicate()
			if order.has("revision"): token.append(int(order["revision"]))
			var seen: Array = failed_gather_seen.get(worker_id, [])
			if seen == token: continue
			failed_gather_seen[worker_id] = token
			if seen == legacy: continue
			expiry[target_id] = int(snapshot.get("tick", 0)) + int(economic_policy.get("gather_retry_ticks", 200))
			failed_gather_expiry[worker_id] = expiry
			failures[target_id] = _gather_access(unit, available[target_id], reachable, regions, assignments)
		else:
			failures[target_id] = true
		failed_gather_targets[worker_id] = failures


static func _gather_access(unit: Dictionary, resource: Dictionary, reachable: Dictionary, regions: Dictionary, assignments: Dictionary) -> Array:
	var domain := String(unit.get("movement_domain", "land"))
	var cell := Vector2i(Vector2(resource.get("pos", Vector2.ZERO)))
	var mask := -1
	if reachable.has(domain):
		var cells: Dictionary = reachable[domain]
		mask = 0
		for y in range(-2, 3):
			for x in range(-2, 3):
				mask = (mask << 1) | int(cells.has(cell + Vector2i(x, y)))
	var origin: Variant = regions.get(int(unit["id"]), Vector2i(Vector2(unit.get("pos", Vector2.ZERO))))
	return [domain, origin, cell, mask, int(assignments.get(int(resource["id"]), 0))]


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


func decision_options(target_tick: int) -> Dictionary:
	var options := presentation_options()
	if competitive_controller != null and last_economic_tick >= 0 and target_tick-last_economic_tick < economic_interval:
		options["tactical_only"] = true
		options["include_navigation"] = target_tick-int(competitive_controller.last_operation_tick)>=10
		options["requested_build_site_kinds"] = []
		options["planning_technology_ids"] = []
		options["include_worker_command_options"] = false
	return options

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
			"build_site_filter": Callable(self, "_source_construction_site_kinds"),
			"maximum_build_sites_per_kind": maximum_build_sites_per_kind,
			"build_site_search_radius": source_city_plan.recommended_search_radius() if source_city_plan != null and source_city_plan.enabled else 12,
			# Exact worker positions, mobile obstructions, exploration, technology
			# and topology invalidate placement results independently of age.
			"build_site_cache_ticks": 1200,
			"minimum_structure_gap": float(economic_policy.get("minimum_structure_gap", 0.0)),
			"preferred_build_sites": preferred_build_sites,
			"strict_preferred_build_site_kinds": strict_preferred_build_site_kinds,
		}
	# collect_commands intentionally routes every non-campaign profile through
	# the skirmish planners. Keep their observation contract equally explicit so
	# imported or future fallback profile names never regress to the expensive
	# presentation defaults.
	var known_positions: Dictionary = {}
	if bool(economic_policy.get("adaptive_strategy", false)):
		for id in strategy.memory: known_positions[int(id)] = strategy.memory[id]["entity"].get("pos", Vector2.ZERO)
		for record in strategy.belief_regions.values():
			var actor: Dictionary=record["entry"]["entity"]
			known_positions[int(actor.get("id",-1))]=actor.get("pos",Vector2.ZERO)
	var skirmish_preferred_sites: Dictionary = {}
	if competitive_controller != null and strategy.goal.has("expansion_position"):
		skirmish_preferred_sites["town_center"] = [Vector2(strategy.goal["expansion_position"])]
	var requested_kinds: Array=economic_policy.get("construction_priorities", []).duplicate()
	if competitive_controller != null:
		for kind in ["tower","gate","wall","wonder"]:
			if kind not in requested_kinds: requested_kinds.append(kind)
		var home:=Vector2(strategy.goal.get("home",Vector2.ZERO)); var target:=Vector2(strategy.goal.get("position",home))
		var forward:=(target-home).normalized()
		if forward.length_squared()>0.5:
			var choke:=home+forward*7.0
			skirmish_preferred_sites["tower"]=[choke-forward*2.0]
			skirmish_preferred_sites["gate"]=[choke]
			# Short flanks leave the gate axis and both external ends open. The
			# regular placement validator still checks slopes and approach slots.
			skirmish_preferred_sites["wall"]=[choke+forward.orthogonal()*3.0,choke-forward.orthogonal()*3.0]
	var skirmish_options := {
		"ai_memory_positions": known_positions,
		"include_ai_projectiles": competitive_controller != null,
		"compact_entities": true,
		"include_navigation": true,
		"include_build_sites": false,
		"include_fog_cells": false,
		"include_projectiles": false,
		"include_scenario": false,
		"include_worker_command_options": false,
		"requested_build_site_kinds": requested_kinds,
		"build_site_filter": Callable(self, "_construction_site_kinds"),
		"build_site_filter_navigation": true,
		"build_site_candidate_filter": Callable() if bool(economic_policy.get("adaptive_strategy", false)) else Callable(self, "_has_usable_build_site"),
		"build_site_cache_ticks": 1200,
		"economic_production_options_only": true,
		"include_ai_profiles": bool(economic_policy.get("adaptive_strategy", false)),
		"build_site_filter_snapshot": bool(economic_policy.get("adaptive_strategy", false)),
		"recover_abandoned_foundations_only": true,
		"planning_technology_ids": economic_policy.get("age_advance_technology_ids", []).duplicate(),
		"maximum_build_sites_per_kind": 12,
		"preferred_build_sites": skirmish_preferred_sites,
		"build_site_search_radius": 12,
		"minimum_structure_gap": float(economic_policy.get("minimum_structure_gap", 0.0)),
	}
	if competitive_controller!=null: skirmish_options["include_builder_productivity"]=true
	return skirmish_options


func _source_construction_site_kinds(kinds: Array, units: Array, buildings: Array, player_state: Dictionary) -> Array:
	return SourceCampaignPlanner.construction_site_kinds(kinds, units, buildings, player_state, team, source_contract)


func _construction_site_kinds(kinds: Array, units: Array, buildings: Array, player_state: Dictionary, navigation: Dictionary = {}, snapshot: Dictionary = {}) -> Array:
	if bool(economic_policy.get("adaptive_strategy", false)):
		var facts := snapshot.duplicate()
		facts.merge({"units": units, "buildings": buildings, "player_state": player_state, "navigation": navigation}, true)
		return AdaptiveEconomy.site_kinds(kinds, facts, team, economic_policy, strategy)
	return EconomicPlanner.construction_site_kinds(kinds, units, buildings, player_state, team, economic_policy, navigation)


func _has_usable_build_site(kind: String, sites: Array, units: Array, buildings: Array) -> bool:
	return EconomicPlanner.has_usable_build_site(kind, sites, units, buildings, team, economic_policy)


static func initial_decision_tick(player, players: Array) -> int:
	var cadence := maxi(1, mini(int(player.economic_interval), int(player.military_interval)))
	var peers: Array = players.filter(func(peer): return bool(peer.enabled) and maxi(1, mini(int(peer.economic_interval), int(peer.military_interval))) == cadence)
	peers.sort_custom(func(left, right): return int(left.team) < int(right.team))
	if peers.is_empty():
		return 1 + posmod(int(player.team) - 1, cadence)
	var rank := peers.find(player)
	var anchor := posmod(int(peers[0].team) - 1, cadence)
	# Equal intervals remain unchanged; only their stable initial phases differ.
	return 1 + posmod(anchor + floori(float(maxi(0, rank) * cadence) / float(peers.size())), cadence)


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
		var record := {"worker_id": int(worker_id), "resource_ids": resource_ids}
		var access: Dictionary = {}
		for id in resource_ids:
			if failed_gather_targets[worker_id][id] is Array: access[id] = failed_gather_targets[worker_id][id].duplicate()
		if not access.is_empty(): record["access"] = access
		failed_gathers.append(record)
	var result := {
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
		"navigation_failures": navigation_policy.canonical_state(),
		"adaptive_strategy": strategy.canonical_state(),
		"adaptive_operations": operations.canonical_state(),
		"failed_gather_expiry": failed_gather_expiry.duplicate(true),
		"last_gather_topology": last_gather_topology,
		"failed_gather_seen": failed_gather_seen.duplicate(true),
		"source_city_plan": source_city_plan.canonical_state() if source_city_plan != null else {},
	}
	if competitive_controller != null: result["competitive_controller"] = competitive_controller.canonical_state()
	return result


func restore_state(data: Dictionary) -> bool:
	if competitive_controller != null:
		if not data.get("adaptive_strategy") is Dictionary or not data.get("adaptive_operations") is Dictionary: return false
		if not data.get("competitive_controller") is Dictionary or not competitive_controller.restore_state(data["competitive_controller"]): return false
	if data.has("adaptive_strategy") and not strategy.restore_state(data["adaptive_strategy"]): return false
	if data.has("adaptive_operations") and not operations.restore_state(data["adaptive_operations"], team): return false
	failed_gather_expiry = data.get("failed_gather_expiry", {}).duplicate(true)
	last_gather_topology = data.get("last_gather_topology")
	failed_gather_seen = data.get("failed_gather_seen", {}).duplicate(true)
	if not navigation_policy.restore_state(data.get("navigation_failures", [])):
		return false
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
			var access: Variant = entry.get("access", {}).get(int(resource_id))
			failed[int(resource_id)] = access.duplicate() if access is Array else true
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
