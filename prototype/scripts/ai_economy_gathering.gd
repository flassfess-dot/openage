extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const Rules := preload("res://scripts/ai_economy_rules.gd")
const Resources := preload("res://scripts/ai_resource_spatial_index.gd")
const RESOURCE_NAMES := ["food", "wood", "stone", "gold"]
const Common := preload("res://scripts/ai_economy_common.gd")

static func worker_safety(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary) -> Array:
	var result := _protect_workers(snapshot, tick, team, policy, reserved)
	var retreating: Dictionary = state.metrics.get("worker_retreats", {})
	var units := Common.own(snapshot.get("units", []), team)
	var live: Dictionary = {}
	var navigation: Dictionary = snapshot.get("navigation", {})
	var risks: Dictionary = {}
	for worker in units:
		var id := int(worker["id"])
		live[id] = true
		if reserved.has(id) or not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)) or String(worker.get("task", "")) in ["board", "embarked"]: continue
		var domain := String(worker.get("movement_domain", "land"))
		var position := Vector2(worker.get("pos", Vector2.ZERO))
		var danger: float = state.danger(position, int(snapshot.get("tick", 0)), policy, domain)
		if danger <= float(policy.get("maximum_economic_danger", 8.0)):
			if retreating.has(id) and tick < int(retreating[id]["until"]): reserved[id] = true
			else: retreating.erase(id)
			continue
		var points: Array = navigation.get("reachable", {}).get(domain, navigation.get(domain, []))
		var best := position
		var score := INF
		var stride := maxi(1, ceili(float(points.size()) / 128.0))
		for index in range(0, points.size(), stride):
			var point := Vector2(points[index])
			var distance := position.distance_to(point)
			if distance < 3.0 or distance > 24.0: continue
			var risk_key := [domain, point]
			if not risks.has(risk_key): risks[risk_key] = state.danger(point, int(snapshot.get("tick", 0)), policy, domain)
			var risk: float = risks[risk_key]
			if risk >= danger * 0.5: continue
			var value := distance + risk * 12.0
			for building in snapshot.get("buildings", []):
				if int(building.get("team", 0)) == team and bool(building.get("ai_drop_site", false)):
					value += minf(12.0, point.distance_to(Vector2(building.get("pos", point)))) * 0.2
			if value < score:
				best = point
				score = value
		if best == position: continue
		reserved[id] = true
		if not retreating.has(id) or Vector2(retreating[id]["destination"]).distance_to(best) > 3.0 or String(worker.get("task", "")) != "move":
			result.append(Commands.MoveCommand.new(tick, [id], best))
		retreating[id] = {"until": tick + 120, "destination": best}
	for id in retreating.keys():
		if not live.has(id): retreating.erase(id)
	state.metrics["worker_retreats"] = retreating
	return result


static func _protect_workers(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, reserved: Dictionary) -> Array:
	var result: Array = []
	var own := Common.own(snapshot.get("units", []), team)
	var workers: Dictionary = {}
	for unit in own:
		if bool(unit.get("components", {}).get("worker", {}).get("enabled", false)): workers[int(unit["id"])] = unit
	var regions: Dictionary = snapshot.get("navigation", {}).get("unit_regions", {})
	for predator in snapshot.get("units", []):
		if int(predator.get("team", 0)) != 0 or "predator" not in predator.get("behavior_tags", []) or float(predator.get("hp", 0.0)) <= 0.0 or bool(predator.get("last_known", false)): continue
		var victim := int(predator.get("target_id", -1)) if String(predator.get("task", "")) == "attack" else -1
		if not workers.has(victim):
			victim = -1
			var warning := pow(maxf(0.0, float(predator.get("acquisition_range", 3.0))) + 2.0, 2)
			for id in workers:
				if Vector2(workers[id].get("pos", Vector2.ZERO)).distance_squared_to(Vector2(predator.get("pos", Vector2.ZERO))) <= warning:
					victim = int(id)
					break
		if victim < 0: continue
		var defender: Dictionary = {}
		var best := pow(float(policy.get("enemy_response_distance", 22.0)), 2)
		for unit in own:
			var id := int(unit["id"])
			if reserved.has(id) or workers.has(id) or not bool(unit.get("combat_enabled", false)): continue
			if String(unit.get("task", "idle")) == "attack" and int(unit.get("target_id", -1)) != int(predator["id"]): continue
			if String(predator.get("movement_domain", "land")) not in unit.get("target_domains", ["land", "water"]): continue
			if regions.has(id) and regions.has(victim):
				var guard_region := String(regions[id])
				var worker_region := String(regions[victim])
				# Component IDs are comparable only for the same domain,
				# restriction and radius. Soldiers and villagers differ in size.
				if guard_region.rsplit(":", true, 1)[0] == worker_region.rsplit(":", true, 1)[0] and guard_region != worker_region: continue
			var distance := Vector2(unit.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(predator.get("pos", Vector2.ZERO)))
			if distance < best:
				best = distance
				defender = unit
		if defender.is_empty(): continue
		reserved[int(defender["id"])] = true
		if String(defender.get("task", "")) != "attack" or int(defender.get("target_id", -1)) != int(predator["id"]):
			result.append(Commands.AttackCommand.new(tick, [int(defender["id"])], int(predator["id"])))
	return result


