class_name RoRAiOperations
extends RefCounted
const Group := preload("res://scripts/source_ai_attack_group.gd")
const Commands := preload("res://scripts/commands.gd")
const Combat := preload("res://scripts/ai_combat_model.gd")
const Economy := preload("res://scripts/ai_adaptive_economy.gd")
var groups: Dictionary = {}
var next_id := 1
var scouts: Dictionary = {}


func plan(
	snapshot: Dictionary,
	tick: int,
	team: int,
	goal: Dictionary,
	policy: Dictionary,
	state,
	reserved: Dictionary,
	formation: String,
	attack_allowed: bool
) -> Array:
	var own := Economy.own(snapshot.get("units", []), team)
	var by_id: Dictionary = {}
	for actor in own:
		by_id[int(actor["id"])] = actor
	# Own cargo IDs remain known while removed from the active unit collection.
	# Keep group membership alive and reserve those IDs until disembarkation.
	for transport in own:
		for passenger in transport.get("components", {}).get("cargo", {}).get("passenger_ids", []):
			var id := int(passenger)
			reserved[id] = true
			for operation in groups.values():
				var group = operation["group"]
				if id in group.member_ids:
					by_id[id] = {
						"id": id,
						"team": team,
						"hp": float(group.initial_hp_by_member.get(id, 1.0)),
						"pos": transport.get("pos", Vector2.ZERO),
						"task": "embarked"
					}
	var result: Array = []
	var ids: Array = groups.keys()
	ids.sort()
	var claimed: Dictionary = reserved.duplicate()
	for id in ids:
		var operation: Dictionary = groups[id]
		var group = operation["group"]
		group.sync_members(by_id, tick)
		var regions: Dictionary = snapshot.get("navigation", {}).get("unit_regions", {})
		var known_regions: Dictionary = {}
		for member in group.living_ids():
			if regions.has(int(member)):
				known_regions[String(regions[int(member)])] = int(member)
		if known_regions.size() == 1:
			var region := String(known_regions.keys()[0])
			if String(operation.get("region", region)) != region:
				operation["region"] = region
				group.rally_position = Vector2(by_id[known_regions[region]].get("pos", group.rally_position))
		if group.current_living_count == 0:
			groups.erase(id)
			continue
		for member in group.living_ids():
			claimed[int(member)] = true
	result.append_array(_scout(snapshot, tick, team, own, policy, state, claimed))
	var regions: Dictionary = snapshot.get("navigation", {}).get("unit_regions", {})
	var available_components: Dictionary = {}
	for actor in own:
		var domain := String(actor.get("movement_domain", "land"))
		if (
			domain not in ["land", "water"]
			or not bool(actor.get("combat_enabled", false))
			or bool(actor.get("components", {}).get("worker", {}).get("enabled", false))
		):
			continue
		var region := String(regions.get(int(actor["id"]), domain))
		available_components[domain + ":" + region] = {"domain": domain, "region": region}
	var component_keys: Array = available_components.keys()
	component_keys.sort()
	for component in component_keys:
		var domain := String(available_components[component]["domain"])
		var region := String(available_components[component]["region"])
		if domain == "land" and String(goal.get("type", "")) != "defend" and region == String(regions.get(int(own[0]["id"]), "land")):
			var local_fighters: Array = own.filter(func(u): return String(u.get("movement_domain", "land")) == domain and String(regions.get(int(u["id"]), domain)) == region and bool(u.get("combat_enabled", false)) and not bool(u.get("components", {}).get("worker", {}).get("enabled", false)))
			if local_fighters.size() >= 8:
				var guards: Array = local_fighters.filter(func(u): return not claimed.has(int(u["id"])) and String(u.get("task", "")) in ["idle", "hold"])
				guards.reverse()
				for guard in guards.slice(0, int(policy.get("home_guard_count", 2))):
					claimed[int(guard["id"])] = true
					reserved[int(guard["id"])] = true
		# Nearby replacements join a marching force. Distant replacements form
		# their own wave instead of waiting for the first operation to disappear.
		if not groups.is_empty():
			var ordered_ids: Array = groups.keys()
			ordered_ids.sort()
			for operation_id in ordered_ids:
				var operation: Dictionary = groups[operation_id]
				var group = operation["group"]
				if (
					group.movement_domain != domain
					or String(operation.get("region", domain)) != region
					or group.state not in [Group.ASSEMBLING, Group.READY, Group.RECENTERING, Group.ATTACKING]
				):
					continue
				var recruits: Array = own.filter(
					func(u): return ( not claimed.has(int(u.get("id", -1))) and not bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and not bool(u.get("components", {}).get("cargo", {}).get("enabled", false)) and bool(u.get("combat_enabled", false)) and String(u.get("movement_domain", "land")) == domain and String(regions.get(int(u.get("id", -1)), domain)) == region and String(u.get("task", "idle")) in ["idle", "hold"] )
				)
				if group.state == Group.ATTACKING:
					var center := Vector2.ZERO
					for member_id in group.living_ids(): center += Vector2(by_id[member_id].get("pos", Vector2.ZERO))
					center /= float(maxi(1, group.current_living_count))
					recruits = recruits.filter(func(u): return Vector2(u.get("pos", Vector2.ZERO)).distance_to(center) <= 8.0)
				for recruit in recruits.slice(
					0, maxi(0, int(policy.get("maximum_attack_group_size", 20)) - group.current_living_count)
				):
					var recruit_id := int(recruit["id"])
					group.member_ids.append(recruit_id)
					group.active_member_ids.append(recruit_id)
					group.initial_hp_by_member[recruit_id] = float(recruit.get("hp", 0.0))
					group.initial_total_hp += float(recruit.get("hp", 0.0))
					claimed[recruit_id] = true
					if group.state == Group.READY and Vector2(recruit.get("pos", Vector2.ZERO)).distance_to(group.rally_position) > 5.0:
						group.transition(Group.ASSEMBLING, "reinforcements_assembling", tick)
						operation["phase_tick"] = tick
						operation["last_order_tick"] = -1
				group.member_ids.sort()
				group.active_member_ids.sort()
				group.sync_members(by_id, tick)
		if groups.size() >= int(policy.get("maximum_operations", 8)):
			continue
		var fighters: Array = own.filter(
			func(u): return ( not claimed.has(int(u.get("id", -1))) and not bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and not bool(u.get("components", {}).get("cargo", {}).get("enabled", false)) and bool(u.get("combat_enabled", false)) and String(u.get("movement_domain", "land")) == domain and String(regions.get(int(u.get("id", -1)), domain)) == region and String(u.get("task", "idle")) in ["idle", "hold", "attack", "attack_move", "move"] )
		)
		var minimum := int(policy.get("minimum_attack_group_size", 3))
		if fighters.size() < minimum and String(goal.get("type", "")) != "defend":
			continue
		if fighters.is_empty():
			continue
		fighters = fighters.slice(0, int(policy.get("maximum_attack_group_size", 20)))
		var rally := Vector2(fighters[0].get("pos", Vector2.ZERO))
		if domain == "land" and region == String(regions.get(int(own[0]["id"]), "land")):
			rally = _rally(snapshot, team, domain, Vector2(goal.get("home", rally)))
		var group = Group.new(
			next_id,
			team,
			fighters,
			Vector2(goal.get("position", rally)),
			int(goal.get("target_id", -1)),
			rally,
			domain,
			formation,
			tick
		)
		group.transition(Group.ASSEMBLING, "skirmish_assembly", tick)
		groups[next_id] = {
			"group": group, "region": region, "phase": "assembly", "last_order_tick": -1, "phase_tick": tick
		}
		next_id += 1
		for actor in fighters:
			claimed[int(actor["id"])] = true
	ids = groups.keys()
	ids.sort()
	for id in ids:
		var operation: Dictionary = groups[id]
		var group = operation["group"]
		var operation_goal: Dictionary = goal.get("goals_by_domain", {}).get(String(group.movement_domain), goal)
		var members: Array = []
		var member_ids: Array[int] = []
		for member_id in group.living_ids():
			if reserved.has(int(member_id)):
				continue
			members.append(by_id[member_id])
			member_ids.append(int(member_id))
			reserved[int(member_id)] = true
		if members.is_empty():
			continue
		var center := Vector2.ZERO
		for actor in members:
			center += Vector2(actor.get("pos", Vector2.ZERO))
		center /= float(members.size())
		var enemies: Array = state.enemies(int(snapshot.get("tick", 0)), policy).filter(
			func(e): return ( Vector2(e.get("pos", Vector2.ZERO)).distance_to(center) <= 12.0 + float(Combat.profile(e).get("range", 0.0)) )
		)
		enemies.sort_custom(
			func(a, b):
				var ad := center.distance_squared_to(Vector2(a.get("pos", Vector2.ZERO)))
				var bd := center.distance_squared_to(Vector2(b.get("pos", Vector2.ZERO)))
				return ad < bd if ad != bd else int(a["id"]) < int(b["id"])
		)
		enemies = enemies.slice(0, int(policy.get("combat_sample_budget", 32)))
		var ours := Combat.strength(members, enemies, int(policy.get("combat_sample_budget", 32)))
		var theirs := 0.0
		for enemy in enemies:
			theirs += (
				Combat.strength([enemy], members, int(policy.get("combat_sample_budget", 32)))
				* float(enemy.get("confidence", 1.0))
			)
		var losing: bool = theirs > 0.0 and ours < theirs * float(policy.get("retreat_ratio", 0.75))
		var depleted: bool = group.health_loss_percent >= float(policy.get("retreat_loss_percent", 45.0))
		if (losing or depleted) and group.state not in [Group.RETREATING, Group.RECENTERING]:
			group.transition(Group.RETREATING, "unfavourable_strength" if losing else "casualties", tick)
			operation["phase"] = "retreat"
			operation["phase_tick"] = tick
			operation["last_order_tick"] = -1
		if group.state == Group.RETREATING and center.distance_to(group.rally_position) <= 4.0:
			group.transition(Group.RECENTERING, "safe_rally_reached", tick)
			operation["phase"] = "regroup"
			operation["phase_tick"] = tick
		if (
			group.state == Group.RECENTERING
			and tick - int(operation["phase_tick"]) >= int(policy.get("regroup_ticks", 160))
		):
			# Refresh loss baselines only after a completed retreat, never in combat.
			var renewed = Group.new(
				group.group_id,
				team,
				members,
				group.objective_position,
				group.target_id,
				group.rally_position,
				group.movement_domain,
				group.formation_name,
				tick
			)
			renewed.transition(Group.ASSEMBLING, "regroup_complete", tick)
			operation["group"] = renewed
			group = renewed
			operation["phase"] = "assembly"
			operation["phase_tick"] = tick
		if group.state == Group.ASSEMBLING:
			var assembled := members.all(
				func(u): return Vector2(u.get("pos", Vector2.ZERO)).distance_to(group.rally_position) <= 5.0
			)
			if (assembled or tick - int(operation["phase_tick"]) >= int(policy.get("assembly_timeout_ticks", 240))) and (members.size() >= int(policy.get("minimum_attack_group_size", 3)) or String(operation_goal.get("type", "")) == "defend"):
				group.transition(Group.READY, "assembled" if assembled else "assembly_timeout", tick)
		if (
			String(operation_goal.get("type", "")) == "defend"
			and String(operation_goal.get("target_domain", "land")) == group.movement_domain
			and group.state not in [Group.RETREATING, Group.RECENTERING]
		):
			group.objective_position = Vector2(operation_goal.get("position", center))
			group.target_id = int(operation_goal.get("target_id", -1))
			group.target_observed = bool(operation_goal.get("observed", false))
			group.transition(Group.ATTACKING, "base_defence", tick)
		if (
			group.state == Group.READY
			and attack_allowed
			and not (group.movement_domain == "land" and bool(operation_goal.get("needs_transport", false)))
			and String(operation_goal.get("type", "")) == "attack"
			and String(operation_goal.get("target_domain", "land")) == group.movement_domain
		):
			var objective := Vector2(operation_goal.get("position", center))
			var guarding: Array = state.enemies(int(snapshot.get("tick", 0)), policy).filter(
				func(e): return Vector2(e.get("pos", Vector2.ZERO)).distance_to(objective) <= 10.0
			)
			var guard_strength := 0.0
			for enemy in guarding.slice(0, int(policy.get("combat_sample_budget", 32))):
				guard_strength += Combat.strength([enemy], members) * float(enemy.get("confidence", 1.0))
			if (
				guard_strength <= 0.0
				or (
					Combat.strength(members, guarding, int(policy.get("combat_sample_budget", 32)))
					>= guard_strength * float(policy.get("attack_ratio", 1.15))
				)
			):
				group.objective_position = objective
				group.target_id = int(operation_goal.get("target_id", -1))
				group.target_observed = bool(operation_goal.get("observed", false))
				group.transition(Group.ATTACKING, "strength_sufficient", tick)
				operation["phase"] = "march"
				operation["last_order_tick"] = -1
		if group.state == Group.ATTACKING:
			if int(operation_goal.get("target_id", -2)) != group.target_id and String(operation_goal.get("type", "")) == "attack" and not members.any(func(u): return String(u.get("task", "")) == "attack"):
				group.transition(Group.READY, "better_objective_available", tick)
				operation["last_order_tick"] = -1
			if int(operation_goal.get("target_id", -2)) == group.target_id:
				group.objective_position = Vector2(operation_goal.get("position", group.objective_position))
				group.target_observed = bool(operation_goal.get("observed", false))
			if not state.memory.has(group.target_id):
				group.transition(Group.READY, "objective_no_longer_known", tick)
				operation["phase"] = "assembly"
			else:
				operation["phase"] = "combat" if not enemies.is_empty() else "march"
		if (
			tick - int(operation["last_order_tick"]) < int(policy.get("operation_order_interval_ticks", 80))
			and int(operation["last_order_tick"]) >= 0
		):
			continue
		var command = null
		if group.state == Group.ATTACKING:
			var order_ids: Array[int] = []
			for member in members:
				if String(member.get("task", "")) == "attack" and not _stalled(member): continue
				var order: Dictionary = member.get("components", {}).get("order", {})
				if String(member.get("task", "")) == "attack_move" and not bool(order.get("completed", false)) and Vector2(order.get("target_position", member.get("destination", Vector2.INF))).distance_to(group.objective_position) <= 2.0 and not _stalled(member): continue
				order_ids.append(int(member["id"]))
			if order_ids.is_empty(): continue
			# Attack-move can investigate a remembered position without issuing an
			# illegal entity attack into fog; common combat awareness picks targets.
			command = Commands.AttackMoveCommand.new(tick, order_ids, group.objective_position)
		elif group.state in [Group.ASSEMBLING, Group.RETREATING, Group.RECENTERING]:
			command = Commands.FormationMoveCommand.new(tick, member_ids, group.rally_position, formation)
		if command != null:
			command.params["_ai_feedback"] = {
				"key": "operation:%d:%s" % [int(id), String(group.state)], "cost": {}, "operation_id": int(id)
			}
			if not state.cooldowns.has(command.params["_ai_feedback"]["key"]):
				result.append(command)
				operation["last_order_tick"] = tick
	return result


