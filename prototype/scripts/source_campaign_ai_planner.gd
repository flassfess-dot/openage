class_name RoRSourceCampaignAiPlanner
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const AttackGroup := preload("res://scripts/source_ai_attack_group.gd")
const AssignmentGroup := preload("res://scripts/source_ai_assignment_group.gd")
const TICKS_PER_SECOND := 20
const ESCORT_FOLLOW_DISTANCE := 3.0
const ESCORT_THREAT_DISTANCE := 6.0


static func plan_economy(snapshot: Dictionary, tick: int, team: int, contract: Dictionary, city_plan = null) -> Array:
	if int(snapshot.get("observer_team", -1)) != team:
		return []
	var own_units: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0
	)
	var own_buildings: Array = snapshot.get("buildings", []).filter(func(entity):
		return int(entity.get("team", 0)) == team and float(entity.get("hp", 0.0)) > 0.0
	)
	var result: Array = []
	var committed_workers: Dictionary = {}
	var numbers := strategic_number_values(contract)
	if city_plan != null:
		city_plan.synchronize(snapshot, own_units, own_buildings, numbers)
	var housing_command: Variant = _housing_command(snapshot, tick, own_units, city_plan)
	if housing_command != null:
		result.append(housing_command)
		for worker_id in housing_command.unit_ids:
			committed_workers[int(worker_id)] = true
	else:
		var build_command: Variant = _next_build_order_command(snapshot, tick, team, contract, own_units, own_buildings, numbers, city_plan)
		if build_command != null:
			result.append(build_command)
			for worker_id in build_command.unit_ids:
				committed_workers[int(worker_id)] = true
	result.append_array(_idle_worker_commands(snapshot, tick, own_units, committed_workers))
	return result


static func plan_assignment_group_lifecycle(snapshot: Dictionary, tick: int, team: int, groups: Dictionary) -> Dictionary:
	var result := {"commands": [], "excluded_unit_ids": {}, "completed_group_ids": []}
	if int(snapshot.get("observer_team", -1)) != team:
		return result
	var units_by_id: Dictionary = {}
	for unit_value in snapshot.get("units", []):
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == team:
			units_by_id[int(unit.get("id", -1))] = unit
	var anchors_by_id: Dictionary = {}
	for unit_id in units_by_id:
		anchors_by_id[int(unit_id)] = units_by_id[unit_id]
	for category in ["buildings", "resources", "objectives"]:
		for entity_value in snapshot.get(category, []):
			var entity: Dictionary = entity_value
			anchors_by_id[int(entity.get("id", -1))] = entity
	var group_ids: Array = groups.keys()
	group_ids.sort()
	for group_id_value in group_ids:
		var group = groups[group_id_value]
		if int(group.team) != team:
			continue
		group.sync_members(units_by_id, tick)
		if String(group.state) == AssignmentGroup.COMPLETE:
			result["completed_group_ids"].append(int(group.group_id))
			continue
		var commands: Array = []
		if String(group.role) == AssignmentGroup.DEFEND:
			commands = _update_defend_group(snapshot, tick, team, group, units_by_id, anchors_by_id)
		elif String(group.role) == AssignmentGroup.ESCORT:
			commands = _update_escort_group(snapshot, tick, team, group, units_by_id, anchors_by_id)
		else:
			commands = _update_explore_group(snapshot, tick, group, units_by_id)
		result["commands"].append_array(commands)
		if String(group.state) == AssignmentGroup.COMPLETE:
			result["completed_group_ids"].append(int(group.group_id))
		else:
			for entity_id in group.member_ids:
				result["excluded_unit_ids"][entity_id] = true
	return result


