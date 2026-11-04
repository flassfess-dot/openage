extends RefCounted
const Recovery = preload("res://scripts/ai_infrastructure_recovery.gd")
const Common = preload("res://scripts/ai_economy_common.gd")

const STYLES := ["pressure","fast_age","growth","naval"]

static func opening(snapshot: Dictionary, policy: Dictionary, state = null) -> String:
	var explicit = String(policy.get("style",""))
	if explicit in STYLES: return explicit
	if state!=null:
		var saved:Dictionary=state.metrics.get("opening_selection",{})
		if String(saved.get("style","")) in STYLES:return String(saved["style"])
		# An older save has already committed to an opening. Preserve it rather
		# than choosing another style after learning more terrain.
		var prior:=String(state.metrics.get("macro_plan",{}).get("style",""))
		if prior in STYLES:
			state.metrics["opening_selection"]={"style":prior,"migrated":true}
			return prior
	var seed = int(policy.get("policy_seed",snapshot.get("match_seed",1)))
	var team = int(snapshot.get("observer_team",1))
	var civilization:=-1
	for player in snapshot.get("player_state",{}).get("players",[]):
		if int(player.get("team",0))==team:civilization=int(player.get("civilization_id",-1));break
	var weights:={"pressure":1.0,"fast_age":1.0,"growth":1.0,"naval":1.0}
	var navigation:Dictionary=snapshot.get("navigation",{})
	var land_count:int=navigation.get("land",[]).size()
	var water_count:int=navigation.get("water",[]).size()
	if land_count+water_count>=64:
		var water_fraction:=float(water_count)/float(land_count+water_count)
		weights["naval"]=0.0 if water_count==0 else 0.5+water_fraction*5.0
		weights["pressure"]=1.5-water_fraction
	# Own civilization's actual capabilities and prices take precedence over
	# a hard-coded civilization stereotype. Only owned command menus are read.
	var inexpensive_worker:=false
	var fast_pressure:=false
	var inspected:=0
	for building in snapshot.get("buildings",[]):
		if int(building.get("team",0))!=team:continue
		inspected+=1
		if inspected>32:break
		for option in building.get("command_options",{}).get("train",[]):
			if "worker" in option.get("behavior_tags",[]):
				inexpensive_worker=inexpensive_worker or float(option.get("cost",{}).get(0,999))<45.0
			else:
				var profile:Dictionary=option.get("ai_profile",{})
				fast_pressure=fast_pressure or (bool(profile.get("enabled",false)) and float(profile.get("speed",0.0))>=1.4 and float(profile.get("range",0.0))<=2.0)
	if inexpensive_worker:weights["growth"]+=1.0
	if fast_pressure:weights["pressure"]+=1.0
	var rng:=RandomNumberGenerator.new()
	rng.seed=seed*31+team*7919+maxi(0,civilization)*104729
	var total:=0.0
	for value in weights.values():total+=float(value)
	var roll:=rng.randf()*total
	var selected:="growth"
	for style in STYLES:
		roll-=float(weights[style])
		if roll<0.0:selected=style;break
	if state!=null:state.metrics["opening_selection"]={"style":selected,"seed":seed,"civilization":civilization,"known_land":land_count,"known_water":water_count,"weights":weights,"own_capabilities":{"inexpensive_worker":inexpensive_worker,"fast_pressure":fast_pressure}}
	return selected

