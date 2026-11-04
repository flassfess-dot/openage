extends RefCounted
const Library = preload("res://scripts/ai_plan_library.gd")
const Common = preload("res://scripts/ai_economy_common.gd")
const Roles = preload("res://scripts/ai_micro_controller.gd")
const Ranker = preload("res://scripts/ai_linear_ranker.gd")
var plan: Dictionary = {}
var chosen_tick = -1000
var alternatives: Array = []

func choose(snapshot: Dictionary, team: int, policy: Dictionary, state, regions, force: bool=false) -> Dictionary:
	var tick = int(snapshot.get("tick",0))
	var goal: Dictionary = state.goal.duplicate(true)
	var own = Common.own(snapshot.get("units",[]),team)
	var home = Vector2(goal.get("home",Vector2.ZERO))
	var danger: float = state.danger(home,tick,policy)
	if force or tick-chosen_tick >= clampi(int(policy.get("strategy_interval_ticks",80)),40,160) or (danger>8.0 and String(plan.get("id",""))!="survive"):
		var facts = {"age":int(snapshot.get("player_state",{}).get("age",100)),"danger":danger,"army":Common.army_count(own),"workers":own.filter(func(u): return bool(u.get("components",{}).get("worker",{}).get("enabled",false))).size(),"known":state.enemies(tick,policy).size(),"water":own.filter(func(u): return String(u.get("movement_domain","land"))=="water").size(),"needs_transport":goal.get("needs_transport",false)}
		facts["siege_count"]=own.filter(func(unit):return String(unit.get("movement_domain","land"))=="land" and Roles.siege_role(unit)).size()
		facts["screen_count"]=own.filter(func(unit):return String(unit.get("movement_domain","land"))=="land" and Roles.screen_role(unit)).size()
		facts["screen_target"]=ceili(float(facts["siege_count"])*1.5)
		alternatives = Library.candidates(facts)
		if bool(policy.get("ranker_enabled",false)) and Ranker.valid(policy.get("ranker_model",{})):
			for candidate in alternatives:
				candidate["manual_utility"]=candidate["utility"]
				candidate["utility"]=Ranker.score(candidate,facts,policy["ranker_model"])
		for candidate in alternatives:
			if String(candidate["id"]) == String(plan.get("id","")): candidate["utility"] += float(policy.get("plan_inertia",8.0))
		alternatives.sort_custom(func(a,b): return float(a["utility"])>float(b["utility"]) if not is_equal_approx(float(a["utility"]),float(b["utility"])) else String(a["id"])<String(b["id"]))
		var next: Dictionary = alternatives[0]
		if String(next["id"]) != String(plan.get("id","")):
			plan = next.duplicate(true); plan["step"] = 0; plan["started_tick"] = tick; plan["start_age"] = int(facts["age"])
		chosen_tick = tick
		plan["facts"] = facts
	var steps: Array = plan.get("steps",[])
	if not steps.is_empty():
		var step = int(plan.get("step",0))
		while step < steps.size()-1 and task_complete(String(steps[step]),snapshot,team,policy,state,own): step += 1
		plan["step"] = step
		plan["active_task"] = steps[step]
	var expansion: Dictionary = regions.best_expansion(home,float(policy.get("maximum_economic_danger",8.0)))
	if not expansion.is_empty(): goal["expansion_position"] = expansion["position"]
	goal["strategic_plan"] = String(plan.get("id","develop"))
	if String(plan.get("id","")) == "pressure" and String(goal.get("type","")) != "defend":
		var best = -INF
		for enemy in state.enemies(tick,policy):
			if not bool(enemy.get("components",{}).get("worker",{}).get("enabled",false)): continue
			var position = Vector2(enemy.get("pos",home))
			var score = 45.0*float(enemy.get("confidence",1.0))-home.distance_to(position)-state.danger(position,tick,policy)*0.5
			if score>best:
				best=score
				goal.merge({"type":"attack","target_id":int(enemy["id"]),"position":position,"target_position":position,"target_domain":String(enemy.get("movement_domain","land")),"observed":bool(enemy.get("observed",false))},true)
				var domain_goal = goal.duplicate(true); domain_goal.erase("goals_by_domain")
				goal.get_or_add("goals_by_domain",{})[String(goal["target_domain"])]=domain_goal
	state.metrics["strategic_plan"] = plan.duplicate(true)
	state.metrics["strategic_alternatives"] = alternatives.duplicate(true)
	if String(goal.get("type",""))!="defend":
		var rules: Array=snapshot.get("victory_rules",[]).map(func(r): return String(r.get("type","conquest")))
		var candidates: Array=[]
		for objective in snapshot.get("objectives",[]):
			var category=String(objective.get("category",""))
			if (category+"s" in rules or category=="wonder" and "wonder" in rules) and int(objective.get("team",0)) not in snapshot.get("player_state",{}).get("allies",[team]): candidates.append(objective)
		candidates.sort_custom(func(a,b): return home.distance_squared_to(Vector2(a.get("pos",Vector2.ZERO)))<home.distance_squared_to(Vector2(b.get("pos",Vector2.ZERO))) if home.distance_squared_to(Vector2(a.get("pos",Vector2.ZERO)))!=home.distance_squared_to(Vector2(b.get("pos",Vector2.ZERO))) else int(a["id"])<int(b["id"]))
		if not candidates.is_empty():
			var objective: Dictionary=candidates[0]
			goal.merge({"type":"secure","position":objective.get("pos",home),"target_id":int(objective["id"]),"target_domain":"land","objective_category":objective.get("category","")},true)
			goal["goals_by_domain"]={"land":goal.duplicate(true)}
			goal["goals_by_domain"]["land"].erase("goals_by_domain")
		elif "wonder" in rules: goal["pursue_wonder"]=true
		# A request is an intention. Receiving AI verifies the place from its own
		# current visible allies; no message is inserted into enemy memory.
		for intent in snapshot.get("team_intents",[]):
			if String(intent.get("kind",""))=="attack":
				var sender=int(intent.get("sender",-1)); var rally=Vector2(intent.get("position",home))
				if sender in snapshot.get("player_state",{}).get("mutual_allies",[team]) and snapshot.get("units",[]).filter(func(u): return int(u.get("team",0))==sender and bool(u.get("combat_enabled",false)) and Vector2(u.get("pos",Vector2.ZERO)).distance_to(rally)<10.0).size()>=3:
					goal["allied_rally"]=rally
			if String(intent.get("kind",""))!="cover": continue
			var sender=int(intent.get("sender",-1)); var position=Vector2(intent.get("position",home))
			if sender not in snapshot.get("player_state",{}).get("mutual_allies",[team]): continue
			if not snapshot.get("units",[]).any(func(u): return int(u.get("team",0))==sender and Vector2(u.get("pos",Vector2.ZERO)).distance_to(position)<8.0): continue
			if state.danger(position,tick,policy)>4.0: goal["ally_cover_position"]=position
	return goal