static func plan_strategic_assignments(snapshot: Dictionary, tick: int, team: int, contract: Dictionary, groups: Dictionary, excluded_unit_ids: Dictionary = {}, next_group_id: int = 1, formation_name: String = "RECTANGLE") -> Dictionary:
	var result := {"commands": [], "groups": [], "unit_ids": [], "issued": false}
	if int(snapshot.get("observer_team", -1)) != team:
		return result
	var numbers: Dictionary = strategic_number_values(contract)
	var reserved: Dictionary = excluded_unit_ids.duplicate()
	var active_land_defend := 0
	var active_water_defend := 0
	var active_land_explore := 0
	var active_water_explore := 0
	var active_civilian_explore := 0
	var active_escort_members := {
		"trade": 0,
		"fish": 0,
		"transport": 0,
	}
	var occupied_anchor_ids: Dictionary = {}
	for group_value in groups.values():
		var existing = group_value
		if int(existing.team) != team or String(existing.state) == AssignmentGroup.COMPLETE:
			continue
		for entity_id in existing.member_ids:
			reserved[entity_id] = true
		if String(existing.role) == AssignmentGroup.DEFEND:
			if String(existing.movement_domain) == "water":
				active_water_defend += 1
			else:
				active_land_defend += 1
			if int(existing.anchor_id) >= 0:
				occupied_anchor_ids[int(existing.anchor_id)] = true
		elif String(existing.role) == AssignmentGroup.ESCORT:
			var escort_kind := String(existing.anchor_kind).trim_prefix("escort_")
			active_escort_members[escort_kind] = int(active_escort_members.get(escort_kind, 0)) + existing.member_ids.size()
			if int(existing.anchor_id) >= 0:
				occupied_anchor_ids[int(existing.anchor_id)] = true
		else:
			if String(existing.movement_domain) == "water":
				active_water_explore += 1
			else:
				active_land_explore += 1
			if String(existing.anchor_kind) == "civilian" and String(existing.movement_domain) == "land":
				active_civilian_explore += 1

	var created: Array = []
	var defend_count := maxi(0, int(numbers.get(38, 0)))
	var defend_slots := maxi(0, defend_count - active_land_defend)
	if defend_slots > 0:
		var defend_minimum := maxi(1, int(numbers.get(25, 0)))
		var defend_maximum := maxi(defend_minimum, int(numbers.get(28, defend_minimum)))
		var defenders := _idle_land_combatants(snapshot, team, reserved)
		var anchors := _defence_anchors(snapshot, team, numbers, occupied_anchor_ids, defend_slots)
		var allocations := _partition_defend_groups(defenders, anchors, defend_minimum, defend_maximum, defend_slots, clampi(int(numbers.get(40, 0)), 0, 1))
		for allocation_value in allocations:
			var allocation: Dictionary = allocation_value
			var members: Array = allocation.get("members", [])
			var anchor: Dictionary = allocation.get("anchor", {})
			var group = AssignmentGroup.new(next_group_id + created.size(), team, AssignmentGroup.DEFEND, members, Vector2(anchor.get("position", Vector2.ZERO)), tick)
			_configure_group_commander(group, members, numbers)
			group.anchor_id = int(anchor.get("id", -1))
			group.anchor_kind = String(anchor.get("kind", ""))
			group.priority = int(anchor.get("priority", 0))
			group.defence_distance = maxf(0.0, float(anchor.get("defence_distance", 0.0)))
			group.influence_radius = maxf(0.0, float(numbers.get(92, 0)))
			group.formation_name = formation_name
			var ids: Array[int] = group.member_ids.duplicate()
			if _entity_center(members).distance_to(group.anchor_position) <= maxf(0.75, group.defence_distance):
				group.state = AssignmentGroup.ACTIVE
				group.last_transition_reason = "created_at_defence_anchor"
			else:
				result["commands"].append(Commands.FormationMoveCommand.new(tick, ids, group.anchor_position, formation_name))
			created.append(group)
			for entity_id in ids:
				reserved[entity_id] = true
				result["unit_ids"].append(entity_id)

	var boat_defend_count := maxi(0, int(numbers.get(67, 0)))
	var boat_defend_slots := maxi(0, boat_defend_count - active_water_defend)
	if boat_defend_slots > 0 and int(numbers.get(70, 0)) > 0:
		var boat_defend_minimum := maxi(1, int(numbers.get(68, 0)))
		var boat_defend_maximum := maxi(boat_defend_minimum, int(numbers.get(69, boat_defend_minimum)))
		var boat_defenders := _idle_domain_combatants(snapshot, team, reserved, "water")
		var dock_anchors := _dock_defence_anchors(snapshot, team, numbers, occupied_anchor_ids)
		var boat_allocations := _partition_defend_groups(boat_defenders, dock_anchors, boat_defend_minimum, boat_defend_maximum, boat_defend_slots, clampi(int(numbers.get(40, 0)), 0, 1))
		for allocation_value in boat_allocations:
			var allocation: Dictionary = allocation_value
			var members: Array = allocation.get("members", [])
			var anchor: Dictionary = allocation.get("anchor", {})
			var group = AssignmentGroup.new(next_group_id + created.size(), team, AssignmentGroup.DEFEND, members, Vector2(anchor.get("position", Vector2.ZERO)), tick)
			_configure_group_commander(group, members, numbers)
			group.anchor_id = int(anchor.get("id", -1))
			group.anchor_kind = "dock"
			group.movement_domain = "water"
			group.priority = int(anchor.get("priority", 1))
			group.defence_distance = maxf(0.0, float(anchor.get("defence_distance", 0.0)))
			group.influence_radius = maxf(0.0, float(numbers.get(92, 0)))
			group.formation_name = formation_name
			var ids: Array[int] = group.member_ids.duplicate()
			if _entity_center(members).distance_to(group.anchor_position) <= maxf(0.75, group.defence_distance):
				group.state = AssignmentGroup.ACTIVE
				group.last_transition_reason = "created_at_dock_anchor"
			else:
				result["commands"].append(Commands.FormationMoveCommand.new(tick, ids, group.anchor_position, formation_name))
			created.append(group)
			for entity_id in ids:
				reserved[entity_id] = true
				result["unit_ids"].append(entity_id)

	for escort_spec in [
		{"source_id": 64, "kind": "trade"},
		{"source_id": 65, "kind": "fish"},
		{"source_id": 66, "kind": "transport"},
	]:
		var escort_kind := String(escort_spec.get("kind", ""))
		var desired_members := maxi(0, int(numbers.get(int(escort_spec.get("source_id", -1)), 0)))
		var missing_members := maxi(0, desired_members - int(active_escort_members.get(escort_kind, 0)))
		if missing_members <= 0:
			continue
		var escort_candidates := _idle_domain_combatants(snapshot, team, reserved, "water")
		var escort_anchors := _escort_anchors(snapshot, team, escort_kind, occupied_anchor_ids)
		var escort_allocations := _partition_escort_groups(escort_candidates, escort_anchors, missing_members)
		for allocation_value in escort_allocations:
			var allocation: Dictionary = allocation_value
			var members: Array = allocation.get("members", [])
			var anchor: Dictionary = allocation.get("anchor", {})
			var group = AssignmentGroup.new(next_group_id + created.size(), team, AssignmentGroup.ESCORT, members, Vector2(anchor.get("pos", Vector2.ZERO)), tick)
			_configure_group_commander(group, members, numbers)
			group.anchor_id = int(anchor.get("id", -1))
			group.anchor_kind = "escort_%s" % escort_kind
			group.movement_domain = "water"
			group.defence_distance = ESCORT_THREAT_DISTANCE
			group.influence_radius = ESCORT_FOLLOW_DISTANCE
			group.formation_name = formation_name
			var ids: Array[int] = group.member_ids.duplicate()
			if _entity_center(members).distance_to(group.anchor_position) <= ESCORT_FOLLOW_DISTANCE:
				group.state = AssignmentGroup.ACTIVE
				group.last_transition_reason = "created_near_escort_anchor"
			else:
				result["commands"].append(Commands.AttackMoveCommand.new(tick, ids, group.anchor_position))
			created.append(group)
			occupied_anchor_ids[int(group.anchor_id)] = true
			for entity_id in ids:
				reserved[entity_id] = true
				result["unit_ids"].append(entity_id)

	var total_cap := maxi(0, int(numbers.get(18, 2147483647)))
	var active_explore_total := active_land_explore + active_water_explore
	var remaining_explorer_slots := maxi(0, total_cap - active_explore_total)
	var civilian_target := maxi(0, int(numbers.get(35, 0)))
	var civilian_slots := mini(maxi(0, civilian_target - active_civilian_explore), remaining_explorer_slots)
	if civilian_slots > 0:
		var workers := _idle_land_workers(snapshot, team, reserved)
		for index in range(mini(civilian_slots, workers.size())):
			var worker: Dictionary = workers[index]
			var origin := Vector2(worker.get("pos", Vector2.ZERO))
			var frontier: Variant = _frontier_for_domain(snapshot, "land", origin, 0.25)
			if frontier == null:
				break
			var group = AssignmentGroup.new(next_group_id + created.size(), team, AssignmentGroup.EXPLORE, [worker], origin, tick)
			_configure_group_commander(group, [worker], numbers)
			group.anchor_kind = "civilian"
			group.objective_position = Vector2(frontier)
			group.formation_name = formation_name
			result["commands"].append(Commands.MoveCommand.new(tick, group.member_ids, group.objective_position))
			created.append(group)
			reserved[int(worker.get("id", -1))] = true
			result["unit_ids"].append(int(worker.get("id", -1)))
	remaining_explorer_slots = maxi(0, total_cap - active_explore_total - created.filter(func(group): return String(group.role) == AssignmentGroup.EXPLORE).size())
	var soldier_group_target := maxi(0, int(numbers.get(42, 0)))
	var active_soldier_groups := maxi(0, active_land_explore - active_civilian_explore)
	var soldier_slots := mini(maxi(0, soldier_group_target - active_soldier_groups), remaining_explorer_slots)
	if soldier_slots > 0:
		var explore_minimum := maxi(1, int(numbers.get(43, 0)))
		var explore_maximum := maxi(explore_minimum, int(numbers.get(44, explore_minimum)))
		var explorers := _idle_land_combatants(snapshot, team, reserved)
		var explore_partitions := _partition_attack_groups(explorers, explore_minimum, explore_maximum, soldier_slots, clampi(int(numbers.get(40, 0)), 0, 1))
		for members_value in explore_partitions:
			var members: Array = members_value
			var origin := _entity_center(members)
			var frontier: Variant = _frontier_for_domain(snapshot, "land", origin, 0.25)
			if frontier == null:
				continue
			var group = AssignmentGroup.new(next_group_id + created.size(), team, AssignmentGroup.EXPLORE, members, origin, tick)
			_configure_group_commander(group, members, numbers)
			group.anchor_kind = "soldier_group"
			group.objective_position = Vector2(frontier)
			group.formation_name = formation_name
			result["commands"].append(Commands.AttackMoveCommand.new(tick, group.member_ids, group.objective_position))
			created.append(group)
			for entity_id in group.member_ids:
				reserved[entity_id] = true
				result["unit_ids"].append(entity_id)

	remaining_explorer_slots = maxi(0, total_cap - active_explore_total - created.filter(func(group): return String(group.role) == AssignmentGroup.EXPLORE).size())
	var boat_explore_target := maxi(0, int(numbers.get(61, 0)))
	var boat_explore_slots := mini(maxi(0, boat_explore_target - active_water_explore), remaining_explorer_slots)
	if boat_explore_slots > 0:
		var boat_explore_minimum := maxi(1, int(numbers.get(62, 0)))
		var boat_explore_maximum := maxi(boat_explore_minimum, int(numbers.get(63, boat_explore_minimum)))
		var boat_explorers := _idle_domain_combatants(snapshot, team, reserved, "water")
		var boat_partitions := _partition_attack_groups(boat_explorers, boat_explore_minimum, boat_explore_maximum, boat_explore_slots, clampi(int(numbers.get(40, 0)), 0, 1))
		for members_value in boat_partitions:
			var members: Array = members_value
			var origin := _entity_center(members)
			var frontier: Variant = _frontier_for_domain(snapshot, "water", origin, 0.25)
			if frontier == null:
				continue
			var group = AssignmentGroup.new(next_group_id + created.size(), team, AssignmentGroup.EXPLORE, members, origin, tick)
			_configure_group_commander(group, members, numbers)
			group.anchor_kind = "boat_group"
			group.movement_domain = "water"
			group.objective_position = Vector2(frontier)
			group.formation_name = formation_name
			result["commands"].append(Commands.AttackMoveCommand.new(tick, group.member_ids, group.objective_position))
			created.append(group)
			for entity_id in group.member_ids:
				reserved[entity_id] = true
				result["unit_ids"].append(entity_id)

	result["groups"] = created
	result["issued"] = not created.is_empty()
	return result


