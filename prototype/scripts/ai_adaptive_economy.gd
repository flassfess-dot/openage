class_name RoRAiAdaptiveEconomy
extends RefCounted
const Commands := preload("res://scripts/commands.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const Rules := preload("res://scripts/ai_economy_rules.gd")
const Combat := preload("res://scripts/ai_combat_model.gd")
const Resources := preload("res://scripts/ai_resource_spatial_index.gd")
const RESOURCE_NAMES := ["food", "wood", "stone", "gold"]
static var memoized_production_enabled := true
static var memoized_site_checks_enabled := true
static var native_resource_views_enabled := true


static func _economy_resources(resources: Array, buildings: Array, team: int, native: bool = true) -> Dictionary:
	if native and ClassDB.class_exists("RoRReadModelKernel"):
		var kernel = ClassDB.instantiate("RoRReadModelKernel")
		if kernel.has_method("economy_resource_view"):
			return kernel.economy_resource_view(resources, buildings, team)
	var active: Array = resources.filter(func(r): return int(r.get("amount", 0)) > 0)
	for building in buildings:
		if int(building.get("team", 0)) == team and bool(building.get("harvestable", false)) and int(building.get("amount", 0)) > 0:
			active.append(building)
	var by_id: Dictionary = {}
	var types: Dictionary = {}
	for row in active:
		by_id[int(row.get("id", -1))] = row
		types[int(row.get("resource_type_id", -1))] = true
	return {"resources":active,"by_id":by_id,"types":types}


static func own(rows: Array, team: int) -> Array:
	var result: Array = rows.filter(func(e): return int(e.get("team", 0)) == team and float(e.get("hp", 0.0)) > 0.0)
	result.sort_custom(func(a, b): return int(a.get("id", -1)) < int(b.get("id", -1)))
	return result


static func policy_for(snapshot: Dictionary, team: int, base: Dictionary, state) -> Dictionary:
	var policy := base.duplicate(true)
	var player: Dictionary = snapshot.get("player_state", {})
	var units := own(snapshot.get("units", []), team)
	var buildings := own(snapshot.get("buildings", []), team)
	var workers: Array = units.filter(
		func(e): return ( bool(e.get("components", {}).get("worker", {}).get("enabled", false)) and String(e.get("movement_domain", "land")) == "land" )
	)
	var cap := maxi(1, int(player.get("population_limit", 50)))
	var age := int(player.get("age", 100))
	var target := mini(
		int(base.get("maximum_workers", 90)),
		maxi(
			int(base.get("land_worker_target", 8)),
			roundi(float(cap) * float(base.get("worker_population_ratio", 0.45)))
		)
	)
	var army_count := _army_count(units)
	var producers := buildings.filter(func(b): return String(b.get("kind", "")) in ["barracks", "archery_range", "stable", "siege_workshop"]).size()
	# Grow towards the production capacity we actually need to feed. Large
	# population limits may support more than forty workers in later economies.
	policy["land_worker_target"] = mini(target, maxi(int(base.get("land_worker_target", 8)), 12 + maxi(0, age - 100) * 8 + producers * 4))
	policy["minimum_workers_before_age_up"] = maxi(int(base.get("minimum_workers_before_age_up", 6)), mini(int(policy["land_worker_target"]), int(base.get("land_worker_target", 8)) + 4 + maxi(0, age - 100) * 4))
	policy["army_target"] = mini(maxi(3, cap - int(policy["land_worker_target"]) - 2), maxi(6 + maxi(0, age - 100) * 8, ceili(float(state.enemies(int(snapshot.get("tick", 0)), base).filter(func(e): return bool(e.get("combat_enabled", false)) and not bool(e.get("components", {}).get("worker", {}).get("enabled", false))).size()) * 1.5)))
	policy["water_worker_target"] = mini(8, maxi(int(base.get("water_worker_target", 2)), workers.size() / 6))
	var limits: Dictionary = policy.get("building_limits", {}).duplicate()
	limits["house"] = maxi(int(limits.get("house", 4)), ceili(float(cap) / 4.0))
	var known_food := 0
	var travel := 0.0
	var gatherers := 0
	var by_id: Dictionary = {}
	var bases: Array = buildings.filter(func(b): return bool(b.get("ai_drop_site", false)))
	for resource in snapshot.get("resources", []):
		by_id[int(resource.get("id", -1))] = resource
		# Food coverage never needs distances to known trees, stone or gold.
		# Keep every resource in the worker lookup, but score only usable food.
		if int(resource.get("resource_type_id", -1)) != 0 or not Rules.resource_allows_worker(resource, {"movement_domain": "land"}): continue
		var near_base := bases.is_empty()
		for base_building in bases:
			if Vector2(base_building.get("pos", Vector2.ZERO)).distance_to(Vector2(resource.get("pos", Vector2.ZERO))) <= 18.0:
				near_base = true
				break
		if near_base:
			known_food += maxi(0, int(resource.get("amount", 0)))
	for worker in workers:
		var resource: Dictionary = by_id.get(int(worker.get("resource_id", -1)), {})
		if resource.is_empty():
			continue
		var nearest := INF
		for building in buildings:
			if bool(building.get("ai_drop_site", false)):
				nearest = minf(
					nearest,
					Vector2(resource.get("pos", Vector2.ZERO)).distance_to(Vector2(building.get("pos", Vector2.ZERO)))
				)
		if is_finite(nearest):
			travel += nearest
			gatherers += 1
	limits["farm"] = (
		mini(int(base.get("maximum_farms", 12)), maxi(0, ceili(float(workers.size()) * 0.45)))
		if known_food < workers.size() * 120
		else 0
	)
	limits["town_center"] = mini(int(base.get("maximum_bases", 3)), 1 + workers.size() / 24) if age >= 102 else 1
	if gatherers > 0 and travel / float(gatherers) > 8.0:
		limits["storage_pit"] = mini(3, 1 + workers.size() / 12)
		limits["granary"] = mini(3, 1 + workers.size() / 12)
	for kind in ["barracks", "archery_range", "stable", "siege_workshop", "dock"]:
		var matching: Array = buildings.filter(func(b): return String(b.get("kind", "")) == kind)
		if (
			not matching.is_empty()
			and matching.all(func(b): return not b.get("production_queue", []).is_empty())
			and workers.size() >= 16
			and int(player.get("wood", 0)) >= 250
		):
			limits[kind] = mini(3, maxi(int(limits.get(kind, 1)), matching.size() + 1))
	var primary := "barracks" if age <= 100 else "archery_range"
	var enemies: Array = state.enemies(int(snapshot.get("tick", 0)), base)
	var ranged := enemies.filter(func(e): return float(Combat.profile(e).get("range", 0.0)) > 2.0).size()
	if age >= 101 and ranged > enemies.size() / 2: primary = "stable"
	var buildable: Dictionary = {}
	for worker in workers.slice(0, 1):
		for option in worker.get("command_options", {}).get("build", []):
			if String(option.get("reason", "")) != "building_unavailable": buildable[String(option.get("kind", ""))] = true
	if not buildable.is_empty() and not buildable.has(primary):
		primary = "archery_range" if buildable.has("archery_range") else "barracks"
	policy["primary_producer"] = primary
	for kind in ["archery_range", "stable"]:
		if kind != primary and army_count < 12: limits[kind] = 0
	limits["siege_workshop"] = int(limits.get("siege_workshop", 1)) if age >= 102 and army_count >= 6 and enemies.any(func(e): return String(e.get("entity_type", "")) == "building") else 0
	limits["temple"] = int(limits.get("temple", 1)) if army_count >= 10 else 0
	var naval_demand: bool = bool(state.goal.get("needs_transport", false)) or String(state.goal.get("target_domain", "")) == "water" or snapshot.get("resources", []).any(func(r): return int(r.get("resource_type_id", -1)) == 0 and "water" in r.get("allowed_gatherer_domains", []))
	if not naval_demand: limits["dock"] = 0
	policy["building_limits"] = limits
	var priorities: Array = policy.get("construction_priorities", []).duplicate()
	priorities.erase(primary)
	priorities.insert(mini(1, priorities.size()), primary)
	if limits["farm"] > 0:
		priorities.erase("farm")
		priorities.insert(mini(3, priorities.size()), "farm")
	if not buildings.any(func(b): return String(b.get("kind", "")) == "town_center"):
		priorities.erase("town_center")
		priorities.push_front("town_center")
	policy["construction_priorities"] = priorities
	policy["desired_stock"] = forecast(snapshot, units, buildings, policy, state)
	return policy


static func _army_count(units: Array) -> int:
	return units.filter(func(u): return (bool(u.get("combat_enabled", false)) or "combatant" in u.get("behavior_tags", [])) and not bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and "worker" not in u.get("behavior_tags", []) and not bool(u.get("ai_profile", {}).get("transport", false))).size()


static func _next_training_food(buildings: Array, worker: bool) -> int:
	var minimum := 2147483647
	for building in buildings:
		if worker and String(building.get("kind", "")) != "town_center": continue
		for option in building.get("command_options", {}).get("train", []):
			var tags: Array = option.get("behavior_tags", [])
			if ("worker" in tags) != worker or (not worker and "combatant" not in tags): continue
			var cost: Dictionary = option.get("cost", {})
			minimum = mini(minimum, int(cost.get(0, cost.get("0", 0))))
	return 50 if minimum == 2147483647 else minimum


static func forecast(snapshot: Dictionary, units: Array, buildings: Array, policy: Dictionary, state) -> Dictionary:
	var horizon := float(policy.get("forecast_seconds", 45.0))
	var desired := {0: 120.0, 1: 120.0, 2: 0.0, 3: 0.0}
	for building in buildings:
		var train: Array = building.get("command_options", {}).get("train", [])
		var candidate := _preferred_train(train, units, snapshot, policy, state, String(building.get("kind", "")))
		if not candidate.is_empty():
			var repeats := clampf(horizon / maxf(5.0, float(candidate.get("duration", 30.0))), 1.0, 3.0)
			for key in candidate.get("cost", {}):
				desired[int(key)] = float(desired.get(int(key), 0.0)) + float(candidate["cost"][key]) * repeats
	var workers := (
		units
		. filter(
			func(u): return ( bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and String(u.get("movement_domain", "land")) == "land" )
		)
		. size()
	)
	var age := _age_intent(buildings, snapshot.get("player_state", {}), policy, workers, int(snapshot.get("tick", 0)))
	for key in age.get("cost", {}):
		desired[int(key)] = maxf(float(desired.get(int(key), 0.0)), float(age["cost"][key]) + 80.0)
	# Known next infrastructure contributes demand even before it is affordable.
	for worker in units:
		if not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)):
			continue
		var planned := 0
		for kind in policy.get("construction_priorities", []):
			if (
				buildings.filter(func(b): return String(b.get("kind", "")) == String(kind)).size()
				>= int(policy.get("building_limits", {}).get(kind, 1))
			):
				continue
			for option in worker.get("command_options", {}).get("build", []):
				if String(option.get("kind", "")) != String(kind):
					continue
				for key in option.get("cost", {}):
					desired[int(key)] = float(desired.get(int(key), 0.0)) + float(option["cost"][key])
				planned += 1
			if planned >= 2:
				break
		break
	return desired


