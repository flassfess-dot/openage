extends RefCounted
const Economy = preload("res://scripts/ai_adaptive_economy.gd")
const Budget = preload("res://scripts/ai_plan_budget.gd")
const Support = preload("res://scripts/ai_support_planner.gd")
const Transport = preload("res://scripts/ai_transport_planner.gd")
const Regions = preload("res://scripts/ai_region_model.gd")
const Director = preload("res://scripts/ai_strategy_director.gd")
const Micro = preload("res://scripts/ai_micro_controller.gd")
const Actions = preload("res://scripts/ai_action_scheduler.gd")
const Capabilities = preload("res://scripts/ai_capability_planner.gd")
const Combat = preload("res://scripts/ai_combat_model.gd")
const Traffic = preload("res://scripts/ai_traffic_clearance.gd")
var regions = Regions.new()
var director = Director.new()
var micro = Micro.new()
var actions = Actions.new()
var last_operation_tick = -1000
var last_strategy_tick = -1000
var tactical_navigation: Dictionary = {}

func plan(ai, snapshot: Dictionary, tick: int, reserved: Dictionary) -> Array:
	ai.planning_metrics.clear()
	var layer_started := Time.get_ticks_usec()
	snapshot=actions.react(snapshot,tick,int(ai.team),ai.economic_policy)
	var navigation_reserved = reserved.duplicate()
	var full_navigation: bool=not snapshot.get("navigation",{}).is_empty()
	if full_navigation:
		cache_tactical_navigation(snapshot)
	else:
		snapshot=snapshot.duplicate(); snapshot["navigation"]=tactical_navigation
	var policy: Dictionary = ai.economic_policy.duplicate(true)
	policy["maximum_enemy_memory"] = 1024
	policy["competitive"] = true
	ai.strategy.observe(snapshot,int(ai.team),policy)
	ai.planning_metrics["knowledge"]=Time.get_ticks_usec()-layer_started
	layer_started=Time.get_ticks_usec()
	var economic_due: bool=ai.last_economic_tick<0 or tick-int(ai.last_economic_tick)>=int(ai.economic_interval)
	var strategy_due: bool=tick-last_strategy_tick>=clampi(int(policy.get("strategy_interval_ticks",80)),40,160) or ai.strategy.goal.is_empty()
	var alert: Dictionary=defense_alert(snapshot,int(ai.team),policy,ai.strategy)
	var pending_refresh: bool=bool(ai.strategy.metrics.get("pending_defense_refresh",false))
	var refresh: bool=economic_due and (full_navigation or ai.strategy.goal.is_empty()) and (strategy_due or pending_refresh or not alert.is_empty())
	if refresh:
		ai.strategy.choose_goal(snapshot,int(ai.team),policy,int(ai.decision_index))
		regions.update(snapshot,ai.strategy,policy)
		ai.strategy.metrics.erase("pending_defense_refresh")
	elif not alert.is_empty():
		# A tactical snapshot has no full path/region context. Rally to the
		# threatened owned base now, then refine the plan at the next economic
		# capture. It must never turn missing tactical cells into a boat request.
		var actor: Dictionary=alert["actor"]
		var domain=String(alert["domain"])
		var rally: Dictionary={"type":"defend","home":alert["home"],"position":alert["home"],"target_position":actor.get("pos",alert["home"]),"target_id":int(actor["id"]),"target_domain":domain,"target_domains":actor.get("target_domains",[domain]).duplicate(),"target_radius":float(actor.get("footprint_radius",0.3)),"observed":true,"adaptive_strategy":true,"needs_transport":false,"defense_rally":true}
		var domains: Dictionary=ai.strategy.goal.get("goals_by_domain",{}).duplicate(true)
		domains[domain]=rally.duplicate(true);rally["goals_by_domain"]=domains
		ai.strategy.goal=rally
		ai.strategy.metrics["pending_defense_refresh"]=true
		ai.strategy.metrics["last_urgent_defense"]={"tick":tick,"home":alert["home"],"target_id":actor["id"]}
	if refresh or not alert.is_empty():
		ai.strategy.goal = director.choose(snapshot,int(ai.team),policy,ai.strategy,regions,pending_refresh)
		last_strategy_tick = tick
	ai.planning_metrics["strategy"]=Time.get_ticks_usec()-layer_started
	layer_started=Time.get_ticks_usec()
	var goal: Dictionary = ai.strategy.goal.duplicate(true)
	policy = director.apply_policy(policy)
	if ai.strategy.memory.has(int(goal.get("target_id",-1))):
		var known: Dictionary = ai.strategy.memory[int(goal["target_id"])]
		if bool(known.get("observed",false)):
			goal["target_position"] = known["entity"].get("pos",goal.get("position",Vector2.ZERO))
			if String(goal.get("target_domain","land"))!="water" and not bool(goal.get("defense_rally",false)): goal["position"]=goal["target_position"]
	ai.decision_index += 1
	var owned = Economy.own(snapshot.get("buildings",[]),int(ai.team))
	var budget = Budget.new(snapshot.get("player_state",{}),owned)
	var result: Array = []
	ai.planning_metrics["context"]=Time.get_ticks_usec()-layer_started
	layer_started=Time.get_ticks_usec()
	if ai.last_economic_tick < 0 or tick-int(ai.last_economic_tick) >= int(ai.economic_interval):
		ai._expire_failed_gathers(snapshot); ai._remember_failed_gather_targets(snapshot)
		policy["failed_gather_targets"] = ai.failed_gather_targets
		result.append_array(Traffic.plan(snapshot,tick,int(ai.team),ai.strategy,reserved))
		result.append_array(Economy.plan(snapshot,tick,int(ai.team),policy,ai.strategy,budget,reserved,ai.planning_metrics,ai.economic_resource_index))
		result.append_array(Capabilities.plan(snapshot,tick,int(ai.team),policy,ai.strategy,budget,reserved,regions))
		var support_snapshot = snapshot.duplicate()
		support_snapshot["units"] = snapshot.get("units",[]).filter(func(u): return not reserved.has(int(u.get("id",-1))))
		for command in Support.plan(support_snapshot,tick,int(ai.team),policy,ai.strategy):
			if String(command.command_type()) == "repair" and int(budget.remaining.get(1,0))<int(policy.get("repair_wood_reserve",60)): continue
			result.append(command)
			for id in command.unit_ids: reserved[int(id)] = true
		ai.last_economic_tick = tick
	ai.planning_metrics["economy"]=Time.get_ticks_usec()-layer_started
	layer_started=Time.get_ticks_usec()
	if tick-last_operation_tick >= clampi(int(policy.get("operation_interval_ticks",10)),10,40):
		goal["competitive"]=true
		goal["landing_threats"] = ai.strategy.enemies(int(snapshot.get("tick",0)),policy)
		goal["expeditions"] = ai.strategy.expeditions
		goal["minimum_landing_group"] = ai.minimum_attack_group_size
		goal["minimum_naval_escort"] = int(policy.get("minimum_naval_escort",2))
		goal["landing_danger_limit"] = float(policy.get("landing_danger_limit",12.0))
		var allowed = tick>=int(ai.initial_attack_delay) or String(goal.get("type",""))=="defend"
		if allowed:
			for command in Transport.plan(snapshot,tick,int(ai.team),goal,String(ai.formation_name),reserved):
				result.append(command)
				for id in command.unit_ids: reserved[int(id)] = true
		policy["minimum_attack_group_size"] = ai.minimum_attack_group_size
		policy["maximum_attack_group_size"] = clampi(maxi(int(ai.maximum_attack_group_size),ceili(float(snapshot.get("player_state",{}).get("population_limit",50))/8.0)),8,64)
		result.append_array(ai.operations.plan(snapshot,tick,int(ai.team),goal,policy,ai.strategy,reserved,String(ai.formation_name),allowed))
		for command in result:
			if String(command.command_type()) not in ["attack_move","move"] or command.unit_ids.is_empty() or not command.params.has("target"): continue
			var actor: Dictionary={}
			for unit in snapshot.get("units",[]):
				if int(unit.get("id",-1))==int(command.unit_ids[0]): actor=unit; break
			if actor.is_empty(): continue
			var origin=Vector2(actor.get("pos",Vector2.ZERO)); var target=Vector2(command.params["target"])
			if origin.distance_to(target)<20.0: continue
			var route: Array=regions.route(origin,target,String(actor.get("movement_domain","land")))
			for point in route:
				if origin.distance_to(Vector2(point))<4.0: continue
				command.target=Vector2(point); command.params["target"]=Vector2(point); break
		last_operation_tick = tick
	ai.planning_metrics["operations"]=Time.get_ticks_usec()-layer_started
	layer_started=Time.get_ticks_usec()
	if bool(policy.get("micro_enabled",true)):
		var retreating: Dictionary = {}
		for operation in ai.operations.groups.values():
			if String(operation["group"].state)=="retreating":
				for id in operation["group"].living_ids(): retreating[int(id)]=true
		var micro_snapshot = snapshot.duplicate()
		micro_snapshot["units"] = snapshot.get("units",[]).filter(func(u): return not navigation_reserved.has(int(u.get("id",-1))))
		var tactical = micro.plan(micro_snapshot,tick,int(ai.team),policy,ai.strategy,retreating)
		var claimed: Dictionary = {}
		for command in tactical:
			for id in command.unit_ids: claimed[int(id)]=true
		var retained: Array = []
		for command in result:
			var ids: Array[int] = []
			for id in command.unit_ids:
				if not claimed.has(int(id)): ids.append(int(id))
			if not command.unit_ids.is_empty() and ids.is_empty(): continue
			command.unit_ids=ids; retained.append(command)
		result=retained+tactical
	ai.planning_metrics["micro"]=Time.get_ticks_usec()-layer_started
	ai.last_military_tick = tick
	return result

