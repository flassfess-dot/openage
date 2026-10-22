class_name RoRAiAdaptiveEconomy
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const Rules := preload("res://scripts/ai_economy_rules.gd")
const Combat := preload("res://scripts/ai_combat_model.gd")
const Resources := preload("res://scripts/ai_resource_spatial_index.gd")
const RESOURCE_NAMES := ["food", "wood", "stone", "gold"]
const Common := preload("res://scripts/ai_economy_common.gd")
const Forecast := preload("res://scripts/ai_economy_forecast.gd")
const Production := preload("res://scripts/ai_economy_production.gd")
const Construction := preload("res://scripts/ai_economy_construction.gd")
const Gathering := preload("res://scripts/ai_economy_gathering.gd")

static var memoized_production_enabled := true
static var memoized_site_checks_enabled := true
static var native_resource_views_enabled := true


static func _economy_resources(resources: Array, buildings: Array, team: int, native: bool = true) -> Dictionary:
	return Common.economy_resources(resources, buildings, team, native)


static func own(rows: Array, team: int) -> Array:
	return Common.own(rows, team)


static func policy_for(snapshot: Dictionary, team: int, base: Dictionary, state) -> Dictionary:
	return Forecast.policy_for(snapshot, team, base, state)


static func _army_count(units: Array) -> int:
	return Common.army_count(units)


static func _next_training_food(buildings: Array, worker: bool) -> int:
	return Common.next_training_food(buildings, worker)


static func forecast(snapshot: Dictionary, units: Array, buildings: Array, policy: Dictionary, state) -> Dictionary:
	return Forecast.forecast(snapshot, units, buildings, policy, state)


static func site_kinds(kinds: Array, snapshot: Dictionary, team: int, base: Dictionary, state) -> Array:
	return Construction.site_kinds(kinds, snapshot, team, base, state)


static func plan(
	snapshot: Dictionary, tick: int, team: int, base: Dictionary, state, budget, reserved: Dictionary, timings: Dictionary = {}, resource_index: Variant = null
) -> Array:
	var started := Time.get_ticks_usec()
	var policy := Forecast.policy_for(snapshot, team, base, state)
	timings["policy"] = Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var units := Common.own(snapshot.get("units", []), team)
	var structures := Common.own(snapshot.get("buildings", []), team)
	var buildings: Array = structures.filter(func(b): return String(b.get("state", "complete")) == "complete")
	var workers: Array = units.filter(
		func(u): return ( bool(u.get("components", {}).get("worker", {}).get("enabled", false)) and String(u.get("movement_domain", "land")) == "land" )
	)
	var result: Array = []
	result.append_array(Gathering.worker_safety(snapshot, tick, team, policy, state, reserved))
	# A completed build/move can leave a villager idle with its previous cargo.
	# Active returns keep their route; idle cargo uses the public deposit order.
	for worker in units:
		var worker_id := int(worker.get("id", -1))
		if reserved.has(worker_id) or not bool(worker.get("components", {}).get("worker", {}).get("enabled", false)):
			continue
		if String(worker.get("task", "")) in ["idle", "hold"] and float(worker.get("ai_profile", {}).get("carried_amount", 0.0)) > 0.0:
			Common.offer(result, Commands.ReturnResourcesCommand.new(tick, [worker_id]), {}, 0, -1, true, state, budget, reserved)
	var age := Production.age_intent(buildings, snapshot.get("player_state", {}), policy, workers.size(), tick)
	var defending := String(state.goal.get("type", "")) == "defend"
	var minimum_army := int(policy.get("minimum_attack_group_size", 3))
	var army_count := Common.army_count(units)
	var operating_food := (Common.next_training_food(buildings, true) if workers.size() < int(policy["minimum_workers_before_age_up"]) else 0) + (Common.next_training_food(buildings, false) if army_count < minimum_army else 0)
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
					Common.offer(result, command, option.get("cost", {}), 0, producer_id, true, state, budget, reserved)
	elif not defending and (bool(age.get("block_construction", false)) or age.has("command")):
		var reserve: Dictionary = {}
		for resource in age.get("cost", {}):
			var floor_stock := operating_food if int(resource) == 0 else 0
			reserve[int(resource)] = maxi(0, mini(int(age["cost"][resource]), int(budget.remaining.get(int(resource), 0)) - floor_stock))
		budget.protect(reserve)
	policy["saving_age"] = not budget.protected.is_empty()
	policy["defending"] = defending
	policy["army_priority"] = workers.size() >= 8 and army_count < minimum_army
	Construction.resume_foundations(snapshot, tick, policy, state, budget, reserved, result, structures, units, workers)
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
	Production.plan_production(snapshot, tick, team, policy, state, budget, reserved, result, units, buildings, workers, memoized_production_enabled)
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
	result.append_array(Gathering.economic_scout(snapshot, tick, team, policy, state, reserved))
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
	return Production.producer_rank(kind, policy, workers)


static func _worker_safety(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary) -> Array:
	return Gathering.worker_safety(snapshot, tick, team, policy, state, reserved)


static func _economic_scout(snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary) -> Array:
	return Gathering.economic_scout(snapshot, tick, team, policy, state, reserved)


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
	return Common.offer(result, command, cost, points, producer, essential, state, budget, reserved)


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
	Construction.construct(snapshot, tick, team, policy, state, budget, reserved, result, requested, memoized_site_checks_enabled, native_site_scores_enabled, native_kernel)


static func _site_key(kind: String, site: Vector2) -> String:
	return Common.site_key(kind, site)


static func _preferred_train(
	options: Array, units: Array, snapshot: Dictionary, policy: Dictionary, state, producer_kind: String
) -> Dictionary:
	return Production.preferred_train(options, units, snapshot, policy, state, producer_kind)


static func _preferred_research(options: Array, units: Array, policy: Dictionary, state) -> Dictionary:
	return Production.preferred_research(options, units, policy, state)


static func _gather(
	snapshot: Dictionary, tick: int, team: int, policy: Dictionary, state, reserved: Dictionary, timings: Dictionary = {}, resource_index: Variant = null
) -> Array:
	return Gathering.gather(snapshot, tick, team, policy, state, reserved, timings, resource_index, native_resource_views_enabled)


static func _age_intent(
	buildings: Array, player: Dictionary, policy: Dictionary, workers: int, tick: int
) -> Dictionary:
	return Production.age_intent(buildings, player, policy, workers, tick)

static var native_site_scores_enabled := true
static var native_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
static func _site_resource_bonuses(resources: Array, sites: Array, kind: String, use_native: bool = true) -> Dictionary:
	return Construction.site_resource_bonuses(resources, sites, kind, use_native, native_site_scores_enabled, native_kernel)