static func site_kinds(kinds: Array, snapshot: Dictionary, team: int, base: Dictionary, state) -> Array:
	var policy := policy_for(snapshot, team, base, state)
	var buildings := own(snapshot.get("buildings", []), team)
	var foundations: Array = buildings.filter(func(b): return String(b.get("state", "complete")) == "foundation")
	if foundations.size() >= int(policy.get("maximum_foundations", 2)):
		return []
	var complete: Array = buildings.filter(func(b): return String(b.get("state", "complete")) != "foundation")
	# Existing foundations count towards limits, but do not block unrelated work.
	for foundation in foundations:
		var kind := String(foundation.get("kind", ""))
		policy["building_limits"][kind] = maxi(0, int(policy["building_limits"].get(kind, 1)) - 1)
	# The adaptive budget decides age spending. The legacy site filter must not
	# suppress emergency housing or producers just because an age is affordable.
	policy["minimum_workers_before_age_up"] = 0
	var demanded: Array = EconomicPlanner.construction_site_kinds(
		kinds,
		snapshot.get("units", []),
		complete,
		snapshot.get("player_state", {}),
		team,
		policy,
		snapshot.get("navigation", {})
	)
	return demanded.slice(0, 4)


static func plan(
	snapshot: Dictionary, tick: int, team: int, base: Dictionary, state, budget, reserved: Dictionary, timings: Dictionary = {}, resource_index: Variant = null
) -> Array:
	var started := Time.get_ticks_usec()
	var policy := policy_for(snapshot, team, base, state)
	timings["policy"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var units := own(snapshot.get("units", []), team)
	var structures := own(snapshot.get("buildings", []), team)
	var buildings: Array = structures.filter(func(b): return String(b.get("state", "complete")) == "complete")
	var workers: Array = units.filter(
		func(u): return ( bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and String(u.get("movement_domain", "land")) == "land" )
	)
	var result: Array = []
	result.append_array(_worker_safety(snapshot, tick, team, policy, state, reserved))
	# A completed build/move can leave a villager idle with its previous cargo.
	# Active returns keep their route; idle cargo uses the public deposit order.
	for worker in units:
		var worker_id := int(worker.get("id", -1))
		if reserved.has(worker_id) or not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)):
			continue
		if String(worker.get("task", "")) in ["idle", "hold"] and float(worker.get("ai_profile", {}).get("carried_amount", 0.0)) > 0.0:
			_offer(result, Commands.ReturnResourcesCommand.new(tick, [worker_id]), {}, 0, -1, true, state, budget, reserved)
	var age := _age_intent(buildings, snapshot.get("player_state", {}), policy, workers.size(), tick)
	var defending := String(state.goal.get("type", "")) == "defend"
	var minimum_army := int(policy.get("minimum_attack_group_size", 3))
	var army_count := _army_count(units)
	var operating_food := (_next_training_food(buildings, true) if workers.size() < int(policy["land_worker_target"]) else 0) + (_next_training_food(buildings, false) if army_count < minimum_army else 0)
	var age_affordable := age.has("command") and not defending and army_count >= minimum_army
	for resource in age.get("cost", {}):
		var floor_stock := operating_food if int(resource) == 0 else 0
		if int(budget.remaining.get(int(resource), 0)) < int(age["cost"][resource]) + floor_stock: age_affordable = false
	if age_affordable:
		var command = age["command"]
		var producer_id := int(command.unit_ids[0])
		for building in buildings:
			if int(building.get("id", -1)) != producer_id:
				continue
			for option in building.get("command_options", {}).get("research", []):
				if (
					String.num_int64(int(option.get("technology_id", -1)))
					== String(command.params.get("technology", ""))
				):
					_offer(result, command, option.get("cost", {}), 0, producer_id, true, state, budget, reserved)
	elif not defending and (bool(age.get("block_construction", false)) or age.has("command")):
		var reserve: Dictionary = {}
		for resource in age.get("cost", {}):
			var floor_stock := operating_food if int(resource) == 0 else 0
			reserve[int(resource)] = maxi(0, mini(int(age["cost"][resource]), int(budget.remaining.get(int(resource), 0)) - floor_stock))
		budget.protect(reserve)
	policy["saving_age"] = not budget.protected.is_empty()
	policy["defending"] = defending
	policy["army_priority"] = workers.size() >= 8 and army_count < minimum_army
	var foundations: Array = structures.filter(func(b): return String(b.get("state", "complete")) == "foundation")
	for foundation in foundations.slice(0, int(policy.get("maximum_foundations", 2))):
		if (
			int(foundation.get("builder_count", 0)) > 0
			or units.any(
				func(u): return ( String(u.get("task", "")) == "build" and int(u.get("target_building_id", -1)) == int(foundation.get("id", -2)) )
			)
		):
			continue
		var eligible: Array = workers.filter(
			func(w): return ( not reserved.has(int(w.get("id", -1))) and String(w.get("task", "idle")) in ["idle", "gather"] and int(w.get("id", -1)) in foundation.get("reachable_builder_ids", []) )
		)
		eligible.sort_custom(func(a, b): return Rules.foundation_builder_precedes(a, b, foundation))
		if not eligible.is_empty():
			_offer(
				result,
				Commands.BuildCommand.new(
					tick, [int(eligible[0]["id"])], String(foundation["kind"]), Vector2(foundation["pos"])
				),
				{},
				0,
				-1,
				true,
				state,
				budget,
				reserved
			)
	# Housing and recovery precede military spending. Other infrastructure follows
	# production so a new building cannot starve a working town center.
	_construct(
		snapshot,
		tick,
		team,
		policy,
		state,
		budget,
		reserved,
		result,
		(
			["house", "town_center"]
			if not buildings.any(func(b): return String(b.get("kind", "")) == "town_center")
			else ["house"]
		)
	)
	var effective_units: Array = units.duplicate()
	var production_choices: Dictionary = {}
	var effective_version := 0
	for building in buildings:
		for order in building.get("production_queue", []):
			if String(order.get("order_type", "unit")) == "unit":
				var option: Dictionary = {}
				for candidate in building.get("command_options", {}).get("train", []):
					if candidate.get("kind") == order.get("kind"): option = candidate
				effective_units.append({"kind": order.get("kind", ""), "behavior_tags": option.get("behavior_tags", ["worker"] if String(order.get("kind", "")) in ["villager", "fishing_boat"] else ["combatant"]), "ai_profile": option.get("ai_profile", {})})
	buildings.sort_custom(func(a, b):
		var a_rank := _producer_rank(String(a.get("kind", "")), policy, workers.size())
		var b_rank := _producer_rank(String(b.get("kind", "")), policy, workers.size())
		return a_rank < b_rank if a_rank != b_rank else int(a["id"]) < int(b["id"]))
	for building in buildings:
		var id := int(building.get("id", -1))
		var queue: Array = building.get("production_queue", [])
		if budget.producer_orders.has(id) or queue.size() >= int(policy.get("maximum_production_queue", 2)) or queue.any(func(o): return String(o.get("order_type", "unit")) != "unit" or String(o.get("status", "")) == "blocked_population"):
			continue
		var options: Dictionary = building.get("command_options", {})
		var essential_worker := workers.size() < int(policy["minimum_workers_before_age_up"])
		var train_options: Array = options.get("train", []).filter(func(o): return bool(o.get("accepted", false)) and budget.can_reserve(o.get("cost", {}), int(o.get("population_points_cost", int(o.get("population_cost", 1)) * 2)), id, essential_worker and "worker" in o.get("behavior_tags", [])))
		var producer_kind := String(building.get("kind", ""))
		# A plan sees one fixed enemy sample and policy. Unit counts change only
		# when an accepted offer extends effective_units below.
		var choice_key := [producer_kind, effective_version, train_options]
		var selected: Dictionary
		if memoized_production_enabled and production_choices.has(choice_key):
			selected = production_choices[choice_key]
		else:
			selected = _preferred_train(train_options, effective_units, snapshot, policy, state, producer_kind)
			if memoized_production_enabled: production_choices[choice_key] = selected
		var technology := _preferred_research(options.get("research", []).filter(func(o): return budget.can_reserve(o.get("cost", {}), 0, id)), units, policy, state)
		var worker_option: bool = "worker" in selected.get("behavior_tags", [])
		if (
			not technology.is_empty()
			and not worker_option
			and building.get("production_queue", []).is_empty()
			and (
				selected.is_empty()
				or (
					float(technology.get("ai_score", 0.0))
					> float(selected.get("ai_score", 0.0)) * float(policy.get("research_priority", 1.1))
				)
			)
		):
			_offer(
				result,
				Commands.ResearchCommand.new(tick, [id], String.num_int64(int(technology["technology_id"]))),
				technology.get("cost", {}),
				0,
				id,
				false,
				state,
				budget,
				reserved
			)
		elif not selected.is_empty():
			var essential: bool = (
				worker_option
				and (
					essential_worker
					or workers.size() < int(policy["land_worker_target"]) / 2
				)
			)
			if _offer(
				result,
				Commands.TrainCommand.new(
					tick,
					[id],
					String(selected["kind"]),
					team,
					Vector2(building.get("rally_point", building.get("pos", Vector2.ZERO)))
				),
				selected.get("cost", {}),
				int(selected.get("population_points_cost", int(selected.get("population_cost", 1)) * 2)),
				id,
				essential,
				state,
				budget,
				reserved
			):
				effective_units.append({"kind": selected["kind"], "behavior_tags": selected.get("behavior_tags", [])})
				effective_version += 1
	_construct(
		snapshot,
		tick,
		team,
		policy,
		state,
		budget,
		reserved,
		result,
		policy.get("construction_priorities", []).filter(func(k): return k != "house")
	)
	result.append_array(Rules.plan_idle_trade(snapshot, tick, team, units, buildings))
	timings["production"] = Time.get_ticks_usec() - started
	result.append_array(_economic_scout(snapshot, tick, team, policy, state, reserved))
	result.append_array(_gather(snapshot, tick, team, policy, state, reserved, timings, resource_index))
	state.metrics["budget_rejections"] += budget.rejected
	state.metrics["economy_plan"] = {
		"worker_target": int(policy["land_worker_target"]),
		"army_target": int(policy["army_target"]),
		"primary_producer": String(policy["primary_producer"]),
		"desired_stock": policy["desired_stock"].duplicate(true),
		"remaining_budget": budget.remaining.duplicate(true)
	}
	return result


