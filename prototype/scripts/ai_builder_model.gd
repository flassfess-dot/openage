extends RefCounted

const MAX_CANDIDATES := 32
const MAX_CREW := 16

# Construction in this engine is additive work. Arrival is an estimate from
# legal own positions; the ordinary movement/approach rules still execute it.
static func completion_time(work: float, roster: Array, extra: Dictionary = {}) -> float:
	if work<=0.0: return 0.0
	var events: Array=roster.duplicate(false)
	if not extra.is_empty(): events.append(extra)
	events.sort_custom(func(a,b):return float(a["arrival"])<float(b["arrival"]) if float(a["arrival"])!=float(b["arrival"]) else int(a["id"])<int(b["id"]))
	return _finish_ordered(work,events)


static func _finish_ordered(work: float, roster: Array, extra: Dictionary = {}) -> float:
	if work<=0.0: return 0.0
	var time:=0.0
	var rate:=0.0
	var remaining:=work
	var cursor:=0
	var pending:=not extra.is_empty()
	for _index in range(roster.size()+(1 if pending else 0)):
		var event: Dictionary
		if pending and (cursor>=roster.size() or float(extra["arrival"])<float(roster[cursor]["arrival"]) or (float(extra["arrival"])==float(roster[cursor]["arrival"]) and int(extra["id"])<int(roster[cursor]["id"]))):
			event=extra;pending=false
		else:
			event=roster[cursor];cursor+=1
		var arrival:=maxf(time,float(event["arrival"]))
		if rate>0.0:
			var delivered:=(arrival-time)*rate
			if delivered>=remaining: return time+remaining/rate
			remaining-=delivered
		time=arrival
		rate+=maxf(0.0,float(event["rate"]))
	return time+remaining/rate if rate>0.0 else INF


static func worker_forecast(worker: Dictionary, site: Vector2, footprint: float, income_per_worker: float, horizon: float) -> Dictionary:
	var speed:=maxf(0.1,float(worker.get("ai_profile",{}).get("speed",worker.get("speed",1.0))))
	var distance:=maxf(0.0,Vector2(worker.get("pos",Vector2.ZERO)).distance_to(site)-maxf(0.0,footprint)-float(worker.get("footprint_radius",0.3))-1.0)
	var productive:=String(worker.get("task","idle")) in ["gather","build"]
	var opportunity:=maxf(0.0,income_per_worker) if productive else 0.0
	# Carried goods are retained by construction, but their deposit is delayed.
	opportunity+=maxf(0.0,float(worker.get("carried_amount",0.0)))/maxf(10.0,horizon)
	return {"id":int(worker["id"]),"arrival":distance/speed,"travel":distance/speed,"rate":maxf(0.01,float(worker.get("construction_work_rate",1.0))),"opportunity":opportunity}


static func urgency(kind: String, snapshot: Dictionary, policy: Dictionary, state, total_income: float, team: int = -1) -> float:
	var player: Dictionary=snapshot.get("player_state",{})
	var owner:=team if team>=0 else int(snapshot.get("observer_team",0))
	if kind=="house":return 3.0+minf(4.0,float(player.get("blocked_population_queues",0))) if int(player.get("blocked_population_queues",0))>0 else 0.35
	if kind=="town_center":return 2.0+total_income if not snapshot.get("buildings",[]).any(func(b):return String(b.get("kind",""))=="town_center" and String(b.get("state","complete"))=="complete" and int(b.get("team",0))==owner) else 0.75
	if kind=="wonder":return 3.0+total_income*0.5 if bool(state.goal.get("pursue_wonder",false)) else 0.5
	if kind in ["tower","gate","wall"]:return 2.0+total_income*0.25 if String(state.goal.get("type",""))=="defend" else 0.25
	if kind in ["granary","storage_pit","dock"]:return 0.75+total_income*0.1 if policy.get("construction_recovery_positions",{}).has(kind) else 0.35
	return 0.25


# Greedy marginal value, with an explicit cap on attention and storage. Existing
# builders freed earlier are credited; charging only the extra worker would
# incorrectly treat the same fixed construction work as additional lost income.
static func choose(work: float, primary: Array, candidates: Array, value_per_second: float, maximum_crew: int = MAX_CREW) -> Dictionary:
	var roster: Array=primary.duplicate(true)
	roster.sort_custom(func(a,b):return float(a["arrival"])<float(b["arrival"]) if float(a["arrival"])!=float(b["arrival"]) else int(a["id"])<int(b["id"]))
	var selected: Dictionary={}
	var ids: Array[int]=[]
	for builder in primary:ids.append(int(builder["id"]))
	for builder in roster:selected[int(builder["id"])]=true
	var audit: Array=[]
	var pool: Array=candidates.slice(0,MAX_CANDIDATES)
	while roster.size()<mini(MAX_CREW,maxi(1,maximum_crew)):
		var before:=_finish_ordered(work,roster)
		var old_opportunity:=0.0
		for builder in roster:old_opportunity+=float(builder["opportunity"])
		var best: Dictionary={}
		var best_value:=0.0
		var best_audit: Dictionary={}
		for candidate in pool:
			if selected.has(int(candidate["id"])):continue
			var after:=_finish_ordered(work,roster,candidate)
			if not is_finite(after) or after>=before-0.000001 or float(candidate["arrival"])>=after:continue
			var opportunity:=float(candidate["opportunity"])
			var lost_income:=after*(old_opportunity+opportunity)-before*old_opportunity+opportunity*(float(candidate.get("travel",candidate["arrival"]))+1.0-float(candidate.get("commitment_delay",0.0)))
			var saved_seconds:=before-after
			var value:=saved_seconds*value_per_second-lost_income
			if value>best_value+0.000001 or (value>0.000001 and is_equal_approx(value,best_value) and (best.is_empty() or int(candidate["id"])<int(best["id"]))):
				best=candidate;best_value=value
				best_audit={"worker":int(candidate["id"]),"seconds_saved":saved_seconds,"income_delay_delta":lost_income,"value":value}
		if best.is_empty():break
		roster.append(best)
		roster.sort_custom(func(a,b):return float(a["arrival"])<float(b["arrival"]) if float(a["arrival"])!=float(b["arrival"]) else int(a["id"])<int(b["id"]))
		selected[int(best["id"])]=true
		ids.append(int(best["id"]))
		audit.append(best_audit)
	return {"ids":ids,"completion_seconds":_finish_ordered(work,roster),"marginal_choices":audit,"candidates":pool.size()}