static func urgent_defense(snapshot: Dictionary,team: int,policy: Dictionary,state) -> bool:
	return not defense_alert(snapshot,team,policy,state).is_empty()

static func defense_alert(snapshot: Dictionary,team: int,policy: Dictionary,state) -> Dictionary:
	if String(state.goal.get("type",""))=="defend": return {}
	var homes: Array=[Vector2(state.goal.get("home",Vector2.ZERO))]
	for building in snapshot.get("buildings",[]):
		if homes.size()>=16: break
		if int(building.get("team",0))!=team or String(building.get("kind",""))!="town_center" or float(building.get("hp",0))<=0.0: continue
		var point=Vector2(building.get("pos",Vector2.ZERO))
		if point not in homes: homes.append(point)
	var allies: Array=snapshot.get("player_state",{}).get("allies",[team])
	var tick=int(snapshot.get("tick",0))
	# Reacted, visible rows provide the cheap proximity gate. Remembered or
	# neutral actors cannot wake strategy by themselves, and a quiet economy
	# never rebuilds the complete threat map at the micro cadence.
	for category in ["units","buildings"]:
		for actor in snapshot.get(category,[]):
			var owner=int(actor.get("team",0))
			if owner<=0 or owner==team or owner in allies or bool(actor.get("last_known",false)) or float(actor.get("hp",0))<=0.0: continue
			if actor.has("combat_enabled") and not bool(actor["combat_enabled"]): continue
			var profile: Dictionary=Combat.profile(actor)
			if not bool(profile.get("enabled",actor.get("combat_enabled",false))): continue
			var response=minf(float(policy.get("enemy_response_distance",22.0)),maxf(6.0,float(profile.get("range",0.0))+(4.0 if bool(actor.get("components",{}).get("worker",{}).get("enabled",false)) else 8.0)))
			var position=Vector2(actor.get("pos",Vector2.ZERO))
			for home in homes:
				if position.distance_squared_to(home)>response*response: continue
				for domain in actor.get("target_domains",["land"]):
					if String(domain) in ["land","water"] and state.danger(home,tick,policy,String(domain))>8.0: return {"actor":actor,"home":home,"domain":String(domain)}
	return {}