static func plan_response(snapshot: Dictionary, tick: int, team: int, contract: Dictionary, last_response_tick: int, excluded_unit_ids: Dictionary = {}) -> Dictionary:
	var empty := {"commands": [], "issued": false, "unit_ids": [], "signal_sequence": -1}
	if int(snapshot.get("observer_team", -1)) != team:
		return empty
	var numbers: Dictionary = strategic_number_values(contract)
	if not numbers.has(19) or not numbers.has(20):
		return empty
	var response_percent := clampi(int(numbers[19]), 0, 100)
	var response_distance := clampf(float(numbers[20]), 0.0, 144.0)
	if response_percent <= 0:
		return empty
	var separation_ticks := maxi(0, int(numbers.get(48, 0))) * TICKS_PER_SECOND
	if last_response_tick >= 0 and tick - last_response_tick < separation_ticks:
		return empty

	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var targets: Dictionary = {}
	for category in ["units", "buildings"]:
		for entity_value in snapshot.get(category, []):
			var entity: Dictionary = entity_value
			targets[int(entity.get("id", -1))] = entity
	var signals: Array = snapshot.get("ai_distress_signals", []).duplicate(true)
	signals.sort_custom(func(left, right):
		var left_sequence := int(left.get("sequence", 0))
		var right_sequence := int(right.get("sequence", 0))
		if left_sequence != right_sequence:
			return left_sequence > right_sequence
		return int(left.get("target_id", -1)) < int(right.get("target_id", -1))
	)
	for distress_value in signals:
		var distress: Dictionary = distress_value
		if int(distress.get("target_team", 0)) != team:
			continue
		var attacker_id := int(distress.get("attacker_id", -1))
		if not targets.has(attacker_id):
			continue
		var target: Dictionary = targets[attacker_id]
		var target_team := int(target.get("team", 0))
		if target_team <= 0 or target_team == team or allies.has(target_team) or float(target.get("hp", 0.0)) <= 0.0:
			continue
		var target_domains: Array = target.get("target_domains", [])
		if target_domains.is_empty():
			target_domains = [String(target.get("movement_domain", "land"))]
		var signal_position := Vector2(distress.get("position", Vector2.ZERO))
		var distressed_id := int(distress.get("target_id", -1))
		var candidates: Array = snapshot.get("units", []).filter(func(entity):
			var domain := String(entity.get("movement_domain", "land"))
			return int(entity.get("team", 0)) == team \
				and not excluded_unit_ids.has(int(entity.get("id", -1))) \
				and int(entity.get("id", -1)) != distressed_id \
				and float(entity.get("hp", 0.0)) > 0.0 \
				and String(entity.get("task", "idle")) == "idle" \
				and not bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) \
				and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) \
				and domain in target_domains \
				and Vector2(entity.get("pos", Vector2.ZERO)).distance_to(signal_position) <= response_distance + 0.0001
		)
		candidates.sort_custom(func(left, right):
			var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(signal_position)
			var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(signal_position)
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return int(left.get("id", -1)) < int(right.get("id", -1))
		)
		var response_count := int(floor(float(candidates.size() * response_percent) / 100.0))
		if response_count <= 0:
			continue
		var ids: Array[int] = []
		for candidate in candidates.slice(0, response_count):
			ids.append(int(candidate.get("id", -1)))
		return {
			"commands": [Commands.AttackCommand.new(tick, ids, attacker_id, {"trigger": "source_distress_response"})],
			"issued": true,
			"unit_ids": ids,
			"signal_sequence": int(distress.get("sequence", -1)),
		}
	return empty


static func plan_attack_group_lifecycle(snapshot: Dictionary, tick: int, team: int, contract: Dictionary, groups: Dictionary) -> Dictionary:
	var result := {"commands": [], "excluded_unit_ids": {}, "completed_group_ids": []}
	if int(snapshot.get("observer_team", -1)) != team:
		return result
	var numbers: Dictionary = strategic_number_values(contract)
	var units_by_id: Dictionary = {}
	for unit_value in snapshot.get("units", []):
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == team:
			units_by_id[int(unit.get("id", -1))] = unit
	var targets_by_id: Dictionary = {}
	for category in ["units", "buildings"]:
		for target_value in snapshot.get(category, []):
			var target: Dictionary = target_value
			targets_by_id[int(target.get("id", -1))] = target
	var group_ids: Array = groups.keys()
	group_ids.sort()
	for group_id_value in group_ids:
		var group = groups[group_id_value]
		if int(group.team) != team:
			continue
		group.sync_members(units_by_id, tick)
		if String(group.state) == AttackGroup.COMPLETE:
			result["completed_group_ids"].append(int(group.group_id))
			continue
		if group.living_ids().is_empty():
			group.transition(AttackGroup.COMPLETE, "no_surviving_members", tick)
			result["completed_group_ids"].append(int(group.group_id))
			continue
		if String(group.state) in [AttackGroup.RETREATING, AttackGroup.RECENTERING]:
			if _group_movement_complete(group, units_by_id):
				group.transition(AttackGroup.COMPLETE, "group_movement_complete", tick)
				result["completed_group_ids"].append(int(group.group_id))
			else:
				_exclude_group_members(group, result["excluded_unit_ids"])
			continue

		var health_retreat := numbers.has(30) and float(group.health_loss_percent) + 0.0001 >= float(clampi(int(numbers[30]), 1, 100))
		var death_retreat := numbers.has(31) and float(group.death_loss_percent) + 0.0001 >= float(clampi(int(numbers[31]), 1, 100))
		if health_retreat or death_retreat:
			var reason := "group_health_threshold" if health_retreat else "group_death_threshold"
			result["commands"].append_array(_begin_group_retreat(group, tick, reason))
			_exclude_group_members(group, result["excluded_unit_ids"])
			continue

		if numbers.has(91):
			var threshold := clampi(int(numbers[91]), 1, 100)
			var individual_retreats: Array[int] = []
			for entity_id in group.active_member_ids.duplicate():
				var member: Variant = units_by_id.get(entity_id)
				if member != null and group.unit_health_loss_percent(entity_id, float(member.get("hp", 0.0))) + 0.0001 >= float(threshold):
					individual_retreats.append(entity_id)
					group.begin_individual_retreat(entity_id)
			if not individual_retreats.is_empty():
				result["commands"].append(Commands.MoveCommand.new(tick, individual_retreats, group.rally_position))
				if group.active_member_ids.is_empty():
					group.transition(AttackGroup.RETREATING, "all_members_individual_retreat", tick)
				_exclude_group_members(group, result["excluded_unit_ids"])
				if String(group.state) == AttackGroup.RETREATING:
					continue

		if String(group.state) == AttackGroup.ASSEMBLING:
			if _group_is_gathered(group, units_by_id):
				group.transition(AttackGroup.READY, "gather_spacing_reached", tick)
			else:
				_exclude_group_members(group, result["excluded_unit_ids"])
				continue
		if String(group.state) == AttackGroup.READY:
			_exclude_group_members(group, result["excluded_unit_ids"])
			continue

		_observe_group_target(group, units_by_id)
		if _group_target_destroyed(group, targets_by_id, units_by_id):
			result["commands"].append_array(_target_destroyed_commands(snapshot, tick, team, group, clampi(int(numbers.get(49, 0)), 0, 3)))
		elif String(group.state) == AttackGroup.EXTERMINATING and _active_members_settled(group, units_by_id):
			result["commands"].append_array(_continue_extermination(snapshot, tick, team, group))
		elif int(group.target_id) < 0 and String(group.state) == AttackGroup.ATTACKING and _active_members_settled(group, units_by_id):
			group.transition(AttackGroup.COMPLETE, "attack_move_objective_reached", tick)
			result["completed_group_ids"].append(int(group.group_id))
		if String(group.state) != AttackGroup.COMPLETE:
			_exclude_group_members(group, result["excluded_unit_ids"])
	result["commands"].append_array(_release_ready_groups(snapshot, tick, team, groups, clampi(int(numbers.get(49, 0)), 0, 3)))
	return result


static func plan_military(snapshot: Dictionary, tick: int, team: int, contract: Dictionary, last_attack_tick: int, wave_index: int, excluded_unit_ids: Dictionary = {}, next_group_id: int = 1, formation_name: String = "RECTANGLE", existing_attack_active: bool = false) -> Dictionary:
	if int(snapshot.get("observer_team", -1)) != team:
		return {"commands": [], "issued": false, "groups": []}
	var numbers: Dictionary = strategic_number_values(contract)
	var initial_tick: int = maxi(0, int(numbers.get(104, 0))) * TICKS_PER_SECOND
	if tick < initial_tick:
		return {"commands": [], "issued": false, "groups": []}
	var separation_ticks: int = maxi(1, int(numbers.get(46, 30))) * TICKS_PER_SECOND
	if last_attack_tick >= 0 and tick - last_attack_tick < separation_ticks:
		return {"commands": [], "issued": false, "groups": []}

	var fighters: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team \
			and not excluded_unit_ids.has(int(entity.get("id", -1))) \
			and float(entity.get("hp", 0.0)) > 0.0 \
			and not bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) \
			and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", [])) \
			and String(entity.get("task", "idle")) in ["idle", "hold"]
	)
	fighters.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))

	var markers: Array = contract.get("target_markers", [])
	var visible_target_by_domain: Dictionary = {}
	if markers.is_empty():
		for fighter_value in fighters:
			var fighter_domain := String(fighter_value.get("movement_domain", "land"))
			if not visible_target_by_domain.has(fighter_domain):
				visible_target_by_domain[fighter_domain] = _compatible_visible_target(snapshot, team, fighter_domain)
		fighters = fighters.filter(func(entity): return not visible_target_by_domain.get(String(entity.get("movement_domain", "land")), {}).is_empty())
	var fill_method := clampi(int(numbers.get(40, 0)), 0, 1)
	var gather_spacing := maxf(1.0, float(numbers.get(41, 1))) if numbers.has(41) else 0.0
	var coordination_mode := clampi(int(numbers.get(47, 0)), 0, 2)
	var commands: Array = []
	var groups_created: Array = []
	var partitions: Array = _source_attack_partitions(fighters, numbers, fill_method)
	for group_index in range(partitions.size()):
		var members: Array = partitions[group_index]
		var domain := String(members[0].get("movement_domain", "land"))
		var ids: Array[int] = []
		for fighter in members:
			ids.append(int(fighter.get("id", -1)))
		var objective := Vector2.ZERO
		var target_entity_id := -1
		var order_type := "attack_move"
		var has_order := false
		if not markers.is_empty():
			var marker: Dictionary = markers[posmod(wave_index + group_index, markers.size())]
			var domain_objective: Variant = _domain_marker_objective(snapshot, marker, domain)
			if domain_objective is Vector2:
				objective = Vector2(domain_objective)
				has_order = true
		else:
			var visible_goal: Dictionary = visible_target_by_domain.get(domain, {})
			if not visible_goal.is_empty():
				target_entity_id = int(visible_goal.get("id", -1))
				objective = Vector2(visible_goal.get("pos", Vector2.ZERO))
				order_type = "attack"
				has_order = true
		if not has_order:
			continue
		var rally := _entity_center(members)
		var group = AttackGroup.new(next_group_id + groups_created.size(), team, members, objective, target_entity_id, rally, domain, formation_name, tick)
		_configure_group_commander(group, members, numbers)
		group.wave_id = wave_index
		group.order_type = order_type
		group.fill_method = fill_method
		group.gather_spacing = gather_spacing
		group.coordination_mode = coordination_mode
		if gather_spacing > 0.0 and not _members_are_gathered(members, rally, gather_spacing):
			group.state = AttackGroup.ASSEMBLING
			group.last_transition_reason = "created_assembling"
			commands.append(Commands.MoveCommand.new(tick, ids, rally))
		else:
			group.state = AttackGroup.READY
			group.last_transition_reason = "created_ready"
		groups_created.append(group)
	var new_groups_by_id: Dictionary = {}
	for group in groups_created:
		new_groups_by_id[int(group.group_id)] = group
	commands.append_array(_release_ready_groups(snapshot, tick, team, new_groups_by_id, clampi(int(numbers.get(49, 0)), 0, 3), existing_attack_active))
	return {"commands": commands, "issued": not groups_created.is_empty(), "groups": groups_created}