static func economic_scout(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary) -> Array:
	if String(state.goal.get("type", "")) == "defend" or not snapshot.get("build_sites", {}).is_empty(): return []
	var buildings := Common.own(snapshot.get("buildings", []), team)
	if buildings.any(func(b): return String(b.get("state", "complete")) == "foundation"): return []
	var priorities: Array = policy.get("construction_priorities", [])
	var essential_missing := ("barracks" in priorities and not buildings.any(func(b): return String(b.get("kind", "")) == "barracks")) or ("granary" in priorities and not buildings.any(func(b): return String(b.get("kind", "")) == "granary")) or ("house" in priorities and Rules.needs_housing(snapshot.get("player_state", {}), int(policy.get("housing_buffer", 2)), false, Rules.active_order_population_points(buildings)))
	if not essential_missing: return []
	var last: Dictionary = state.metrics.get("economic_scout", {})
	if tick < int(last.get("deadline", -1)): return []
	var navigation: Dictionary = snapshot.get("navigation", {})
	var workers: Array = Common.own(snapshot.get("units", []), team).filter(func(w): return bool(w.get("components", {}).get("worker", {}).get("enabled", false)) and String(w.get("movement_domain", "land")) == "land" and String(w.get("task", "")) in ["idle", "gather"] and not reserved.has(int(w["id"])) and float(w.get("ai_profile", {}).get("carried_amount", 0.0)) <= 0.0)
	for worker in workers:
		var id := int(worker["id"])
		var region := String(navigation.get("unit_regions", {}).get(id, "land"))
		var frontier: Array = navigation.get("frontier_by_region", {}).get(region, navigation.get("reachable_frontier", {}).get("land", []))
		var best := Vector2(worker.get("pos", Vector2.ZERO))
		var score := INF
		for index in range(0, frontier.size(), maxi(1, ceili(float(frontier.size()) / 64.0))):
			var point := Vector2(frontier[index])
			var distance := Vector2(worker.get("pos", Vector2.ZERO)).distance_to(point)
			if distance < 2.0 or distance > 18.0: continue
			if state.danger(point, int(snapshot.get("tick", 0)), policy) > 0.0: continue
			var value := distance + (20.0 if point.distance_to(Vector2(last.get("target", Vector2.INF))) < 4.0 else 0.0)
			if value < score:
				best = point
				score = value
		if is_finite(score):
			reserved[id] = true
			state.metrics["economic_scout"] = {"target": best, "deadline": tick + ceili(score * 20.0 / maxf(0.2, float(worker.get("ai_profile", {}).get("speed", 0.8)))) + 80}
			return [Commands.MoveCommand.new(tick, [id], best)]
	return []


