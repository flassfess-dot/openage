extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const EconomicPlanner := preload("res://scripts/ai_economic_planner.gd")
const Rules := preload("res://scripts/ai_economy_rules.gd")
const Common := preload("res://scripts/ai_economy_common.gd")
const Forecast := preload("res://scripts/ai_economy_forecast.gd")
const Access := preload("res://scripts/ai_construction_access.gd")
const BuilderModel := preload("res://scripts/ai_builder_model.gd")

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
	if bool(policy.get("competitive",false)):
		state.metrics["construction_demand"]={"requested":kinds.duplicate(),"demanded":demanded.duplicate(),"wood":snapshot.get("player_state",{}).get("wood",0)}
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
	var protect_access: bool = bool(policy.get("competitive", false)) and bool(snapshot.get("navigation", {}).get("cell_geometry", false))
	var access_land: Dictionary = {}
	var access_ready := false
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
		var valued_resources: Array=snapshot.get("resources",[])
		if bool(policy.get("competitive",false)) and kind in ["granary","storage_pit","town_center"]:
			valued_resources=valued_resources.filter(func(r): return float(r.get("amount",0))>0.0 and (kind not in ["granary","storage_pit","town_center"] or "land" in r.get("allowed_gatherer_domains",["land"])))
		var site_risks: Dictionary = {}
		var site_gaps: Dictionary = {}
		var site_access: Dictionary = {}
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
				if protect_access and kind not in ["wall", "gate"] and not bool(option.get("navigation_passable", false)) and option.has("navigation_obstruction_half_size"):
					if not access_ready:
						access_land = Access.prepare(snapshot["navigation"])
						access_ready = true
					if not site_access.has(site):
						site_access[site] = Access.preserves(site, Vector2(option["navigation_obstruction_half_size"]), access_land)
					if not bool(site_access[site]):
						continue
				var score := Vector2(worker.get("pos", Vector2.ZERO)).distance_to(site) + risk * 4.0 + gap_penalty
				if not site_values.has(site):
					if kind in ["granary", "storage_pit", "town_center"]:
						site_values = site_resource_bonuses(valued_resources, snapshot.get("build_sites", {}).get(kind, []), kind, true, native_site_scores_enabled, native_kernel)
					else: site_values[site] = 0.0
				score += float(site_values[site])
				if policy.get("construction_recovery_positions",{}).has(kind): score+=site.distance_to(Vector2(policy["construction_recovery_positions"][kind]))*3.0
				if score < best_score:
					best_score = score
					best = {"worker": worker, "site": site, "option": option}
		if best.is_empty():
			continue
		var essential: bool = kind in ["house", "town_center", "farm", "granary", "storage_pit"]
		var builder_ids: Array[int] = [int(best["worker"]["id"])]
		if bool(policy.get("competitive",false)) and kind in ["house","town_center","tower","dock","wonder","granary","storage_pit"]:
			builder_ids=construction_crew(snapshot,team,kind,Vector2(best["site"]),best["option"],[best["worker"]],workers,policy,state,reserved)["ids"]
		if Common.offer(
			result,
			Commands.BuildCommand.new(tick, builder_ids, kind, best["site"]),
			best["option"].get("cost", {}),
			0,
			-1,
			essential,
			state,
			budget,
			reserved
		):
			return