static func _source_attack_partitions(fighters: Array, numbers: Dictionary, fill_method: int) -> Array:
	var result: Array = []
	var land_count := maxi(0, int(numbers.get(36, 1)))
	if land_count > 0:
		var land_minimum := maxi(1, int(numbers.get(16, 1)))
		var land_maximum := maxi(land_minimum, int(numbers.get(26, land_minimum)))
		var land_fighters: Array = fighters.filter(func(entity): return String(entity.get("movement_domain", "land")) == "land")
		result.append_array(_partition_attack_groups(land_fighters, land_minimum, land_maximum, land_count, fill_method))
	var boat_count := maxi(0, int(numbers.get(58, 0)))
	if boat_count > 0:
		var boat_minimum := maxi(1, int(numbers.get(59, 0)))
		var boat_maximum := maxi(boat_minimum, int(numbers.get(60, boat_minimum)))
		var boat_fighters: Array = fighters.filter(func(entity): return String(entity.get("movement_domain", "land")) == "water")
		result.append_array(_partition_attack_groups(boat_fighters, boat_minimum, boat_maximum, boat_count, fill_method))
	return result


static func _domain_marker_objective(snapshot: Dictionary, marker: Dictionary, domain: String) -> Variant:
	var source_position := Vector2(marker.get("position", Vector2.ZERO))
	var navigation: Array = snapshot.get("navigation", {}).get(domain, [])
	if navigation.is_empty():
		return source_position
	var best := Vector2(navigation[0])
	var best_distance := best.distance_squared_to(source_position)
	for index in range(1, navigation.size()):
		var candidate := Vector2(navigation[index])
		var distance := candidate.distance_squared_to(source_position)
		if distance < best_distance - 0.0001 or (is_equal_approx(distance, best_distance) and (candidate.y < best.y or (is_equal_approx(candidate.y, best.y) and candidate.x < best.x))):
			best = candidate
			best_distance = distance
	return best


static func _release_ready_groups(snapshot: Dictionary, tick: int, team: int, groups: Dictionary, target_destroyed_policy: int, external_attack_active: bool = false) -> Array:
	var commands: Array = []
	var group_ids: Array = groups.keys()
	group_ids.sort()
	var attack_active := external_attack_active
	for group_id_value in group_ids:
		var existing = groups[group_id_value]
		if String(existing.state) in [AttackGroup.ATTACKING, AttackGroup.EXTERMINATING]:
			attack_active = true
	var released_waves: Dictionary = {}
	for group_id_value in group_ids:
		var group = groups[group_id_value]
		if int(group.team) != team or String(group.state) != AttackGroup.READY:
			continue
		match int(group.coordination_mode):
			0:
				commands.append_array(_launch_group(snapshot, tick, team, group, target_destroyed_policy))
			1:
				if not attack_active:
					commands.append_array(_launch_group(snapshot, tick, team, group, target_destroyed_policy))
					attack_active = String(group.state) in [AttackGroup.ATTACKING, AttackGroup.EXTERMINATING]
			2:
				var wave_id := int(group.wave_id)
				if released_waves.has(wave_id) or not _wave_ready(groups, team, wave_id):
					continue
				released_waves[wave_id] = true
				for wave_group_id in group_ids:
					var wave_group = groups[wave_group_id]
					if int(wave_group.team) == team and int(wave_group.wave_id) == wave_id and String(wave_group.state) == AttackGroup.READY:
						commands.append_array(_launch_group(snapshot, tick, team, wave_group, target_destroyed_policy))
	return commands


static func _launch_group(snapshot: Dictionary, tick: int, team: int, group, target_destroyed_policy: int) -> Array:
	var ids: Array[int] = group.active_member_ids.duplicate()
	if ids.is_empty():
		group.transition(AttackGroup.COMPLETE, "launch_without_members", tick)
		return []
	if String(group.order_type) == "attack":
		var target := _target_with_id(snapshot, int(group.target_id))
		if target.is_empty() or float(target.get("hp", 0.0)) <= 0.0:
			return _target_destroyed_commands(snapshot, tick, team, group, target_destroyed_policy)
		group.target_observed = true
		group.transition(AttackGroup.ATTACKING, "coordination_released", tick)
		return [Commands.AttackCommand.new(tick, ids, int(group.target_id), {"trigger": "source_attack_group", "attack_group_id": int(group.group_id)})]
	group.target_id = -1
	group.target_observed = false
	group.transition(AttackGroup.ATTACKING, "coordination_released", tick)
	return [Commands.AttackMoveCommand.new(tick, ids, group.objective_position)]


static func _target_with_id(snapshot: Dictionary, target_id: int) -> Dictionary:
	for category in ["units", "buildings"]:
		for target_value in snapshot.get(category, []):
			var target: Dictionary = target_value
			if int(target.get("id", -1)) == target_id:
				return target
	return {}


static func _wave_ready(groups: Dictionary, team: int, wave_id: int) -> bool:
	var found := false
	for group_value in groups.values():
		var group = group_value
		if int(group.team) != team or int(group.wave_id) != wave_id or String(group.state) in [AttackGroup.COMPLETE, AttackGroup.RETREATING, AttackGroup.RECENTERING]:
			continue
		found = true
		if String(group.state) != AttackGroup.READY:
			return false
	return found


static func _group_is_gathered(group, units_by_id: Dictionary) -> bool:
	if float(group.gather_spacing) <= 0.0:
		return true
	for entity_id in group.active_member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and Vector2(unit.get("pos", Vector2.ZERO)).distance_to(group.rally_position) > float(group.gather_spacing) + 0.0001:
			return false
	return true


static func _members_are_gathered(members: Array, rally: Vector2, spacing: float) -> bool:
	for member_value in members:
		if Vector2(member_value.get("pos", Vector2.ZERO)).distance_to(rally) > spacing + 0.0001:
			return false
	return true


static func _partition_attack_groups(fighters: Array, minimum_group: int, maximum_group: int, group_count: int, fill_method: int) -> Array:
	var remaining: Array = fighters.duplicate()
	var partitions: Array = []
	while partitions.size() < group_count:
		var domain := _first_viable_group_domain(remaining, minimum_group)
		if domain.is_empty():
			break
		var domain_fighters: Array = remaining.filter(func(entity): return String(entity.get("movement_domain", "land")) == domain)
		var initial_size := minimum_group if fill_method == 1 else mini(maximum_group, domain_fighters.size())
		var members: Array = domain_fighters.slice(0, initial_size)
		partitions.append(members)
		remaining = _without_members(remaining, members)
	if fill_method == 0 or partitions.is_empty():
		return partitions
	var cursor := 0
	while not remaining.is_empty():
		var assigned := false
		for step in range(partitions.size()):
			var group_index := posmod(cursor + step, partitions.size())
			var members: Array = partitions[group_index]
			if members.size() >= maximum_group:
				continue
			var domain := String(members[0].get("movement_domain", "land"))
			var candidate_index := -1
			for index in range(remaining.size()):
				if String(remaining[index].get("movement_domain", "land")) == domain:
					candidate_index = index
					break
			if candidate_index < 0:
				continue
			members.append(remaining[candidate_index])
			partitions[group_index] = members
			remaining.remove_at(candidate_index)
			cursor = posmod(group_index + 1, partitions.size())
			assigned = true
			break
		if not assigned:
			break
	return partitions