static func _producer_rank(kind: String, policy: Dictionary, workers: int) -> int:
	if kind == "town_center": return 0 if (not bool(policy.get("defending", false)) and not bool(policy.get("army_priority", false))) or workers < 6 else 2
	return 1 if kind == String(policy.get("primary_producer", "barracks")) else 3


static func _worker_safety(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary) -> Array:
	var result: Array = []
	var retreating: Dictionary = state.metrics.get("worker_retreats", {})
	var units := own(snapshot.get("units", []), team)
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


static func _economic_scout(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary) -> Array:
	if String(state.goal.get("type", "")) == "defend" or not snapshot.get("build_sites", {}).is_empty(): return []
	var buildings := own(snapshot.get("buildings", []), team)
	if buildings.any(func(b): return String(b.get("state", "complete")) == "foundation"): return []
	var priorities: Array = policy.get("construction_priorities", [])
	var essential_missing := ("barracks" in priorities and not buildings.any(func(b): return String(b.get("kind", "")) == "barracks")) or ("granary" in priorities and not buildings.any(func(b): return String(b.get("kind", "")) == "granary")) or ("house" in priorities and Rules.needs_housing(snapshot.get("player_state", {}), int(policy.get("housing_buffer", 2)), false, Rules.active_order_population_points(buildings)))
	if not essential_missing: return []
	var last: Dictionary = state.metrics.get("economic_scout", {})
	if tick < int(last.get("deadline", -1)): return []
	var navigation: Dictionary = snapshot.get("navigation", {})
	var workers: Array = own(snapshot.get("units", []), team).filter(func(w): return bool(w.get("components", {}).get("worker", {}).get("enabled", false)) and String(w.get("movement_domain", "land")) == "land" and String(w.get("task", "")) in ["idle", "gather"] and not reserved.has(int(w["id"])) and float(w.get("ai_profile", {}).get("carried_amount", 0.0)) <= 0.0)
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