static func gather(
	snapshot: Dictionary,
	tick: int,
	team: int,
	policy: Dictionary,
	state,
	reserved: Dictionary,
	timings: Dictionary = {},
	resource_index: Variant = null,
	native_resource_views_enabled: bool = true
) -> Array:
	var started := Time.get_ticks_usec()
	var units := Common.own(snapshot.get("units", []), team)
	var workers: Array = units.filter(
		func(w): return ( bool(w.get("components", {}).get("worker", {}).get("enabled", false)) and String(w.get("task", "idle")) in ["idle", "gather"] and not reserved.has(int(w.get("id", -1))) and float(w.get("ai_profile", {}).get("carried_amount", 0.0)) <= 0.0 and String(w.get("ai_profile", {}).get("gather_stage", "")) != "returning" )
	)
	var resource_view := Common.economy_resources(snapshot.get("resources", []), snapshot.get("buildings", []), team, native_resource_views_enabled)
	var resources: Array = resource_view["resources"]
	var index: Resources = resource_index if resource_index != null else Resources.new()
	index.rebuild(resources, ["land", "water"], false, true)
	var by_id: Dictionary = resource_view["by_id"]
	var saturation: Dictionary = {}
	for worker in units:
		if String(worker.get("task", "")) == "gather":
			var id := int(worker.get("resource_id", -1))
			saturation[id] = int(saturation.get(id, 0)) + 1
	var reachable: Dictionary = snapshot["_economy_reachable_cells"] if snapshot.has("_economy_reachable_cells") else Rules.reachable_cells_by_domain(snapshot.get("navigation", {}), EconomicPlanner.native_reachable_lookup_enabled)
	var drops: Array = Common.own(snapshot.get("buildings", []), team).filter(
		func(b): return bool(b.get("ai_drop_site", false)) and String(b.get("state", "complete")) == "complete"
	)
	var result: Array = []
	var player: Dictionary = snapshot.get("player_state", {})
	# Allocate by resource type as well as by individual node. Otherwise every
	# worker follows the same stock shortage and productive cycles oscillate.
	var type_load: Dictionary = {}
	var weights: Dictionary = {}
	var quotas: Dictionary = {}
	var total_workers := 0
	for unit in units:
		if not bool(unit.get("components", {}).get("worker", {}).get("enabled", false)): continue
		total_workers += 1
		var resource: Dictionary = by_id.get(int(unit.get("resource_id", -1)), {})
		var type_id := int(resource.get("resource_type_id", unit.get("ai_profile", {}).get("carried_resource_type_id", -1)))
		if String(unit.get("task", "")) == "gather" and type_id >= 0: type_load[type_id] = int(type_load.get(type_id, 0)) + 1
	var total_weight := 0.0
	for type_id in range(RESOURCE_NAMES.size()):
		if not resource_view["types"].has(type_id): continue
		if float(policy.get("desired_stock", {}).get(type_id, 0.0)) <= 0.0: continue
		var shortage := maxf(0.0, float(policy.get("desired_stock", {}).get(type_id, 0.0)) - float(player.get(RESOURCE_NAMES[type_id], 0)))
		weights[type_id] = sqrt(maxf(25.0 if type_id in [0, 1] else 1.0, shortage))
		if type_id == 0:
			# A worker-producing town consumes food continuously. Stock-only quotas
			# split a small opening workforce evenly with construction wood and
			# cannot sustain the next worker, even while the town sits idle.
			var land_workers := units.filter(func(u): return bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and String(u.get("movement_domain", "land")) == "land").size()
			weights[type_id] = float(weights[type_id]) + float(maxi(0, int(policy.get("land_worker_target", land_workers)) - land_workers)) * 3.0
		total_weight += float(weights[type_id])
	for type_id in weights: quotas[type_id] = float(total_workers) * float(weights[type_id]) / maxf(1.0, total_weight)
	var count := mini(workers.size(), int(policy.get("worker_search_budget", 32)))
	timings["gather_prepare"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for offset in range(count):
		var worker: Dictionary = workers[posmod(state.gather_cursor + offset, workers.size())]
		var worker_id := int(worker.get("id", -1))
		var current: Dictionary = by_id.get(int(worker.get("resource_id", -1)), {})
		var domain := String(worker.get("movement_domain", "land"))
		var current_type := int(current.get("resource_type_id", -1))
		if not current.is_empty() and int(type_load.get(current_type, 0)) <= float(quotas.get(current_type, 0.0)) + 0.5 and state.danger(Vector2(current.get("pos", Vector2.ZERO)), int(snapshot.get("tick", 0)), policy, domain) <= float(policy.get("maximum_economic_danger", 8.0)): continue
		var best: Dictionary = {}
		var score := -INF
		var current_score := -INF
		for type_id in range(RESOURCE_NAMES.size()):
			var stock := float(player.get(RESOURCE_NAMES[type_id], 0))
			var need := maxf(
				0.0,
				(
					float(policy.get("desired_stock", {}).get(type_id, 0.0))
					- stock
					- float(state.income.get(type_id, 0.0)) * float(policy.get("forecast_seconds", 45.0))
				)
			)
			var candidates: Array = index.candidates(
				Vector2(worker.get("pos", Vector2.ZERO)),
				domain,
				type_id,
				int(policy.get("resource_candidate_budget", 12))
			)
			if (
				int(current.get("resource_type_id", -1)) == type_id
				and not candidates.any(func(r): return int(r.get("id", -1)) == int(current.get("id", -2)))
			):
				candidates.append(current)
			for resource in candidates:
				# The adaptive blacklist owns retry lifetime. A completed order must
				# not permanently veto the resource after its stored failure expires.
				if policy.get("failed_gather_targets", {}).get(worker_id, {}).has(int(resource.get("id", -1))) or not Rules.resource_has_reachable_approach(resource, worker, reachable):
					continue
				var position := Vector2(resource.get("pos", Vector2.ZERO))
				var danger: float = state.danger(position, int(snapshot.get("tick", 0)), policy, domain)
				if danger > float(policy.get("maximum_economic_danger", 8.0)):
					continue
				var drop_distance := INF
				for drop in drops:
					if type_id not in drop.get("ai_drop_resources", [0, 1, 2, 3]):
						continue
					drop_distance = minf(drop_distance, position.distance_to(Vector2(drop.get("pos", Vector2.ZERO))))
				if not is_finite(drop_distance):
					drop_distance = 12.0
				var resource_id := int(resource.get("id", -1))
				var assigned := maxi(
					0, int(saturation.get(resource_id, 0)) - (1 if resource_id == int(current.get("id", -2)) else 0)
				)
				var candidate_score := (
					20.0
					+ minf(200.0, need) * 0.08
					+ (float(quotas.get(type_id, 0.0)) - float(type_load.get(type_id, 0))) * 36.0
					- Vector2(worker.get("pos", Vector2.ZERO)).distance_to(position) * 0.8
					- drop_distance * 0.7
					- float(assigned) * 3.0
					- danger * 8.0
				)
				if resource_id == int(current.get("id", -2)):
					current_score = candidate_score
				if candidate_score > score:
					best = resource
					score = candidate_score
		if best.is_empty() or int(best["id"]) == int(current.get("id", -2)):
			continue
		if not current.is_empty() and score < current_score + float(policy.get("gather_inertia", 12.0)):
			continue
		if not current.is_empty():
			saturation[int(current["id"])] = maxi(0, int(saturation.get(int(current["id"]), 0)) - 1)
		saturation[int(best["id"])] = int(saturation.get(int(best["id"]), 0)) + 1
		var command = Commands.GatherCommand.new(tick, [worker_id], int(best["id"]))
		command.params["_ai_feedback"] = {"key": "gather:%d:%d" % [worker_id, int(best["id"])], "cost": {}}
		if not state.cooldowns.has(command.params["_ai_feedback"]["key"]):
			result.append(command)
			if current_type >= 0: type_load[current_type] = maxi(0, int(type_load.get(current_type, 0)) - 1)
			var selected_type := int(best.get("resource_type_id", -1))
			type_load[selected_type] = int(type_load.get(selected_type, 0)) + 1
			reserved[worker_id] = true
		if result.size() >= int(policy.get("gather_command_budget", 8)):
			break
	state.gather_cursor += maxi(1, count)
	timings["gather_choices"] = Time.get_ticks_usec() - started
	return result
