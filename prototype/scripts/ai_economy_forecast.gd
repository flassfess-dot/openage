extends RefCounted

const Rules := preload("res://scripts/ai_economy_rules.gd")
const Combat := preload("res://scripts/ai_combat_model.gd")
const Common := preload("res://scripts/ai_economy_common.gd")
const Production := preload("res://scripts/ai_economy_production.gd")

static func policy_for(snapshot: Dictionary, team: int, base: Dictionary, state) -> Dictionary:
	var policy := base.duplicate(true)
	var player: Dictionary = snapshot.get("player_state", {})
	var units := Common.own(snapshot.get("units", []), team)
	var buildings := Common.own(snapshot.get("buildings", []), team)
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
	var army_count := Common.army_count(units)
	var producers := buildings.filter(func(b): return String(b.get("kind", "")) in ["barracks", "archery_range", "stable", "siege_workshop"]).size()
	# Grow towards the production capacity we actually need to feed. Large
	# population limits may support more than forty workers in later economies.
	policy["land_worker_target"] = mini(target, maxi(int(base.get("land_worker_target", 8)), 12 + maxi(0, age - 100) * 8 + producers * 4))
	# Growing the long-term workforce must not move the age eligibility threshold
	# ahead of the current economy and spend the saved food on more workers.
	policy["minimum_workers_before_age_up"] = maxi(1, int(base.get("minimum_workers_before_age_up", 6)))
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


static func forecast(snapshot: Dictionary, units: Array, buildings: Array, policy: Dictionary, state) -> Dictionary:
	var horizon := float(policy.get("forecast_seconds", 45.0))
	var desired := {0: 120.0, 1: 120.0, 2: 0.0, 3: 0.0}
	for building in buildings:
		var train: Array = building.get("command_options", {}).get("train", [])
		var candidate := Production.preferred_train(train, units, snapshot, policy, state, String(building.get("kind", "")))
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
	var age := Production.age_intent(buildings, snapshot.get("player_state", {}), policy, workers, int(snapshot.get("tick", 0)))
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