static func _offer(
	result: Array,
	command,
	cost: Dictionary,
	points: int,
	producer: int,
	essential: bool,
	state,
	budget,
	reserved: Dictionary
) -> bool:
	var key := String(command.command_type()) + ":" + str(command.unit_ids) + ":" + str(command.params)
	if state.cooldowns.has(key):
		return false
	if not budget.reserve(cost, points, producer, essential):
		return false
	command.params["_ai_feedback"] = {"key": key, "cost": cost.duplicate(true)}
	if String(command.command_type()) == "build" and not cost.is_empty():
		command.params["_ai_feedback"]["site_key"] = _site_key(String(command.params.get("building_type", "")), Vector2(command.params.get("target", Vector2.ZERO)))
	result.append(command)
	for id in command.unit_ids:
		reserved[int(id)] = true
	return true


static func _construct(
	snapshot: Dictionary,
	tick: int,
	team: int,
	policy: Dictionary,
	state,
	budget,
	reserved: Dictionary,
	result: Array,
	requested: Array
) -> void:
	var structures := own(snapshot.get("buildings", []), team)
	var pending := structures.filter(func(b): return String(b.get("state", "complete")) == "foundation").size()
	pending += (
		result
		. filter(
			func(c): return ( String(c.command_type()) == "build" and not c.params.get("_ai_feedback", {}).get("cost", {}).is_empty() )
		)
		. size()
	)
	if pending >= int(policy.get("maximum_foundations", 2)):
		return
	var workers: Array = own(snapshot.get("units", []), team).filter(
		func(w): return ( bool(w.get("components", {}).get("worker", {}).get("enabled", false)) and String(w.get("movement_domain", "land")) == "land" and String(w.get("task", "idle")) in ["idle", "gather"] and not reserved.has(int(w.get("id", -1))) )
	)
	for kind_value in requested:
		var kind := String(kind_value)
		if (
			structures.filter(func(b): return String(b.get("kind", "")) == kind).size()
			>= int(policy.get("building_limits", {}).get(kind, 1))
		):
			continue
		if result.any(
			func(c): return String(c.command_type()) == "build" and String(c.params.get("building_type", "")) == kind
		):
			continue
		if (
			kind == "house"
			and not Rules.needs_housing(
				snapshot.get("player_state", {}),
				int(policy.get("housing_buffer", 2)),
				int(snapshot.get("player_state", {}).get("blocked_population_queues", 0)) > 0,
				Rules.active_order_population_points(structures)
			)
		):
			continue
		var best: Dictionary = {}
		var best_score := INF
		var site_values: Dictionary = {}
		var site_risks: Dictionary = {}
		var site_gaps: Dictionary = {}
		for worker in workers.slice(0, int(policy.get("worker_search_budget", 32))):
			var option: Dictionary = {}
			var gap_radius := 1.0
			var radius_ready := false
			for entry in worker.get("command_options", {}).get("build", []):
				if not radius_ready and String(entry.get("kind", "")) == kind:
					gap_radius = maxf(0.5, float(entry.get("footprint_radius", 1.0)))
					radius_ready = true
				if String(entry.get("kind", "")) == kind and bool(entry.get("accepted", false)):
					option = entry
			if option.is_empty():
				continue
			for site_value in snapshot.get("build_sites", {}).get(kind, []):
				var site := Vector2(site_value)
				var gap_penalty := 0.0
				if state.cooldowns.has(_site_key(kind, site)):
					continue
				var candidate_key := "build:" + str([int(worker["id"])]) + ":" + str(Commands.BuildCommand.new(tick, [int(worker["id"])], kind, site).params)
				if state.cooldowns.has(candidate_key):
					continue
				if not memoized_site_checks_enabled or not site_risks.has(site):
					site_risks[site] = state.danger(site, int(snapshot.get("tick", 0)), policy)
				var risk: float = site_risks[site]
				if risk > float(policy.get("maximum_economic_danger", 8.0)):
					continue
				if kind not in policy.get("structure_gap_fallback_kinds", []):
					var gap_key := [site, gap_radius]
					if not memoized_site_checks_enabled or not site_gaps.has(gap_key):
						site_gaps[gap_key] = Rules.site_preserves_structure_gap(site, kind, worker, structures, float(policy.get("minimum_structure_gap", 1.0)))
					# Search appends legal tight sites after the spacious candidates.
					# Prefer the requested gap, but do not deadlock a crowded town.
					if not bool(site_gaps[gap_key]): gap_penalty = 1000.0
				var score := Vector2(worker.get("pos", Vector2.ZERO)).distance_to(site) + risk * 4.0 + gap_penalty
				if not site_values.has(site):
					if kind in ["granary", "storage_pit", "town_center"]:
						site_values = _site_resource_bonuses(snapshot.get("resources",[]),snapshot.get("build_sites",{}).get(kind,[]),kind)
					else: site_values[site] = 0.0
				score += float(site_values[site])
				if score < best_score:
					best_score = score
					best = {"worker": worker, "site": site, "option": option}
		if best.is_empty():
			continue
		var essential: bool = kind in ["house", "town_center", "farm", "granary", "storage_pit"]
		if _offer(
			result,
			Commands.BuildCommand.new(tick, [int(best["worker"]["id"])], kind, best["site"]),
			best["option"].get("cost", {}),
			0,
			-1,
			essential,
			state,
			budget,
			reserved
		):
			return