static func _stalled(member: Dictionary) -> bool:
	var reason := String(member.get("diagnostic_reason", ""))
	return reason in ["no_path", "local_obstacle", "no_group_route", "target_unreachable", "no_approach_slot"] or reason.begins_with("stuck_")


func _scout(
	snapshot: Dictionary, tick: int, team: int, own: Array, policy: Dictionary, state, claimed: Dictionary
) -> Array:
	var result: Array = []
	if String(state.goal.get("type", "")) == "defend":
		return result
	for domain in ["land", "water"]:
		var assignment: Dictionary = scouts.get(domain, {})
		var actor: Dictionary = {}
		if not assignment.is_empty():
			for unit in own:
				if int(unit.get("id", -1)) == int(assignment.get("id", -2)) and not claimed.has(int(unit["id"])):
					actor = unit
		if actor.is_empty():
			var candidates: Array = own.filter(
				func(u): return ( not claimed.has(int(u.get("id", -1))) and String(u.get("movement_domain", "land")) == domain and not bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and not bool(u.get("components", {}).get("cargo", {}).get("enabled", false)) and bool(u.get("combat_enabled", false)) )
			)
			candidates.sort_custom(
				func(a, b):
					var aspeed := float(Combat.profile(a).get("speed", 0.0))
					var bspeed := float(Combat.profile(b).get("speed", 0.0))
					return aspeed > bspeed if aspeed != bspeed else int(a["id"]) < int(b["id"])
			)
			if (
				candidates.is_empty()
				or (
					not state.memory.is_empty() and candidates.size() <= int(policy.get("minimum_attack_group_size", 3)) + (int(policy.get("home_guard_count", 2)) if domain == "land" and own.size() >= 8 else 0)
				)
			):
				continue
			actor = candidates[0]
			assignment = {"id": int(actor["id"]), "target": Vector2(actor.get("pos", Vector2.ZERO)), "order_tick": -1}
			scouts[domain] = assignment
		var navigation: Dictionary = snapshot.get("navigation", {})
		var region := String(navigation.get("unit_regions", {}).get(int(actor["id"]), domain))
		var frontier: Array = navigation.get("frontier_by_region", {}).get(
			region, navigation.get("reachable_frontier", {}).get(domain, [])
		)
		if frontier.is_empty():
			scouts.erase(domain)
			continue
		claimed[int(actor["id"])] = true
		if int(assignment["order_tick"]) >= 0 and Vector2(actor.get("pos", Vector2.ZERO)).distance_to(Vector2(assignment["target"])) > 2.0:
			var deadline := int(assignment.get("deadline_tick", int(assignment["order_tick"]) + int(policy.get("scout_interval_ticks", 160)) * 3))
			# Keep a moving scout on its information goal for the estimated trip,
			# instead of replacing a long route every short decision interval.
			if String(actor.get("task", "idle")) == "move" and tick < deadline: continue
			if tick - int(assignment["order_tick"]) < int(policy.get("scout_interval_ticks", 160)): continue
		var best: Variant = null
		var best_score := -INF
		var stride := maxi(1, ceili(float(frontier.size()) / float(int(policy.get("scout_candidate_budget", 64)))))
		for index in range(posmod(int(state.metrics["decisions"]), stride), frontier.size(), stride):
			var point := Vector2(frontier[index])
			var key: String = String(domain) + ":" + str(Vector2i(point) / 8)
			var age := tick - int(state.scout_visits.get(key, -1200))
			var score: float = (
				float(age) * 0.02
				- Vector2(actor.get("pos", Vector2.ZERO)).distance_to(point) * 0.5
				- state.danger(point, int(snapshot.get("tick", 0)), policy, domain) * 6.0
			)
			if score > best_score:
				best = point
				best_score = score
		if best == null:
			continue
		var key: String = String(domain) + ":" + str(Vector2i(best) / 8)
		state.scout_visits[key] = tick
		assignment["target"] = Vector2(best)
		assignment["order_tick"] = tick
		var travel_ticks := ceili(Vector2(actor.get("pos", Vector2.ZERO)).distance_to(Vector2(best)) * 20.0 / maxf(0.2, float(Combat.profile(actor).get("speed", 0.8))))
		assignment["deadline_tick"] = tick + travel_ticks + int(policy.get("scout_interval_ticks", 160))
		result.append(Commands.MoveCommand.new(tick, [int(actor["id"])], Vector2(best)))
	while state.scout_visits.size() > 256:
		var keys: Array = state.scout_visits.keys()
		keys.sort_custom(
			func(a, b):
				return (
					int(state.scout_visits[a]) < int(state.scout_visits[b])
					if int(state.scout_visits[a]) != int(state.scout_visits[b])
					else String(a) < String(b)
				)
		)
		state.scout_visits.erase(keys[0])
	return result