static func adapt(policy: Dictionary, snapshot: Dictionary, state) -> Dictionary:
	var result = policy.duplicate(true)
	var team = int(snapshot.get("observer_team",0))
	var player: Dictionary = snapshot.get("player_state",{})
	var units = Common.own(snapshot.get("units",[]),team)
	var buildings = Common.own(snapshot.get("buildings",[]),team)
	var workers = units.filter(func(u): return bool(u.get("components",{}).get("worker",{}).get("enabled",false)) and String(u.get("movement_domain","land")) == "land").size()
	var cap = int(player.get("population_limit",50))
	var age = int(player.get("age",100))
	var style = opening(snapshot,policy,state)
	var definition: Dictionary = policy.get("opening_definitions",{}).get(style,{})
	var opening_target = int(definition.get("workers",{"pressure":14,"fast_age":18,"growth":24,"naval":18}[style]))
	var fraction = float(policy.get("worker_population_ratio",0.45))
	var long_term = mini(maxi(opening_target,roundi(float(cap)*fraction)),maxi(8,cap-8))
	var stage_target = opening_target if age == 100 else 28 if age == 101 else 48 if age == 102 else long_term
	var capacity = buildings.filter(func(b): return String(b.get("kind","")) in ["barracks","archery_range","stable","siege_workshop","dock"]).size()
	result["land_worker_target"] = mini(long_term,maxi(opening_target,stage_target+capacity*2))
	result["minimum_workers_before_age_up"] = mini(int(result["land_worker_target"]),maxi(8,int(definition.get("age_workers",opening_target-4))))
	result["age_defender_minimum"] = int(policy.get("age_defender_minimum",definition.get("age_defenders",3 if style == "pressure" else 1)))
	result["opening_style"] = style
	result["army_target"] = maxi(3,cap-int(result["land_worker_target"])-2)
	result["housing_buffer"] = clampi(2+capacity,3,12)
	result["maximum_foundations"] = clampi(1+workers/12,2,6)
	result["maximum_production_queue"] = 1
	var limits: Dictionary = result.get("building_limits",{}).duplicate(true)
	for kind in ["wall","gate","wonder"]: limits[kind]=0
	var food_income = float(state.income.get(0,0.0))
	var food_demand = 0.0
	for building in buildings:
		var options: Array = building.get("command_options",{}).get("train",[])
		if options.is_empty(): continue
		var option: Dictionary = options[0]
		food_demand += float(option.get("cost",{}).get(0,0))/maxf(1.0,float(option.get("duration",30.0)))
	var known_food = 0.0
	for resource in snapshot.get("resources",[]):
		if int(resource.get("resource_type_id",-1)) != 0 or "land" not in resource.get("allowed_gatherer_domains",["land"]): continue
		if buildings.any(func(b): return bool(b.get("ai_drop_site",false)) and Vector2(b.get("pos",Vector2.ZERO)).distance_to(Vector2(resource.get("pos",Vector2.ZERO)))<=18.0): known_food += maxf(0.0,float(resource.get("amount",0)))
	var recovery: Dictionary=Recovery.plan(snapshot,policy,state,units,buildings,food_demand)
	var farm_need = bool(recovery["farms"]) or known_food < maxf(800.0,float(workers)*80.0) or (food_demand>food_income*1.15 and int(player.get("food",0))<150)
	limits["farm"] = maxi(2,ceili(float(workers)*0.65)) if farm_need else 0
	limits["house"] = ceili(float(cap)/4.0)
	limits["town_center"] = mini(maxi(1,ceili(float(cap)/60.0)),1+workers/24) if age >= 102 else 1
	for kind in ["barracks","archery_range","stable","siege_workshop","dock"]:
		var matching: Array = buildings.filter(func(b): return String(b.get("kind",""))==kind)
		var busy = not matching.is_empty() and matching.all(func(b): return not b.get("production_queue",[]).is_empty())
		if busy and int(player.get("wood",0)) >= 200 and workers >= 16:
			limits[kind] = mini(maxi(2,workers/8),matching.size()+1)
	limits["storage_pit"] = maxi(int(limits.get("storage_pit",1)),1+workers/24)
	limits["granary"] = maxi(int(limits.get("granary",1)),1+workers/24)
	result["building_limits"] = limits
	result["desired_stock"] = result.get("desired_stock",{}).duplicate(true)
	var worker_cost = Common.next_training_food(buildings,true)
	result["desired_stock"][0] = maxf(float(result["desired_stock"].get(0,0.0)),float(worker_cost)*2.0+food_demand*float(result.get("forecast_seconds",45.0)))
	result["desired_stock"][1] = maxf(float(result["desired_stock"].get(1,0.0)),120.0+float(capacity)*30.0+(float(limits["farm"])*12.0 if farm_need else 0.0))
	var priorities: Array = result.get("construction_priorities",[]).duplicate()
	if farm_need: priorities.erase("farm"); priorities.insert(mini(3,priorities.size()),"farm")
	if style == "naval" and int(limits.get("dock",0)) > 0: priorities.erase("dock"); priorities.insert(mini(2,priorities.size()),"dock")
	if workers>=4 and not buildings.any(func(b): return String(b.get("kind",""))=="granary"):
		var remote_food: bool=snapshot.get("resources",[]).any(func(r):
			if int(r.get("resource_type_id",-1))!=0 or "land" not in r.get("allowed_gatherer_domains",["land"]): return false
			return not buildings.any(func(b): return bool(b.get("ai_drop_site",false)) and Vector2(b.get("pos",Vector2.ZERO)).distance_to(Vector2(r.get("pos",Vector2.ZERO)))<6.0))
		if remote_food: priorities.erase("granary"); priorities.insert(mini(1,priorities.size()),"granary")
	result["construction_priorities"] = priorities
	if String(state.goal.get("type",""))=="defend" and workers>=12:
		limits["tower"]=mini(6,1+workers/16)
		limits["gate"]=1
		limits["wall"]=4
		for kind in ["tower","gate","wall"]:
			if kind not in priorities: priorities.append(kind)
		result["desired_stock"][2]=maxf(float(result["desired_stock"].get(2,0)),150.0)
	# The economic target can be below 24 at population 50. A special
	# victory must remain reachable with the planned workforce.
	var wonder_workers = mini(24,int(result["land_worker_target"]))
	if bool(state.goal.get("pursue_wonder",false)) and age>=103 and workers>=wonder_workers:
		limits["wonder"]=1
		if "wonder" not in priorities: priorities.append("wonder")
		result["desired_stock"][1]=maxf(float(result["desired_stock"].get(1,0)),1100.0)
		result["desired_stock"][2]=maxf(float(result["desired_stock"].get(2,0)),1100.0)
		result["desired_stock"][3]=maxf(float(result["desired_stock"].get(3,0)),1100.0)
	result["construction_recovery_positions"]={}
	for kind in ["storage_pit","dock","granary"]:
		if not recovery["goals"].has(kind): continue
		var goal: Dictionary=recovery["goals"][kind]
		limits[kind]=maxi(int(limits.get(kind,0)),int(goal["target_count"]))
		result["construction_recovery_positions"][kind]=goal["position"]
		priorities.erase(kind); priorities.insert(mini(1,priorities.size()),kind)
	state.metrics["macro_plan"] = {"style":style,"worker_target":result["land_worker_target"],"army_target":result["army_target"],"food_income":food_income,"food_demand":food_demand,"farm_target":limits["farm"]}
	return result