static func _site_key(kind: String, site: Vector2) -> String:
	return "build-site:%s:%s" % [kind, str(site)]


static func _preferred_train(
	options: Array, units: Array, snapshot: Dictionary, policy: Dictionary, state, producer_kind: String
) -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	var enemies: Array = state.enemies(int(snapshot.get("tick", 0)), policy, true).slice(
		0, int(policy.get("combat_sample_budget", 32))
	)
	for option in options:
		var kind := String(option.get("kind", ""))
		var tags: Array = option.get("behavior_tags", [])
		var count := units.filter(func(u): return String(u.get("kind", "")) == kind).size()
		var score := -INF
		if "worker" in tags:
			var water := kind == "fishing_boat"
			var target := int(policy.get("water_worker_target" if water else "land_worker_target", 8))
			if bool(policy.get("defending", false)) and _army_count(units) < int(policy.get("minimum_attack_group_size", 3)) and not water:
				target = mini(target, int(policy.get("minimum_workers_before_age_up", 6)))
			if count < target:
				score = 100.0 + float(target - count) * 2.0
		elif "transport" in tags or bool(option.get("ai_profile", {}).get("transport", false)):
			if (
				count < 1
				and String(state.goal.get("type", "")) == "attack"
				and bool(state.goal.get("needs_transport", false))
			):
				score = 90.0
		elif "trader" in tags:
			if (
				count < 1
				and snapshot.get("buildings", []).any(
					func(b): return ( String(b.get("kind", "")) == "dock" and int(b.get("team", 0)) != int(snapshot.get("observer_team", 0)) and not bool(b.get("last_known", false)) )
				)
			):
				score = 20.0
		elif "healer" in tags or "converter" in tags or kind == "priest":
			var army_size := (
				units
				. filter(
					func(u): return "combatant" in u.get("behavior_tags", []) or bool(u.get("combat_enabled", false))
				)
				. size()
			)
			if count < mini(5, maxi(1, army_size / 10)):
				score = 45.0 + float(army_size) * 0.5
		elif "combatant" in tags or bool(option.get("ai_profile", {}).get("enabled", false)):
			var army_target := int(policy.get("army_target", 9999))
			if bool(policy.get("saving_age", false)): army_target = mini(army_target, int(policy.get("minimum_attack_group_size", 3)))
			if _army_count(units) >= army_target: continue
			var candidate := {
				"kind": kind,
				"hp": option.get("ai_profile", {}).get("max_hp", 1.0),
				"ai_profile": option.get("ai_profile", {}),
				"combat_enabled": true
			}
			var total_cost := 0.0
			for value in option.get("cost", {}).values():
				total_cost += maxf(0.0, float(value))
			score = Combat.counter_score(candidate, enemies, units) * 200.0 / maxf(30.0, total_cost)
			if String(state.goal.get("type", "")) == "defend":
				score *= 2.0
			if producer_kind == "dock" and count < int(policy.get("minimum_naval_escort", 2)):
				score += 40.0
			if enemies.is_empty() and count == 0:
				score += (
					float(option.get("ai_profile", {}).get("speed", 0.0)) * float(policy.get("scout_priority", 4.0))
				)
		if score > best_score:
			best = option.duplicate()
			best["ai_score"] = score
			best_score = score
	return best