static func _without_members(source: Array, members: Array) -> Array:
	var removed_ids: Dictionary = {}
	for member_value in members:
		removed_ids[int(member_value.get("id", -1))] = true
	return source.filter(func(entity): return not removed_ids.has(int(entity.get("id", -1))))


static func _begin_group_retreat(group, tick: int, reason: String) -> Array:
	var ids: Array[int] = group.living_ids()
	group.target_id = -1
	group.target_observed = false
	group.objective_position = group.rally_position
	group.transition(AttackGroup.RETREATING, reason, tick)
	if ids.is_empty():
		return []
	return [Commands.FormationMoveCommand.new(tick, ids, group.rally_position, group.formation_name)]


static func _target_destroyed_commands(snapshot: Dictionary, tick: int, team: int, group, policy: int) -> Array:
	group.target_id = -1
	group.target_observed = false
	var active_ids: Array[int] = group.active_member_ids.duplicate()
	if active_ids.is_empty():
		group.transition(AttackGroup.COMPLETE, "target_destroyed_without_attackers", tick)
		return []
	match policy:
		0:
			var center := _member_center(active_ids, snapshot.get("units", []), group.objective_position)
			group.objective_position = center
			group.transition(AttackGroup.RECENTERING, "target_destroyed_recenter", tick)
			return [Commands.FormationMoveCommand.new(tick, active_ids, center, group.formation_name)]
		1:
			var next_target := _compatible_visible_target(snapshot, team, group.movement_domain)
			if not next_target.is_empty():
				group.target_id = int(next_target.get("id", -1))
				group.target_observed = true
				group.objective_position = Vector2(next_target.get("pos", group.objective_position))
				group.transition(AttackGroup.ATTACKING, "target_destroyed_retarget", tick)
				return [Commands.AttackCommand.new(tick, active_ids, group.target_id, {"trigger": "source_attack_group_retarget", "attack_group_id": int(group.group_id)})]
			return _begin_group_retreat(group, tick, "target_destroyed_no_reachable_visible_target")
		2:
			return _begin_group_retreat(group, tick, "target_destroyed_always_retreat")
		3:
			group.transition(AttackGroup.EXTERMINATING, "target_destroyed_extermination", tick)
			return _continue_extermination(snapshot, tick, team, group)
	return []


static func _continue_extermination(snapshot: Dictionary, tick: int, team: int, group) -> Array:
	var active_ids: Array[int] = group.active_member_ids.duplicate()
	if active_ids.is_empty():
		group.transition(AttackGroup.COMPLETE, "extermination_without_attackers", tick)
		return []
	var next_target := _compatible_visible_target(snapshot, team, group.movement_domain)
	if not next_target.is_empty():
		group.target_id = int(next_target.get("id", -1))
		group.target_observed = true
		group.objective_position = Vector2(next_target.get("pos", group.objective_position))
		group.transition(AttackGroup.EXTERMINATING, "extermination_target", tick)
		return [Commands.AttackCommand.new(tick, active_ids, group.target_id, {"trigger": "source_attack_group_extermination", "attack_group_id": int(group.group_id)})]
	var frontier: Variant = _extermination_frontier(snapshot, group)
	if frontier == null:
		group.transition(AttackGroup.COMPLETE, "extermination_map_exhausted", tick)
		return []
	group.target_id = -1
	group.target_observed = false
	group.objective_position = Vector2(frontier)
	group.transition(AttackGroup.EXTERMINATING, "extermination_explore", tick)
	return [Commands.AttackMoveCommand.new(tick, active_ids, group.objective_position)]


static func _update_defend_group(snapshot: Dictionary, tick: int, team: int, group, units_by_id: Dictionary, anchors_by_id: Dictionary) -> Array:
	var anchor: Variant = anchors_by_id.get(int(group.anchor_id))
	if anchor == null or (anchor.has("hp") and float(anchor.get("hp", 0.0)) <= 0.0) or (anchor.has("amount") and int(anchor.get("amount", 0)) <= 0):
		group.transition(AssignmentGroup.COMPLETE, "defence_anchor_unavailable", tick)
		return []
	group.anchor_position = Vector2(anchor.get("pos", group.anchor_position))
	group.objective_position = group.anchor_position
	var enemy := _defence_enemy(snapshot, team, group.anchor_position, float(group.defence_distance), String(group.movement_domain))
	if not enemy.is_empty():
		var target_id := int(enemy.get("id", -1))
		var already_engaging := int(group.target_id) == target_id and _members_attack_target(group.member_ids, units_by_id, target_id)
		group.target_id = target_id
		group.transition(AssignmentGroup.ENGAGING, "enemy_inside_defence_radius", tick)
		if not already_engaging:
			return [Commands.AttackCommand.new(tick, group.member_ids, target_id, {"trigger": "source_defend_group", "assignment_group_id": int(group.group_id)})]
		return []
	var returning_from_engagement := int(group.target_id) >= 0 or String(group.state) == AssignmentGroup.ENGAGING
	group.target_id = -1
	var center := _member_center(group.member_ids, snapshot.get("units", []), group.anchor_position)
	if not returning_from_engagement and String(group.state) == AssignmentGroup.MOVING and not _assignment_members_settled(group.member_ids, units_by_id):
		return []
	if returning_from_engagement or center.distance_to(group.anchor_position) > maxf(0.75, float(group.defence_distance)):
		group.transition(AssignmentGroup.MOVING, "return_to_defence_anchor", tick)
		return [Commands.FormationMoveCommand.new(tick, group.member_ids, group.anchor_position, group.formation_name)]
	if _assignment_members_settled(group.member_ids, units_by_id):
		group.transition(AssignmentGroup.ACTIVE, "defence_anchor_held", tick)
	return []


static func _update_escort_group(snapshot: Dictionary, tick: int, team: int, group, units_by_id: Dictionary, anchors_by_id: Dictionary) -> Array:
	var anchor: Variant = anchors_by_id.get(int(group.anchor_id))
	var escort_kind := String(group.anchor_kind).trim_prefix("escort_")
	if anchor == null \
			or float(anchor.get("hp", 0.0)) <= 0.0 \
			or int(anchor.get("team", 0)) != team \
			or not _is_escort_anchor(anchor, escort_kind):
		group.transition(AssignmentGroup.COMPLETE, "escort_anchor_unavailable", tick)
		return []
	var previous_objective := Vector2(group.objective_position)
	group.anchor_position = Vector2(anchor.get("pos", group.anchor_position))
	var enemy := _defence_enemy(snapshot, team, group.anchor_position, float(group.defence_distance), "water")
	if not enemy.is_empty():
		var target_id := int(enemy.get("id", -1))
		var already_engaging := int(group.target_id) == target_id and _members_attack_target(group.member_ids, units_by_id, target_id)
		group.target_id = target_id
		group.objective_position = Vector2(enemy.get("pos", group.anchor_position))
		group.transition(AssignmentGroup.ENGAGING, "enemy_near_escort_anchor", tick)
		if not already_engaging:
			return [Commands.AttackCommand.new(tick, group.member_ids, target_id, {"trigger": "source_escort_group", "assignment_group_id": int(group.group_id), "escort_anchor_id": int(group.anchor_id)})]
		return []
	var returning_from_engagement := int(group.target_id) >= 0 or String(group.state) == AssignmentGroup.ENGAGING
	group.target_id = -1
	var follow_distance := maxf(0.75, float(group.influence_radius))
	var center := _member_center(group.member_ids, snapshot.get("units", []), group.anchor_position)
	var anchor_shifted := previous_objective.distance_to(group.anchor_position) > follow_distance
	group.objective_position = group.anchor_position
	if not returning_from_engagement \
			and String(group.state) == AssignmentGroup.MOVING \
			and not anchor_shifted \
			and not _assignment_members_settled(group.member_ids, units_by_id):
		return []
	if returning_from_engagement or center.distance_to(group.anchor_position) > follow_distance:
		group.transition(AssignmentGroup.MOVING, "follow_escort_anchor", tick)
		return [Commands.AttackMoveCommand.new(tick, group.member_ids, group.anchor_position)]
	if _assignment_members_settled(group.member_ids, units_by_id):
		group.transition(AssignmentGroup.ACTIVE, "escort_anchor_held", tick)
	return []


static func _update_explore_group(snapshot: Dictionary, tick: int, group, units_by_id: Dictionary) -> Array:
	if not _assignment_members_settled(group.member_ids, units_by_id):
		return []
	var origin := _member_center(group.member_ids, snapshot.get("units", []), group.objective_position)
	var frontier: Variant = _frontier_for_domain(snapshot, String(group.movement_domain), origin, 0.25)
	if frontier == null:
		group.transition(AssignmentGroup.COMPLETE, "exploration_map_exhausted", tick)
		return []
	group.objective_position = Vector2(frontier)
	group.transition(AssignmentGroup.MOVING, "exploration_frontier_advanced", tick)
	if String(group.anchor_kind) == "civilian":
		return [Commands.MoveCommand.new(tick, group.member_ids, group.objective_position)]
	return [Commands.AttackMoveCommand.new(tick, group.member_ids, group.objective_position)]


