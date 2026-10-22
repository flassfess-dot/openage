extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const Rules := preload("res://scripts/ai_economy_rules.gd")
const Common := preload("res://scripts/ai_economy_common.gd")
const Forecast := preload("res://scripts/ai_economy_forecast.gd")

static func site_kinds(kinds: Array, snapshot: Dictionary, team: int, base: Dictionary, state) -> Array:
	var policy := Forecast.policy_for(snapshot, team, base, state)
	var buildings := Common.own(snapshot.get("buildings", []), team)
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


static func construct(
	snapshot: Dictionary,
	tick: int,
	team: int,
	policy: Dictionary,
	state,
	budget,
	reserved: Dictionary,
	result: Array,
	requested: Array,
	memoized_site_checks_enabled: bool,
	native_site_scores_enabled: bool,
	native_kernel: Variant
) -> void:
	var structures := Common.own(snapshot.get("buildings", []), team)
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
	var workers: Array = Common.own(snapshot.get("units", []), team).filter(
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
				if state.cooldowns.has(Common.site_key(kind, site)):
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
						site_values = site_resource_bonuses(snapshot.get("resources", []), snapshot.get("build_sites", {}).get(kind, []), kind, true, native_site_scores_enabled, native_kernel)
					else: site_values[site] = 0.0
				score += float(site_values[site])
				if score < best_score:
					best_score = score
					best = {"worker": worker, "site": site, "option": option}
		if best.is_empty():
			continue
		var essential: bool = kind in ["house", "town_center", "farm", "granary", "storage_pit"]
		if Common.offer(
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


static func site_resource_bonuses(resources: Array, sites: Array, kind: String, use_native: bool = true, native_site_scores_enabled: bool = true, native_kernel: Variant = null) -> Dictionary:
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


static func resume_foundations(snapshot: Dictionary, tick: int, policy: Dictionary, state, budget, reserved: Dictionary, result: Array, structures: Array, units: Array, workers: Array) -> void:
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
			Common.offer(
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
