extends RefCounted
# Recovery uses exact own cargo and actual food income, never hidden resources.
const MAX_TRACKED_WORKERS := 512

static func plan(snapshot: Dictionary,policy: Dictionary,state,units: Array,buildings: Array,food_demand: float=0.5) -> Dictionary:
	var tick:=int(snapshot.get("tick",0)); var player: Dictionary=snapshot.get("player_state",{})
	var wanted_food:=maxf(150.0,100.0+food_demand*float(policy.get("forecast_seconds",45.0)))
	for building in buildings:
		for option in building.get("command_options",{}).get("research",[]):
			if int(option.get("technology_id",-1))==int(player.get("age",100))+1:
				wanted_food=maxf(wanted_food,float(option.get("cost",{}).get(0,0)))
	var income:=float(state.income.get(0,0.0))
	var hunger: Dictionary=state.metrics.get("food_shortfall",{})
	var since:=int(hunger.get("since",-1))
	var recovering:=bool(hunger.get("fallback",false))
	if income>=maxf(0.5,food_demand) or float(player.get("food",0))>=wanted_food: since=-1; recovering=false
	elif income>0.05 and not recovering: since=-1
	elif since<0: since=tick
	var food_delay:=clampi(int(policy.get("food_shortfall_ticks",1200)),200,3600)
	var farms:=recovering or (since>=0 and tick-since>=food_delay)
	state.metrics["food_shortfall"]={"since":since,"required":wanted_food,"income":income,"target_income":food_demand,"fallback":farms}
	var prior: Dictionary=state.metrics.get("cargo_progress",{})
	var tracked: Dictionary={}; var groups: Dictionary={}
	var cargo_delay:=clampi(int(policy.get("cargo_recovery_ticks",1200)),200,3600)
	for worker in units:
		if tracked.size()>=MAX_TRACKED_WORKERS: break
		if not bool(worker.get("components",{}).get("worker",{}).get("enabled",false)): continue
		if String(worker.get("task","idle")) not in ["idle","gather","return_resources","move"]: continue
		var profile: Dictionary=worker.get("ai_profile",{})
		var amount:=float(worker.get("carried_amount",profile.get("carried_amount",0.0)))
		var resource:=int(worker.get("carried_resource_type_id",profile.get("carried_resource_type_id",-1)))
		if amount<=0.0 or resource not in [0,1,2,3]: continue
		var id:=int(worker["id"]); var position:=Vector2(worker.get("pos",Vector2.ZERO)).snapped(Vector2.ONE*0.25)
		var previous: Dictionary=prior.get(id,{})
		# Full carriers circling without a deposit are stalled too; position
		# changes alone do not establish economic progress.
		if previous.is_empty() or not is_equal_approx(float(previous["amount"]),amount):
			previous={"amount":amount,"position":position,"since":tick}
		tracked[id]=previous
		if tick-int(previous["since"])<cargo_delay: continue
		var kind: String="dock" if String(worker.get("movement_domain","land"))=="water" else "granary" if resource==0 else "storage_pit"
		var accepted: Array=profile.get("delivery_drop_site_kinds",profile.get("drop_site_kinds",[]))
		if resource==0 and kind=="granary" and "storage_pit" in accepted and "granary" not in accepted: kind="storage_pit"
		var key:=kind+":"+str(Vector2i(floori(position.x/8.0),floori(position.y/8.0)))
		var group: Dictionary=groups.get(key,{"kind":kind,"key":key,"sum":Vector2.ZERO,"count":0,"value":0.0})
		group["sum"]+=position; group["count"]+=1; group["value"]+=amount+10.0; groups[key]=group
	state.metrics["cargo_progress"]=tracked
	var best: Dictionary={}; var keys:=groups.keys(); keys.sort()
	for key in keys:
		var group: Dictionary=groups[key]; var kind:=String(group["kind"])
		if not best.has(kind) or float(group["value"])>float(best[kind]["value"]): best[kind]=group
	var old: Dictionary=state.metrics.get("infrastructure_recovery",{}); var goals: Dictionary={}
	var maximum:=clampi(3+units.size()/24,3,16)
	for kind in best:
		var group: Dictionary=best[kind]; var goal: Dictionary=old.get(kind,{})
		if goal.is_empty() or tick>=int(goal["expires"]):
			var count:=buildings.filter(func(b): return String(b.get("kind",""))==kind).size()
			goal={"key":group["key"],"position":group["sum"]/float(group["count"]),"target_count":mini(maximum,count+1),"created":tick,"expires":tick+2400}
		goals[kind]=goal
	state.metrics["infrastructure_recovery"]=goals
	var defending:=String(state.goal.get("type",""))=="defend"
	return {"farms":farms and not defending,"goals":{} if defending else goals}