static func _rally(snapshot: Dictionary, team: int, domain: String, home: Vector2) -> Vector2:
	if domain == "water":
		for building in Economy.own(snapshot.get("buildings", []), team):
			if String(building.get("kind", "")) == "dock":
				home = Vector2(building.get("pos", home))
	var points: Array = snapshot.get("navigation", {}).get("reachable", {}).get(
		domain, snapshot.get("navigation", {}).get(domain, [])
	)
	var best := home
	var distance := INF
	for value in points:
		var point := Vector2(value)
		var candidate := point.distance_squared_to(home)
		if candidate < distance:
			best = point
			distance = candidate
	return best


func canonical_state() -> Dictionary:
	var records: Array = []
	var ids: Array = groups.keys()
	ids.sort()
	for id in ids:
		var operation: Dictionary = groups[id]
		records.append(
			{
				"group": operation["group"].canonical_state(),
				"region": String(operation.get("region", operation["group"].movement_domain)),
				"phase": operation["phase"],
				"last_order_tick": operation["last_order_tick"],
				"phase_tick": operation["phase_tick"]
			}
		)
	return {"version": 1, "next_id": next_id, "groups": records, "scouts": scouts.duplicate(true)}


func restore_state(data: Dictionary, team: int) -> bool:
	if (
		int(data.get("version", -1)) != 1
		or not data.get("groups", []) is Array
		or not data.get("scouts", {}) is Dictionary
	):
		return false
	if data.get("groups", []).size() > 8:
		return false
	groups.clear()
	var members: Dictionary = {}
	for entry in data.get("groups", []):
		if not entry is Dictionary or not entry.get("group") is Dictionary:
			return false
		var group = Group.from_state(entry.get("group", {}))
		if int(group.team) != team or int(group.group_id) <= 0 or groups.has(int(group.group_id)):
			return false
		for id in group.member_ids:
			if members.has(int(id)):
				return false
			members[int(id)] = true
		groups[int(group.group_id)] = {
			"group": group,
			"region": String(entry.get("region", group.movement_domain)),
			"phase": String(entry.get("phase", "assembly")),
			"last_order_tick": int(entry.get("last_order_tick", -1)),
			"phase_tick": int(entry.get("phase_tick", 0))
		}
		next_id = maxi(next_id, int(group.group_id) + 1)
	next_id = maxi(next_id, int(data.get("next_id", 1)))
	scouts = data.get("scouts", {}).duplicate(true)
	return true