func task_complete(task: String,snapshot: Dictionary,team: int,policy: Dictionary,state,own: Array) -> bool:
	var buildings = Common.own(snapshot.get("buildings",[]),team)
	var army = Common.army_count(own)
	var workers = own.filter(func(u): return bool(u.get("components",{}).get("worker",{}).get("enabled",false))).size()
	var known = state.enemies(int(snapshot.get("tick",0)),policy)
	match task:
		"shelter_workers","repel": return String(state.goal.get("type","")) != "defend"
		"produce_counters","assemble": return army>=int(policy.get("minimum_attack_group_size",3))
		"rally_defenders": return own.any(func(u): return bool(u.get("combat_enabled",false)) and String(u.get("task","")) in ["attack","attack_move"])
		"scout_target": return not known.is_empty()
		"raid_economy","break_defence": return own.any(func(u): return String(u.get("task",""))=="attack")
		"secure_food": return snapshot.get("resources",[]).any(func(r): return int(r.get("resource_type_id",-1))==0 and int(r.get("amount",0))>0)
		"grow_workers": return workers>=maxi(14,int(policy.get("land_worker_target",18)))
		"add_drop_sites": return buildings.any(func(b): return String(b.get("kind","")) in ["granary","storage_pit"] and String(b.get("state",""))=="complete")
		"expand": return buildings.filter(func(b): return String(b.get("kind",""))=="town_center").size()>1
		"satisfy_prerequisites","reserve_resources":
			for building in buildings:
				for option in building.get("command_options",{}).get("research",[]):
					if int(option.get("technology_id",-1)) not in policy.get("age_advance_technology_ids",[]): continue
					if task=="reserve_resources" and bool(option.get("accepted",false)): return true
					if task=="satisfy_prerequisites" and String(option.get("reason","")) not in ["missing_prerequisites","already_researched"]: return true
		"advance_age": return int(snapshot.get("player_state",{}).get("age",100))>int(plan.get("start_age",100))
		"train_siege": return own.any(func(unit): return String(unit.get("movement_domain","land"))=="land" and Roles.siege_role(unit))
		"assign_screen":
			var siege: Array=own.filter(func(unit):return String(unit.get("movement_domain","land"))=="land" and Roles.siege_role(unit))
			var screen: Array=own.filter(func(unit):return String(unit.get("movement_domain","land"))=="land" and Roles.screen_role(unit))
			if siege.is_empty() or screen.size()<ceili(float(siege.size())*1.5):return false
			return siege.all(func(engine):return screen.any(func(guard):return Vector2(guard.get("pos",Vector2.ZERO)).distance_squared_to(Vector2(engine.get("pos",Vector2.ZERO)))<=64.0))
		"occupy_firing_position": return own.any(func(unit): return Roles.siege_role(unit) and (String(unit.get("ai_profile",{}).get("action_phase",""))=="PerformAction" or float(unit.get("ai_profile",{}).get("cooldown",0.0))>0.0))
		"secure_dock": return buildings.any(func(b): return String(b.get("kind",""))=="dock" and String(b.get("state",""))=="complete")
		"build_escort": return own.filter(func(u): return String(u.get("movement_domain","land"))=="water" and bool(u.get("combat_enabled",false))).size()>=int(policy.get("minimum_naval_escort",2))
		"load": return own.any(func(u): return not u.get("components",{}).get("cargo",{}).get("passenger_ids",[]).is_empty())
		"sail": return state.expeditions.values().any(func(e): return String(e.get("phase","")) in ["sailing","unloading","returning"])
		"land": return state.expeditions.values().any(func(e): return String(e.get("phase","")) in ["returning","loading"])
	return false