static func _members_attack_target(member_ids: Array[int], units_by_id: Dictionary, target_id: int) -> bool:
	if member_ids.is_empty():
		return false
	for entity_id in member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit == null or String(unit.get("task", "idle")) != "attack" or int(unit.get("target_id", -1)) != target_id:
			return false
	return true


static func _assignment_members_settled(member_ids: Array[int], units_by_id: Dictionary) -> bool:
	for entity_id in member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and String(unit.get("task", "idle")) in ["move", "attack_move", "attack"]:
			return false
	return true


static func _defence_enemy(snapshot: Dictionary, team: int, anchor: Vector2, radius: float, domain: String) -> Dictionary:
	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var candidates: Array = []
	for category in ["units", "buildings"]:
		for target_value in snapshot.get(category, []):
			var target: Dictionary = target_value
			var owner := int(target.get("team", 0))
			if owner <= 0 or owner == team or allies.has(owner) or float(target.get("hp", 0.0)) <= 0.0:
				continue
			var domains: Array = target.get("target_domains", [])
			if domains.is_empty():
				domains = [String(target.get("movement_domain", "land"))]
			if domain not in domains or Vector2(target.get("pos", Vector2.ZERO)).distance_to(anchor) > radius + 0.0001:
				continue
			candidates.append(target)
	candidates.sort_custom(func(left, right):
		var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(anchor)
		var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(anchor)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	return {} if candidates.is_empty() else candidates[0]


static func _defence_anchors(snapshot: Dictionary, team: int, numbers: Dictionary, occupied_ids: Dictionary, _limit: int) -> Array:
	var candidates: Array = []
	var town_priority := clampi(int(numbers.get(56, 0)), 0, 7)
	if town_priority > 0:
		for building_value in snapshot.get("buildings", []):
			var building: Dictionary = building_value
			if int(building.get("team", 0)) == team and String(building.get("kind", "")) == "town_center" and float(building.get("hp", 0.0)) > 0.0:
				candidates.append(_defence_anchor(building, town_priority, float(numbers.get(22, 0)), "town"))
	var resource_priorities := {3: int(numbers.get(50, 0)), 2: int(numbers.get(51, 0))}
	for resource_value in snapshot.get("resources", []):
		var resource: Dictionary = resource_value
		if int(resource.get("amount", 0)) <= 0:
			continue
		var priority := clampi(int(resource_priorities.get(int(resource.get("resource_type_id", -1)), 0)), 0, 7)
		if priority <= 0 and _is_forage_resource(resource):
			priority = clampi(int(numbers.get(52, 0)), 0, 7)
		if priority > 0:
			candidates.append(_defence_anchor(resource, priority, float(numbers.get(57, 0)), "resource"))
	var objective_priorities := {"ruin": int(numbers.get(54, 0)), "artifact": int(numbers.get(55, 0))}
	for objective_value in snapshot.get("objectives", []):
		var objective: Dictionary = objective_value
		var kind := String(objective.get("kind", "")).to_lower()
		var priority := clampi(int(objective_priorities.get(kind, 0)), 0, 7)
		if priority > 0:
			candidates.append(_defence_anchor(objective, priority, float(numbers.get(57, 0)), kind))
	candidates.sort_custom(func(left, right):
		if int(left.get("priority", 0)) != int(right.get("priority", 0)):
			return int(left.get("priority", 0)) < int(right.get("priority", 0))
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	var selected: Array = []
	var influence := maxf(0.0, float(numbers.get(92, 0)))
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		if occupied_ids.has(int(candidate.get("id", -1))):
			continue
		var overlaps := selected.any(func(existing):
			return influence > 0.0 and Vector2(existing.get("position", Vector2.ZERO)).distance_to(Vector2(candidate.get("position", Vector2.ZERO))) < influence * 2.0 - 0.0001
		)
		if overlaps:
			continue
		selected.append(candidate)
	return selected


static func _dock_defence_anchors(snapshot: Dictionary, team: int, numbers: Dictionary, occupied_ids: Dictionary) -> Array:
	var result: Array = []
	var priority := clampi(int(numbers.get(70, 0)), 0, 1)
	if priority <= 0:
		return result
	for building_value in snapshot.get("buildings", []):
		var building: Dictionary = building_value
		if int(building.get("team", 0)) != team or String(building.get("kind", "")) != "dock" or float(building.get("hp", 0.0)) <= 0.0 or occupied_ids.has(int(building.get("id", -1))):
			continue
		result.append(_defence_anchor(building, priority, float(numbers.get(57, 0)), "dock"))
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _defence_anchor(entity: Dictionary, priority: int, distance: float, category: String) -> Dictionary:
	return {
		"id": int(entity.get("id", -1)),
		"kind": category,
		"position": Vector2(entity.get("pos", Vector2.ZERO)),
		"priority": priority,
		"defence_distance": maxf(0.0, distance),
	}


static func _escort_anchors(snapshot: Dictionary, team: int, escort_kind: String, occupied_ids: Dictionary) -> Array:
	var result: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team \
			and float(entity.get("hp", 0.0)) > 0.0 \
			and String(entity.get("movement_domain", "land")) == "water" \
			and not occupied_ids.has(int(entity.get("id", -1))) \
			and _is_escort_anchor(entity, escort_kind)
	)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _is_escort_anchor(entity: Dictionary, escort_kind: String) -> bool:
	var tags: Array = entity.get("behavior_tags", [])
	var components: Dictionary = entity.get("components", {})
	var kind := String(entity.get("kind", "")).to_lower()
	match escort_kind:
		"trade":
			return "trader" in tags or bool(components.get("trade", {}).get("enabled", false)) or "trade" in kind
		"fish":
			return bool(components.get("worker", {}).get("enabled", false)) and String(entity.get("movement_domain", "land")) == "water"
		"transport":
			return "transport" in tags or bool(components.get("cargo", {}).get("enabled", false)) or "transport" in kind
	return false


static func _is_forage_resource(resource: Dictionary) -> bool:
	var kind := String(resource.get("kind", "")).to_lower()
	return "berry" in kind or "forage" in kind


static func _idle_land_combatants(snapshot: Dictionary, team: int, excluded: Dictionary) -> Array:
	return _idle_domain_combatants(snapshot, team, excluded, "land")


static func _idle_domain_combatants(snapshot: Dictionary, team: int, excluded: Dictionary, domain: String) -> Array:
	var result: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team \
			and not excluded.has(int(entity.get("id", -1))) \
			and float(entity.get("hp", 0.0)) > 0.0 \
			and String(entity.get("movement_domain", "land")) == domain \
			and String(entity.get("task", "idle")) in ["idle", "hold"] \
			and not bool(entity.get("components", {}).get("worker", {}).get("enabled", false)) \
			and (bool(entity.get("combat_enabled", false)) or "combatant" in entity.get("behavior_tags", []))
	)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _idle_land_workers(snapshot: Dictionary, team: int, excluded: Dictionary) -> Array:
	var result: Array = snapshot.get("units", []).filter(func(entity):
		return int(entity.get("team", 0)) == team \
			and not excluded.has(int(entity.get("id", -1))) \
			and float(entity.get("hp", 0.0)) > 0.0 \
			and String(entity.get("movement_domain", "land")) == "land" \
			and String(entity.get("task", "idle")) == "idle" \
			and bool(entity.get("components", {}).get("worker", {}).get("enabled", false))
	)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


static func _partition_defend_groups(defenders: Array, anchors: Array, minimum_group: int, maximum_group: int, group_limit: int, fill_method: int) -> Array:
	if group_limit <= 0 or defenders.size() < minimum_group:
		return []
	var remaining: Array = defenders.duplicate()
	var allocations: Array = []
	for anchor_value in anchors:
		var anchor: Dictionary = anchor_value
		var position := Vector2(anchor.get("position", Vector2.ZERO))
		var radius := maxf(0.75, float(anchor.get("defence_distance", 0.0)))
		var local: Array = remaining.filter(func(entity): return Vector2(entity.get("pos", Vector2.ZERO)).distance_to(position) <= radius + 0.0001)
		if local.size() < minimum_group:
			continue
		var ordered := _entities_by_distance(local, position)
		var take := minimum_group if fill_method == 1 else mini(maximum_group, ordered.size())
		var members: Array = ordered.slice(0, take)
		allocations.append({"anchor": anchor, "members": members})
		remaining = _without_members(remaining, members)
		if allocations.size() >= group_limit:
			break
	if fill_method == 0:
		return allocations
	var cursor := 0
	while not remaining.is_empty():
		var assigned := false
		for step in range(allocations.size()):
			var group_index := posmod(cursor + step, allocations.size())
			var allocation: Dictionary = allocations[group_index]
			var members: Array = allocation.get("members", [])
			if members.size() >= maximum_group:
				continue
			var anchor: Dictionary = allocation.get("anchor", {})
			var position := Vector2(anchor.get("position", Vector2.ZERO))
			var radius := maxf(0.75, float(anchor.get("defence_distance", 0.0)))
			var local: Array = remaining.filter(func(entity): return Vector2(entity.get("pos", Vector2.ZERO)).distance_to(position) <= radius + 0.0001)
			var ordered := _entities_by_distance(local, position)
			if ordered.is_empty():
				continue
			var member: Dictionary = ordered[0]
			members.append(member)
			allocation["members"] = members
			allocations[group_index] = allocation
			remaining = _without_members(remaining, [member])
			cursor = posmod(group_index + 1, allocations.size())
			assigned = true
			break
		if not assigned:
			break
	return allocations


