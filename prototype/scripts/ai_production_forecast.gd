extends RefCounted

const Combat := preload("res://scripts/ai_combat_model.gd")
const MAX_ENEMIES := 32
const MAX_PRODUCERS := 128

# A macro planning hypothesis, never an observed upgrade or a tactical profile.
# Without an observed technology, allow one modest upgrade during the forecast
# horizon. No world, technology registry or foreign player state is consulted.
static func context(enemies: Array, snapshot: Dictionary, policy: Dictionary) -> Dictionary:
	var horizon := clampf(float(policy.get("forecast_seconds",45.0)),10.0,120.0)
	var elapsed := maxf(0.0,float(snapshot.get("tick",0))/20.0)
	var records: Array=[]
	var expected_upgrades:=0.0
	var limit:=clampi(int(policy.get("combat_sample_budget",MAX_ENEMIES)),1,MAX_ENEMIES)
	for enemy in Combat.strategic_sample(enemies,limit):
		var confidence:=clampf(float(enemy.get("confidence",1.0)),0.0,1.0)
		var probability:=clampf((0.10+0.40*elapsed/(elapsed+300.0)+0.35*(1.0-confidence))*horizon/60.0,0.0,0.75)
		if String(enemy.get("movement_domain","land"))=="static" or String(enemy.get("entity_type",""))=="building":probability=0.0
		var future:Dictionary=enemy.duplicate(false)
		future.erase("route_area")
		var profile:Dictionary=enemy.get("ai_profile",{}).duplicate(true)
		future["ai_profile"]=profile
		# These are explicit priors, not an assertion that a particular enemy
		# civilization owns an upgrade. Observed stats stay untouched.
		for attack in profile.get("attacks",[]):attack["amount"]=float(attack.get("amount",0.0))+1.0
		profile["damage"]=float(profile.get("damage",1.0))+1.0
		for armor in profile.get("armors",[]):armor["amount"]=float(armor.get("amount",0.0))+1.0
		profile["base_armor"]=float(profile.get("base_armor",0.0))+1.0 if profile.get("armors",[]).is_empty() else float(profile.get("base_armor",0.0))
		var weight:=maxf(0.05,confidence)*clampi(int(enemy.get("belief_count",1)),1,1024)
		records.append({"current":enemy,"future":future,"probability":probability,"weight":weight})
		expected_upgrades+=probability
	return {"records":records,"horizon":horizon,"infrastructure":infrastructure(snapshot),"expected_upgrade_scenarios":expected_upgrades,"hypothesis_only":true}


static func counter_score(candidate: Dictionary, forecast: Dictionary, own: Array) -> float:
	var records:Array=forecast.get("records",[])
	if records.is_empty():return Combat.counter_score(candidate,[],own)
	var outgoing:=0.0
	var incoming:=0.0
	var total:=0.0
	for record in records:
		var p:=float(record["probability"])
		var weight:=float(record["weight"])
		outgoing+=weight*lerpf(Combat.dps(candidate,record["current"]),Combat.dps(candidate,record["future"]),p)
		incoming+=weight*lerpf(Combat.dps(record["current"],candidate),Combat.dps(record["future"],candidate),p)
		total+=weight
	var same:=0
	for unit in own:
		if String(unit.get("kind",""))==String(candidate.get("kind","")):same+=1
	var profile:Dictionary=Combat.profile(candidate)
	return sqrt(maxf(0.0,float(candidate.get("hp",profile.get("max_hp",1.0))))*outgoing/maxf(0.01,total))*(1.0+minf(12.0,float(profile.get("range",0.0)))*0.035)/(1.0+incoming/maxf(0.01,total)*0.05)/(1.0+same*0.06)


# A switching cost in planning seconds, not another command price. The next two
# units can exhaust a newly adopted resource mix. Queued units are already paid.
# Existing production capacity shortens reinforcement time; it never grants
# a unit, technology, discount or free construction.
static func infrastructure(snapshot:Dictionary) -> Dictionary:
	var capacities:Dictionary={}
	var queued_kinds:Dictionary={}
	var inspected:=0
	for building in snapshot.get("buildings",[]):
		if int(building.get("team",0))!=int(snapshot.get("observer_team",-1)):continue
		inspected+=1
		if inspected>MAX_PRODUCERS:break
		var producer_kind:=String(building.get("kind",""))
		if String(building.get("state","complete"))=="complete":capacities[producer_kind]=int(capacities.get(producer_kind,0))+1
		for order in building.get("production_queue",[]).slice(0,16):
			if String(order.get("order_type","unit"))!="unit":continue
			queued_kinds[String(order.get("kind",""))]=true
	return {"capacities":capacities,"queued_kinds":queued_kinds,"inspected":mini(inspected,MAX_PRODUCERS)}


static func logistics(option: Dictionary, own: Array, snapshot: Dictionary, state, producer_kind: String, horizon: float, base:Dictionary={}) -> Dictionary:
	if base.is_empty():base=infrastructure(snapshot)
	var kind:=String(option.get("kind",""))
	var established:bool=base["queued_kinds"].has(kind) or own.any(func(u):return String(u.get("kind",""))==kind)
	var capacity:=int(base["capacities"].get(producer_kind,0))
	var switching:=0.0
	var names:={0:"food",1:"wood",2:"stone",3:"gold"}
	var has_army:bool=own.any(func(u):return "worker" not in u.get("behavior_tags",[]) and bool(u.get("ai_profile",{}).get("enabled",u.get("combat_enabled",false))))
	if not established and has_army:
		for resource in option.get("cost",{}):
			var stock:=float(snapshot.get("player_state",{}).get(names.get(int(resource),""),0.0))
			var deficit:=maxf(0.0,float(option["cost"][resource])*2.0-stock)
			switching+=deficit/maxf(0.25,float(state.income.get(int(resource),0.0)))
	switching=minf(120.0,switching)
	var reinforcement:=maxf(0.0,float(option.get("duration",0.0)))/maxi(1,capacity)
	return {"switch_seconds":switching,"capacity":capacity,"reinforcement_seconds":reinforcement,"multiplier":1.0/(1.0+switching/maxf(20.0,horizon*2.0)+reinforcement/maxf(80.0,horizon*8.0))}