func canonical_state() -> Dictionary:
	return {"version":1,"regions":regions.canonical_state(),"director":director.canonical_state(),"micro":micro.canonical_state(),"actions":actions.canonical_state(),"tactical_navigation":tactical_navigation.duplicate(true),"last_operation_tick":last_operation_tick,"last_strategy_tick":last_strategy_tick}

func restore_state(data: Dictionary) -> bool:
	if int(data.get("version",-1))!=1 or not data.get("regions") is Dictionary or not data.get("director") is Dictionary: return false
	if not regions.restore_state(data["regions"]) or not director.restore_state(data["director"]): return false
	if not data.get("micro") is Dictionary or not micro.restore_state(data["micro"]): return false
	if not data.get("actions") is Dictionary or not actions.restore_state(data["actions"]): return false
	if not data.get("tactical_navigation",{}) is Dictionary: return false
	tactical_navigation=data.get("tactical_navigation",{}).duplicate(true)
	for points in tactical_navigation.get("reachable",{}).values():
		if not points is Array or points.size()>4096: return false
	last_operation_tick=int(data.get("last_operation_tick",-1000)); last_strategy_tick=int(data.get("last_strategy_tick",-1000))
	return true

func cache_tactical_navigation(snapshot: Dictionary) -> void:
	var navigation: Dictionary = snapshot.get("navigation",{})
	var local: Dictionary = {"land":[],"water":[]}
	var lookup: Dictionary = snapshot.get("_economy_reachable_cells",{})
	for domain in ["land","water"]:
		var present: Dictionary = {}
		var cells: Dictionary = lookup.get(domain,{})
		if cells.is_empty():
			cells = {}
			for point in navigation.get("reachable",{}).get(domain,[]): cells[Vector2i(Vector2(point).floor())]=true
		for actor in snapshot.get("units",[]):
			if int(actor.get("team",0))!=int(snapshot.get("observer_team",-1)) or String(actor.get("movement_domain","land"))!=domain: continue
			if bool(actor.get("components",{}).get("worker",{}).get("enabled",false)): continue
			var center = Vector2i(Vector2(actor.get("pos",Vector2.ZERO)).floor())
			for y in range(center.y-2,center.y+3):
				for x in range(center.x-2,center.x+3):
					var cell = Vector2i(x,y)
					if cells.has(cell) and present.size()<4096: present[cell]=true
		var keys: Array = present.keys(); keys.sort_custom(func(a,b): return a.y<b.y if a.y!=b.y else a.x<b.x)
		for cell in keys: local[domain].append(Vector2(cell)+Vector2(0.5,0.5))
	tactical_navigation={"reachable":local,"land":local["land"],"water":local["water"]}