static func _partition_escort_groups(escorts: Array, anchors: Array, desired_member_count: int) -> Array:
	var remaining: Array = escorts.duplicate()
	var allocations: Array = []
	var budget := mini(maxi(0, desired_member_count), remaining.size())
	for anchor_value in anchors:
		if budget <= 0 or remaining.is_empty():
			break
		var anchor: Dictionary = anchor_value
		var ordered := _entities_by_distance(remaining, Vector2(anchor.get("pos", Vector2.ZERO)))
		var member: Dictionary = ordered[0]
		allocations.append({"anchor": anchor, "members": [member]})
		remaining = _without_members(remaining, [member])
		budget -= 1
	while budget > 0 and not remaining.is_empty() and not allocations.is_empty():
		var best_allocation_index := -1
		var best_member: Dictionary = {}
		var best_distance := INF
		for allocation_index in range(allocations.size()):
			var allocation: Dictionary = allocations[allocation_index]
			var anchor_position := Vector2(allocation.get("anchor", {}).get("pos", Vector2.ZERO))
			for member_value in remaining:
				var member: Dictionary = member_value
				var distance := Vector2(member.get("pos", Vector2.ZERO)).distance_squared_to(anchor_position)
				var is_better := distance < best_distance - 0.0001
				if is_equal_approx(distance, best_distance) and best_allocation_index >= 0:
					var current_anchor_id := int(allocation.get("anchor", {}).get("id", -1))
					var best_anchor_id := int(allocations[best_allocation_index].get("anchor", {}).get("id", -1))
					is_better = current_anchor_id < best_anchor_id or (current_anchor_id == best_anchor_id and int(member.get("id", -1)) < int(best_member.get("id", -1)))
				if is_better:
					best_distance = distance
					best_allocation_index = allocation_index
					best_member = member
		if best_allocation_index < 0:
			break
		allocations[best_allocation_index]["members"].append(best_member)
		remaining = _without_members(remaining, [best_member])
		budget -= 1
	return allocations


static func _entities_by_distance(entities: Array, position: Vector2) -> Array:
	var result: Array = entities.duplicate()
	result.sort_custom(func(left, right):
		var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(position)
		var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(position)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left.get("id", -1)) < int(right.get("id", -1))
	)
	return result


static func _compatible_visible_target(snapshot: Dictionary, team: int, domain: String) -> Dictionary:
	var allies: Array = snapshot.get("player_state", {}).get("allies", [team])
	var targets: Array = []
	for category in ["units", "buildings"]:
		for target_value in snapshot.get(category, []):
			var target: Dictionary = target_value
			var owner := int(target.get("team", 0))
			if owner <= 0 or owner == team or allies.has(owner) or float(target.get("hp", 0.0)) <= 0.0:
				continue
			var domains: Array = target.get("target_domains", [])
			if domains.is_empty():
				domains = [String(target.get("movement_domain", "land"))]
			if domain in domains:
				targets.append(target)
	targets.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return {} if targets.is_empty() else targets[0]


static func _extermination_frontier(snapshot: Dictionary, group) -> Variant:
	var center := _member_center(group.active_member_ids, snapshot.get("units", []), group.objective_position)
	return _frontier_for_domain(snapshot, String(group.movement_domain), center)


static func _frontier_for_domain(snapshot: Dictionary, domain: String, origin: Vector2, minimum_distance: float = 0.0) -> Variant:
	var size: Vector2i = snapshot.get("map_size", Vector2i.ZERO)
	var fog_cells: Variant = snapshot.get("fog", {}).get("cells", [])
	var navigation: Array = snapshot.get("navigation", {}).get(domain, [])
	if size.x <= 0 or size.y <= 0 or fog_cells.size() != size.x * size.y or navigation.is_empty():
		return null
	var candidates: Array[Vector2] = []
	for point_value in navigation:
		var point := Vector2(point_value)
		if point.distance_to(origin) <= minimum_distance + 0.0001:
			continue
		var cell := Vector2i(floori(point.x), floori(point.y))
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			continue
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < size.x and neighbor.y < size.y and int(fog_cells[neighbor.y * size.x + neighbor.x]) == 0:
				candidates.append(point)
				break
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left, right):
		var left_distance: float = left.distance_squared_to(origin)
		var right_distance: float = right.distance_squared_to(origin)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		if not is_equal_approx(left.y, right.y):
			return left.y < right.y
		return left.x < right.x
	)
	return candidates[0]


static func _observe_group_target(group, units_by_id: Dictionary) -> void:
	var observed: Array[int] = []
	for entity_id in group.active_member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and String(unit.get("task", "idle")) == "attack" and int(unit.get("target_id", -1)) >= 0:
			observed.append(int(unit.get("target_id", -1)))
	if not observed.is_empty():
		observed.sort()
		group.target_id = observed[0]
		group.target_observed = true


static func _group_target_destroyed(group, targets_by_id: Dictionary, units_by_id: Dictionary) -> bool:
	if not bool(group.target_observed) or int(group.target_id) < 0:
		return false
	var target: Variant = targets_by_id.get(int(group.target_id))
	if target != null:
		return float(target.get("hp", 0.0)) <= 0.0
	for entity_id in group.active_member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit == null:
			continue
		if String(unit.get("task", "idle")) == "attack" and int(unit.get("target_id", -1)) == int(group.target_id):
			return false
		if String(unit.get("diagnostic_reason", "")) == "combat_complete:target_unavailable":
			return true
	return false


static func _group_movement_complete(group, units_by_id: Dictionary) -> bool:
	for entity_id in group.living_ids():
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and String(unit.get("task", "idle")) in ["move", "attack_move", "attack"]:
			return false
	return true


static func _active_members_settled(group, units_by_id: Dictionary) -> bool:
	if group.active_member_ids.is_empty():
		return true
	for entity_id in group.active_member_ids:
		var unit: Variant = units_by_id.get(entity_id)
		if unit != null and String(unit.get("task", "idle")) in ["move", "attack_move", "attack"]:
			return false
	return true


static func _exclude_group_members(group, target: Dictionary) -> void:
	for entity_id in group.living_ids():
		target[entity_id] = true


static func _member_center(member_ids: Array[int], units: Array, fallback: Vector2) -> Vector2:
	var requested: Dictionary = {}
	for entity_id in member_ids:
		requested[entity_id] = true
	var center := Vector2.ZERO
	var count := 0
	for unit_value in units:
		var unit: Dictionary = unit_value
		if requested.has(int(unit.get("id", -1))) and float(unit.get("hp", 0.0)) > 0.0:
			center += Vector2(unit.get("pos", Vector2.ZERO))
			count += 1
	return fallback if count <= 0 else center / float(count)


static func _entity_center(entities: Array) -> Vector2:
	if entities.is_empty():
		return Vector2.ZERO
	var center := Vector2.ZERO
	for entity_value in entities:
		center += Vector2(entity_value.get("pos", Vector2.ZERO))
	return center / float(entities.size())


static func _first_viable_group_domain(fighters: Array, minimum_group: int) -> String:
	var counts: Dictionary = {}
	for fighter_value in fighters:
		var domain := String(fighter_value.get("movement_domain", "land"))
		counts[domain] = int(counts.get(domain, 0)) + 1
	for fighter_value in fighters:
		var domain := String(fighter_value.get("movement_domain", "land"))
		if int(counts.get(domain, 0)) >= minimum_group:
			return domain
	return ""


static func _first_viable_target_domain(fighters: Array, minimum_group: int, snapshot: Dictionary, team: int) -> String:
	var counts: Dictionary = {}
	for fighter_value in fighters:
		var domain := String(fighter_value.get("movement_domain", "land"))
		counts[domain] = int(counts.get(domain, 0)) + 1
	for fighter_value in fighters:
		var domain := String(fighter_value.get("movement_domain", "land"))
		if int(counts.get(domain, 0)) >= minimum_group and not _compatible_visible_target(snapshot, team, domain).is_empty():
			return domain
	return ""