static func _preferred_research(options: Array, units: Array, policy: Dictionary, state) -> Dictionary:
	var best: Dictionary = {}
	var score := 0.0
	for option in options:
		if (
			not bool(option.get("accepted", false))
			or int(option.get("technology_id", -1)) in policy.get("age_advance_technology_ids", [])
		):
			continue
		var relevance := float(option.get("ai_relevance", 0.0))
		if bool(option.get("ai_economic", false)):
			relevance *= float(policy.get("economic_research_priority", 1.4))
		if String(state.goal.get("type", "")) == "defend" and not bool(option.get("ai_economic", false)):
			relevance *= 1.5
		var total_cost := 0.0
		for value in option.get("cost", {}).values():
			total_cost += maxf(0.0, float(value))
		var candidate_score := relevance * 100.0 / maxf(50.0, total_cost)
		if candidate_score > score:
			best = option.duplicate()
			best["ai_score"] = candidate_score
			score = candidate_score
	return best


static func _gather(
	snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary, timings: Dictionary = {}, resource_index: Variant = null
) -> Array:
	var started := Time.get_ticks_usec()
	var units := own(snapshot.get("units", []), team)
	var workers: Array = units.filter(
		func(w): return ( bool(w.get("components", {}).get("worker", {}).get("enabled", false)) and String(w.get("task", "idle")) in ["idle", "gather"] and not reserved.has(int(w.get("id", -1))) and float(w.get("ai_profile", {}).get("carried_amount", 0.0)) <= 0.0 and String(w.get("ai_profile", {}).get("gather_stage", "")) != "returning" )
	)
	var resource_view := _economy_resources(snapshot.get("resources", []), snapshot.get("buildings", []), team, native_resource_views_enabled)
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
	var drops: Array = own(snapshot.get("buildings", []), team).filter(
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


static func _age_intent(
	buildings: Array, player: Dictionary, policy: Dictionary, workers: int, tick: int
) -> Dictionary:
	if workers < int(policy.get("minimum_workers_before_age_up", 6)):
		return {}
	var ids: Array = policy.get("age_advance_technology_ids", []).duplicate()
	ids.sort()
	var target := -1
	for id in ids:
		if int(id) > int(player.get("age", 100)):
			target = int(id)
			break
	if target < 0:
		return {}
	for building in buildings:
		if building.get("production_queue", []).any(func(o): return String(o.get("order_type", "")) == "research"):
			continue
		for option in building.get("command_options", {}).get("research", []):
			if int(option.get("technology_id", -1)) != target:
				continue
			if bool(option.get("accepted", false)):
				return {
					"command": Commands.ResearchCommand.new(tick, [int(building["id"])], String.num_int64(target)),
					"cost": option.get("cost", {}),
					"saving": false
				}
			if String(option.get("reason", "")) in ["insufficient_resources", "missing_prerequisites"]:
				return {
					"saving": true,
					"block_construction": String(option["reason"]) == "insufficient_resources",
					"cost": option.get("cost", {}).duplicate(true)
				}
	return {}

static var native_site_scores_enabled := true
static var native_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
static func _site_resource_bonuses(resources: Array, sites: Array, kind: String, use_native: bool = true) -> Dictionary:
	if use_native and native_site_scores_enabled and native_kernel != null and native_kernel.has_method("infrastructure_site_bonuses"):
		return native_kernel.infrastructure_site_bonuses(resources,sites,kind)
	var result: Dictionary = {}
	for value in sites:
		var site := Vector2(value)
		var distance := INF
		for resource in resources:
			if int(resource.get("amount",0)) <= 0 or not Rules.resource_allows_worker(resource,{"movement_domain":"land"}): continue
			if kind == "granary" and int(resource.get("resource_type_id",-1)) != 0: continue
			if kind == "storage_pit" and int(resource.get("resource_type_id",-1)) == 0: continue
			distance = minf(distance,site.distance_to(Vector2(resource.get("pos",Vector2.ZERO))))
		result[site] = distance*2.0 if is_finite(distance) else 0.0
	return result