static func construction_crew(snapshot: Dictionary, team: int, kind: String, site: Vector2, option: Dictionary, initial: Array, workers: Array, policy: Dictionary, state, reserved: Dictionary, remaining_work: float = -1.0, commitment_delay: float = 0.0) -> Dictionary:
	var work:=remaining_work if remaining_work>=0.0 else float(option.get("duration",0.0))
	var initial_ids: Array[int]=[]
	for worker in initial:initial_ids.append(int(worker["id"]))
	if work<=0.0:return {"ids":initial_ids,"reason":"unknown_or_finished_work"}
	var total_income:=0.0
	for value in state.income.values():total_income+=maxf(0.0,float(value))
	var gatherers:=0
	for worker in snapshot.get("units",[]):
		if int(worker.get("team",0))==team and String(worker.get("task",""))=="gather" and bool(worker.get("components",{}).get("worker",{}).get("enabled",false)):gatherers+=1
	var income_per_worker:=total_income/float(maxi(1,gatherers))
	var horizon:=maxf(10.0,float(policy.get("forecast_seconds",45.0)))
	var footprint:=maxf(0.0,float(option.get("footprint_radius",1.0)))
	var primary: Array=[]
	var regions: Dictionary=snapshot.get("navigation",{}).get("unit_regions",{})
	var connected: Dictionary={}
	for worker in initial:
		primary.append(BuilderModel.worker_forecast(worker,site,footprint,income_per_worker,horizon))
		if regions.has(int(worker["id"])):connected[str(regions[int(worker["id"])])]=true
	var candidates: Array=[]
	var radius:=12.0 if kind=="wonder" else 6.0
	for helper in workers:
		var id:=int(helper["id"])
		if id in initial_ids or reserved.has(id) or Vector2(helper.get("pos",Vector2.ZERO)).distance_squared_to(site)>radius*radius:continue
		if not regions.is_empty() and not connected.has(str(regions.get(id,""))):continue
		if not helper.get("command_options",{}).get("build",[]).any(func(o):return String(o.get("kind",""))==kind and bool(o.get("accepted",false))):continue
		var forecast:=BuilderModel.worker_forecast(helper,site,footprint,income_per_worker,horizon)
		forecast["commitment_delay"]=commitment_delay
		forecast["arrival"]=float(forecast["arrival"])+commitment_delay
		candidates.append(forecast)
		if candidates.size()>=BuilderModel.MAX_CANDIDATES:break
	var maximum:=16 if kind=="wonder" else 8 if kind=="town_center" else 4
	var value:=BuilderModel.urgency(kind,snapshot,policy,state,total_income,team)
	var chosen:=BuilderModel.choose(work,primary,candidates,value,maximum)
	var audit:=chosen.duplicate(true)
	audit.merge({"kind":kind,"site":site,"work":work,"value_per_second":value,"commitment_delay":commitment_delay},true)
	state.metrics["construction_crew"]=audit
	return chosen


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
	var crew_evaluations:=0
	if bool(policy.get("competitive",false)):
		var total_income:=0.0
		for value in state.income.values():total_income+=maxf(0.0,float(value))
		foundations.sort_custom(func(a,b):
			var av:=BuilderModel.urgency(String(a.get("kind","")),snapshot,policy,state,total_income,int(a.get("team",0)))
			var bv:=BuilderModel.urgency(String(b.get("kind","")),snapshot,policy,state,total_income,int(b.get("team",0)))
			return av>bv if av!=bv else int(a["id"])<int(b["id"]))
	var recovery: Dictionary=state.metrics.get("foundation_recovery",{})
	var tracked: Dictionary={}
	for foundation in foundations.slice(0, int(policy.get("maximum_foundations", 2))):
		if bool(policy.get("competitive",false)):
			var id:=int(foundation["id"])
			var progress:=float(foundation.get("construction_progress",0.0))
			var previous: Dictionary=recovery.get(id,{"progress":progress,"last_progress_tick":tick})
			if progress>float(previous["progress"])+0.000001: previous={"progress":progress,"last_progress_tick":tick}
			tracked[id]=previous
			var deadline:=clampi(int(policy.get("foundation_stall_ticks",2400)),600,7200)
			if tick-int(previous["last_progress_tick"])>=deadline:
				# A builder can retain a nominal build order after its route is
				# blocked. Progress, rather than that order label, proves work.
				# Use the ordinary owned-entity command; no refund is fabricated.
				if Common.offer(result,Commands.DeleteEntityCommand.new(tick,[id]),{},0,-1,true,state,budget,reserved):
					state.cooldowns[Common.site_key(String(foundation["kind"]),Vector2(foundation["pos"]))]=tick+deadline
					state.metrics["last_abandoned_foundation"]={"id":id,"tick":tick,"reason":"no construction progress","last_progress_tick":previous["last_progress_tick"]}
				continue
		if bool(policy.get("competitive",false)) and crew_evaluations<1 and float(foundation.get("construction_required",0.0))>0.0 and String(foundation.get("kind","")) in ["house","town_center","tower","dock","wonder","granary","storage_pit"]:
			var active: Array=units.filter(func(u):return String(u.get("task",""))=="build" and int(u.get("target_building_id",-1))==int(foundation["id"]) and not reserved.has(int(u["id"])))
			# Existing known component membership avoids a new per-worker path
			# capture. Abandoned-foundation recovery below keeps its exact query.
			var regions: Dictionary=snapshot.get("navigation",{}).get("unit_regions",{})
			if not active.is_empty() and active.any(func(w):return regions.has(int(w["id"]))):
				crew_evaluations+=1
				var eligible_helpers: Array=workers.filter(func(w):return String(w.get("task","idle")) in ["idle","gather"] and not reserved.has(int(w["id"])))
				var remaining:=float(foundation["construction_required"])*maxf(0.0,1.0-float(foundation.get("construction_progress",0.0)))
				var option:={"footprint_radius":float(foundation.get("footprint_radius",1.0))}
				var delay:=maxf(0.0,float(tick-int(snapshot.get("tick",tick)))/20.0)
				var chosen:=construction_crew(snapshot,int(foundation.get("team",0)),String(foundation["kind"]),Vector2(foundation["pos"]),option,active,eligible_helpers,policy,state,reserved,remaining,delay)
				var active_ids: Array=active.map(func(w):return int(w["id"]))
				var extra_ids: Array[int]=[]
				for id in chosen["ids"]:
					if int(id) not in active_ids:extra_ids.append(int(id))
				if not extra_ids.is_empty():Common.offer(result,Commands.BuildCommand.new(tick,extra_ids,String(foundation["kind"]),Vector2(foundation["pos"])),{},0,-1,true,state,budget,reserved)
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
	if bool(policy.get("competitive",false)): state.metrics["foundation_recovery"]=tracked