static func strategic_number_values(contract: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for entry_value in contract.get("strategic_numbers", []):
		var entry: Dictionary = entry_value
		var runtime_semantics := String(entry.get("runtime_semantics", ""))
		if not runtime_semantics.is_empty() and runtime_semantics != "implemented":
			continue
		result[int(entry.get("source_id", -1))] = int(entry.get("value", 0))
	return result


static func _configure_group_commander(group, members: Array, numbers: Dictionary) -> void:
	if numbers.has(75):
		group.configure_commander(members, clampi(int(numbers.get(75, 0)), 0, 2))


static func _idle_worker_commands(snapshot: Dictionary, tick: int, own_units: Array, excluded_workers: Dictionary = {}) -> Array:
	var resources: Array = snapshot.get("resources", []).filter(func(entity): return int(entity.get("amount", 0)) > 0)
	for building_value in snapshot.get("buildings", []):
		var building: Dictionary = building_value
		if bool(building.get("harvestable", false)) and int(building.get("amount", 0)) > 0:
			resources.append(building)
	if resources.is_empty():
		return []
	var commands: Array = []
	for worker_value in own_units:
		var worker: Dictionary = worker_value
		if excluded_workers.has(int(worker.get("id", -1))) or not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)) or String(worker.get("task", "idle")) != "idle":
			continue
		var candidates: Array = resources.filter(func(resource): return _resource_allows_worker(resource, worker))
		candidates.sort_custom(func(left, right):
			var left_distance := Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(left.get("pos", Vector2.ZERO)))
			var right_distance := Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(right.get("pos", Vector2.ZERO)))
			if not is_equal_approx(left_distance, right_distance):
				return left_distance < right_distance
			return int(left.get("id", -1)) < int(right.get("id", -1))
		)
		if not candidates.is_empty():
			commands.append(Commands.GatherCommand.new(tick, [int(worker.get("id", -1))], int(candidates[0].get("id", -1))))
	return commands


static func _housing_command(snapshot: Dictionary, tick: int, own_units: Array, city_plan = null) -> Variant:
	var player_state: Dictionary = snapshot.get("player_state", {})
	var population := int(player_state.get("population", 0))
	var reserved := int(player_state.get("population_reserved", 0))
	var cap := int(player_state.get("population_cap", 0))
	var limit := int(player_state.get("population_limit", cap))
	if cap <= 0 or cap >= limit or population + reserved < cap - 1:
		return null
	var sites: Array = snapshot.get("build_sites", {}).get("house", [])
	if city_plan != null:
		sites = city_plan.filter_sites(sites, "house")
	if sites.is_empty():
		return null
	var candidates: Array = []
	for worker_value in own_units:
		var worker: Dictionary = worker_value
		if not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)) or String(worker.get("task", "idle")) != "idle" or String(worker.get("movement_domain", "land")) != "land":
			continue
		var can_build_house: bool = worker.get("command_options", {}).get("build", []).any(func(option):
			return String(option.get("kind", "")) == "house" and bool(option.get("accepted", false))
		)
		if not can_build_house:
			continue
		for site_value in sites:
			var site := Vector2(site_value)
			candidates.append({
				"worker": worker,
				"site": site,
				"plan_rank": city_plan.site_rank(site, "house") if city_plan != null else 0,
				"distance": Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(site),
			})
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left, right):
		if int(left.get("plan_rank", 0)) != int(right.get("plan_rank", 0)):
			return int(left.get("plan_rank", 0)) < int(right.get("plan_rank", 0))
		if not is_equal_approx(float(left["distance"]), float(right["distance"])):
			return float(left["distance"]) < float(right["distance"])
		return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))
	)
	var chosen: Dictionary = candidates[0]
	return Commands.BuildCommand.new(tick, [int(chosen["worker"].get("id", -1))], "house", chosen["site"])


static func _next_build_order_command(snapshot: Dictionary, tick: int, team: int, contract: Dictionary, own_units: Array, own_buildings: Array, numbers: Dictionary = {}, city_plan = null) -> Variant:
	var researched: Array = snapshot.get("player_state", {}).get("researched_technologies", [])
	for entry_value in contract.get("build_order", []):
		var entry: Dictionary = entry_value
		var entry_type: String = String(entry.get("type", ""))
		var source_id: int = int(entry.get("source_id", -1))
		var producer_source_id: int = int(entry.get("producer_source_unit_id", -1))
		if entry_type == "building":
			var building_alias: String = String(entry.get("runtime_alias", ""))
			var building_target_count: int = maxi(0, int(entry.get("target_count", 0)))
			var current_building_count: int = own_buildings.filter(func(building):
				return _building_matches_entry(building, source_id, building_alias)
			).size()
			if current_building_count >= building_target_count:
				continue
			var sites: Array = _source_distance_filtered_sites(snapshot.get("build_sites", {}).get(building_alias, []), building_alias, own_buildings, numbers)
			if city_plan != null:
				sites = city_plan.filter_sites(sites, building_alias)
			var candidates: Array = []
			for worker_value in own_units:
				var worker: Dictionary = worker_value
				if String(worker.get("task", "idle")) != "idle" or String(worker.get("movement_domain", "land")) != "land" or not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)):
					continue
				var can_build: bool = worker.get("command_options", {}).get("build", []).any(func(option):
					return String(option.get("kind", "")) == building_alias and bool(option.get("accepted", false))
				)
				if not can_build:
					continue
				for site_value in sites:
					var site := Vector2(site_value)
					candidates.append({
						"worker": worker,
						"site": site,
						"plan_rank": city_plan.site_rank(site, building_alias) if city_plan != null else 0,
						"distance": Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(site),
					})
			if candidates.is_empty():
				return null
			candidates.sort_custom(func(left, right):
				if int(left.get("plan_rank", 0)) != int(right.get("plan_rank", 0)):
					return int(left.get("plan_rank", 0)) < int(right.get("plan_rank", 0))
				if not is_equal_approx(float(left["distance"]), float(right["distance"])):
					return float(left["distance"]) < float(right["distance"])
				return int(left["worker"].get("id", -1)) < int(right["worker"].get("id", -1))
			)
			var chosen: Dictionary = candidates[0]
			return Commands.BuildCommand.new(tick, [int(chosen["worker"].get("id", -1))], building_alias, chosen["site"])
		var producers: Array = own_buildings.filter(func(building):
			return String(building.get("state", "complete")) == "complete" and _entity_matches_source(building, producer_source_id) and building.get("production_queue", []).is_empty()
		)
		producers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
		if entry_type == "technology":
			if researched.has(source_id):
				continue
			for producer_value in producers:
				var producer: Dictionary = producer_value
				for option_value in producer.get("command_options", {}).get("research", []):
					var option: Dictionary = option_value
					if int(option.get("technology_id", -1)) == source_id and bool(option.get("accepted", false)):
						return Commands.ResearchCommand.new(tick, [int(producer.get("id", -1))], String.num_int64(source_id))
			return null
		if entry_type != "unit":
			continue
		var alias: String = String(entry.get("runtime_alias", ""))
		var target_count: int = maxi(0, int(entry.get("target_count", 0)))
		var current_count: int = own_units.filter(func(unit): return _unit_matches_entry(unit, source_id, alias)).size()
		var queued_count: int = 0
		for building in own_buildings:
			queued_count += building.get("production_queue", []).filter(func(order): return String(order.get("kind", "")) == alias).size()
		if current_count + queued_count >= target_count:
			continue
		for producer_value in producers:
			var producer: Dictionary = producer_value
			for option_value in producer.get("command_options", {}).get("train", []):
				var option: Dictionary = option_value
				if String(option.get("kind", "")) == alias and bool(option.get("accepted", false)):
					return Commands.TrainCommand.new(tick, [int(producer.get("id", -1))], alias, team, Vector2(producer.get("rally_point", producer.get("pos", Vector2.ZERO))))
		return null
	return null


static func _source_distance_filtered_sites(sites: Array, building_alias: String, own_buildings: Array, numbers: Dictionary) -> Array:
	var source_id := 86 if building_alias == "storage_pit" else (87 if building_alias == "granary" else -1)
	if source_id < 0 or not numbers.has(source_id):
		return sites
	var maximum_distance := maxf(0.0, float(numbers[source_id]))
	var town_centers: Array = own_buildings.filter(func(building):
		return String(building.get("kind", "")) == "town_center" and float(building.get("hp", 0.0)) > 0.0
	)
	if town_centers.is_empty():
		return []
	return sites.filter(func(site_value):
		var site := Vector2(site_value)
		return town_centers.any(func(town): return site.distance_to(Vector2(town.get("pos", Vector2.ZERO))) <= maximum_distance + 0.0001)
	)


static func _entity_matches_source(entity: Dictionary, source_id: int) -> bool:
	return int(entity.get("source_unit_id", -1)) == source_id or entity.get("unit_lineage", []).has(source_id)


static func _unit_matches_entry(unit: Dictionary, source_id: int, alias: String) -> bool:
	return _entity_matches_source(unit, source_id) or (not alias.is_empty() and String(unit.get("kind", "")) == alias)


static func _building_matches_entry(building: Dictionary, source_id: int, alias: String) -> bool:
	return _entity_matches_source(building, source_id) or (not alias.is_empty() and String(building.get("kind", "")) == alias)


static func _resource_allows_worker(resource: Dictionary, worker: Dictionary) -> bool:
	var allowed_domains: Array = resource.get("allowed_gatherer_domains", [])
	return allowed_domains.is_empty() or String(worker.get("movement_domain", "land")) in allowed_domains