func apply_policy(policy: Dictionary) -> Dictionary:
	var result = policy.duplicate(true)
	result["strategic_plan"] = String(plan.get("id","develop"))
	result["plan_task"] = String(plan.get("active_task","secure_food"))
	if String(plan.get("id",""))=="pressure": result["age_defender_minimum"] = int(policy.get("minimum_attack_group_size",3))
	if String(plan.get("id",""))=="advance": result["age_defender_minimum"] = 1
	if String(plan.get("id",""))=="siege":
		var facts: Dictionary=plan.get("facts",{})
		var screen_needed: bool=int(facts.get("siege_count",0))>0 and int(facts.get("screen_count",0))<int(facts.get("screen_target",0))
		result["prefer_screen"]=screen_needed
		result["prefer_siege"]=not screen_needed
	return result

func canonical_state() -> Dictionary:
	return {"plan":plan.duplicate(true),"chosen_tick":chosen_tick,"alternatives":alternatives.duplicate(true)}

func restore_state(data: Dictionary) -> bool:
	if not data.get("plan",{}) is Dictionary or not data.get("alternatives",[]) is Array or data.get("alternatives",[]).size()>12: return false
	plan=data.get("plan",{}).duplicate(true); chosen_tick=int(data.get("chosen_tick",-1000)); alternatives=data.get("alternatives",[]).duplicate(true)
	var steps: Array = plan.get("steps",[])
	return plan.is_empty() or (not steps.is_empty() and int(plan.get("step",0))>=0 and int(plan.get("step",0))<steps.size())
