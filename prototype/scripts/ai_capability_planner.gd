extends RefCounted
const Commands = preload("res://scripts/commands.gd")
const Common = preload("res://scripts/ai_economy_common.gd")
const Garrison = preload("res://scripts/tower_garrison.gd")
const TransportSystem = preload("res://scripts/transport_system.gd")
const Transport = preload("res://scripts/ai_transport_planner.gd")
const Rules = preload("res://scripts/ai_economy_rules.gd")

static func plan(snapshot: Dictionary,tick: int,team: int,policy: Dictionary,state,budget,reserved: Dictionary,regions) -> Array:
	var result: Array=[]
	var buildings:=Common.own(snapshot.get("buildings",[]),team)
	var units:=Common.own(snapshot.get("units",[]),team)
	var player: Dictionary=snapshot.get("player_state",{})
	# A known forest barrier is cleared with paid-in-time worker gathering,
	# rather than treating it as a permanent reason to wait for a nonexistent
	# sea route. The same ordinary work order and cargo rules apply to humans.
	if bool(state.goal.get("needs_transport",false)) and snapshot.get("navigation",{}).get("reachable",{}).get("water",snapshot.get("navigation",{}).get("water",[])).is_empty():
		var target:=Vector2(state.goal.get("target_position",state.goal.get("position",Vector2.ZERO)))
		var home:=Vector2(state.goal.get("home",Vector2.ZERO))
		var eligible: Array=units.filter(func(u): return not reserved.has(int(u["id"])) and bool(u.get("components",{}).get("worker",{}).get("enabled",false)) and String(u.get("movement_domain","land"))=="land" and String(u.get("task","")) in ["idle","gather"] and float(u.get("ai_profile",{}).get("carried_amount",0))<=0)
		var best: Dictionary={}; var best_score:=-INF
		var clearing_reachable: Dictionary=Rules.reachable_cells_by_domain(snapshot.get("navigation",{}))
		for resource in snapshot.get("resources",[]):
			if String(resource.get("kind",""))!="tree" or int(resource.get("amount",0))<=0: continue
			var position:=Vector2(resource.get("pos",Vector2.ZERO))
			if home.distance_to(position)>16.0: continue
			var score:=home.distance_to(target)-position.distance_to(target)-float(state.danger(position,int(snapshot.get("tick",0)),policy))*4.0
			if score<=maxf(2.0,best_score): continue
			var reachable: Array=eligible.filter(func(u): return Rules.resource_has_reachable_approach(resource,u,clearing_reachable))
			if not reachable.is_empty(): best={"resource":resource,"workers":reachable}; best_score=score
		if not best.is_empty():
			var selected: Array[int]=[]
			for worker in best["workers"].slice(0,2):
				reserved[int(worker["id"])]=true
				if int(worker.get("resource_id",-1))!=int(best["resource"]["id"]): selected.append(int(worker["id"]))
			if not selected.is_empty(): result.append(Commands.GatherCommand.new(tick,selected,int(best["resource"]["id"])))
			state.metrics["clearance_probe"]={"resource_id":best["resource"]["id"],"position":best["resource"]["pos"],"reason":"known land target, no known sea route"}
	for intent in snapshot.get("team_intents",[]):
		var sender:=int(intent.get("sender",-1))
		if sender not in player.get("mutual_allies",[team]): continue
		if String(intent.get("kind",""))=="transport":
			for ship in units:
				if reserved.has(int(ship["id"])) or String(ship.get("movement_domain","land"))!="water" or String(ship.get("task","")) not in ["idle","hold"]: continue
				if not bool(ship.get("components",{}).get("cargo",{}).get("enabled",false)) or not ship.get("components",{}).get("cargo",{}).get("passenger_ids",[]).is_empty(): continue
				var approach: Variant=Transport._water_approach(Vector2(intent.get("position",Vector2.ZERO)),ship,snapshot.get("navigation",{}))
				if approach is Vector2 and Vector2(ship.get("pos",Vector2.ZERO)).distance_to(approach)>3.0: Common.offer(result,Commands.MoveCommand.new(tick,[int(ship["id"])],approach),{},0,-1,false,state,budget,reserved)
		if String(intent.get("kind",""))=="resource" and not state.cooldowns.has("help:"+str(sender)):
			var resource:=int(intent.get("resource_type_id",0)); var amount:=mini(200,int(intent.get("amount",0)))
			if amount>0 and int(budget.remaining.get(resource,0))-amount>=400:
				if Common.offer(result,Commands.TributeCommand.new(tick,sender,resource,amount),{resource:amount},0,-1,false,state,budget,reserved): state.cooldowns["help:"+str(sender)]=tick+600
	var last_intent:=int(state.metrics.get("last_team_intent_tick",-600))
	if tick-last_intent>=600:
		var allies: Array=player.get("mutual_allies",[team]).filter(func(t): return int(t)!=team)
		allies.sort()
		if not allies.is_empty():
			var kind:="attack" if String(state.goal.get("type",""))=="attack" else "cover"
			var resource:=0; var amount:=0
			for type_id in [0,1]:
				if int(budget.remaining.get(type_id,0))<50: kind="resource"; resource=type_id; amount=150; break
			if bool(state.goal.get("needs_transport",false)): kind="transport"
			# The position is an owned rally, with no hidden enemy payload.
			var home:=Vector2(state.goal.get("home",Vector2.ZERO))
			result.append(Commands.TeamIntentCommand.new(tick,int(allies[0]),kind,home,resource,amount))
			state.metrics["last_team_intent_tick"]=tick
	var farms:=buildings.filter(func(b): return String(b.get("kind",""))=="farm" and String(b.get("state",""))=="complete")
	var granaries:=buildings.filter(func(b): return String(b.get("kind",""))=="granary" and String(b.get("state",""))=="complete")
	if not granaries.is_empty() and bool(player.get("farm_reserve_available",false)):
		var urgent:=farms.filter(func(f): return int(f.get("amount",0))<=80).size()
		var desired:=mini(40,maxi(urgent,ceili(farms.size()*0.25)))
		if int(player.get("wood",0))<120: desired=0
		var current:=int(player.get("farm_reserve_count",0))
		if current>desired:
			Common.offer(result,Commands.FarmReserveCommand.new(tick,[int(granaries[0]["id"])],-1),{},0,-1,true,state,budget,reserved)
		elif current<desired and int(budget.remaining.get(1,0))>=180:
			Common.offer(result,Commands.FarmReserveCommand.new(tick,[int(granaries[0]["id"])],1),player.get("farm_reserve_cost",{}),0,-1,false,state,budget,reserved)
	for tower in buildings:
		if not Garrison.is_tower(tower) or String(tower.get("state",""))!="complete": continue
		var cargo: Dictionary=tower.get("components",{}).get("cargo",{})
		var passengers: Array=cargo.get("passenger_ids",[])
		var position:=Vector2(tower.get("pos",Vector2.ZERO))
		var danger: float=state.danger(position,int(snapshot.get("tick",0)),policy)
		if not passengers.is_empty() and (danger<1.0 or float(tower.get("hp",0))<float(tower.get("max_hp",1))*0.3):
			var safe: Dictionary=regions.best_expansion(position,1.0)
			var destination:=Vector2(state.goal.get("home",position+Vector2(2,0))) if safe.is_empty() else Vector2(safe["position"])
			# A tower cannot sail to a distant rally like a transport. Keep its
			# exit request inside the same public unloading radius; the transport
			# system still chooses and validates an unoccupied landing position.
			destination=position+(destination-position).limit_length(TransportSystem.MAX_UNLOAD_DISTANCE-0.25)
			Common.offer(result,Commands.UnloadCommand.new(tick,[int(tower["id"])],destination),{},0,-1,true,state,budget,reserved)
		elif danger>1.0 and passengers.size()<int(cargo.get("capacity",5)):
			var candidates:=units.filter(func(u): return not reserved.has(int(u["id"])) and Garrison.accepts(u) and String(u.get("task","")) in ["idle","hold","gather"] and Vector2(u.get("pos",Vector2.ZERO)).distance_to(position)<6.0)
			candidates.sort_custom(func(a,b):
				var ar: bool="ranged" in a.get("behavior_tags",[]); var br: bool="ranged" in b.get("behavior_tags",[])
				return ar if ar!=br else int(a["id"])<int(b["id"]))
			var ids: Array[int]=[]
			for actor in candidates.slice(0,int(cargo.get("capacity",5))-passengers.size()): ids.append(int(actor["id"]))
			if not ids.is_empty(): Common.offer(result,Commands.BoardCommand.new(tick,ids,int(tower["id"])),{},0,-1,true,state,budget,reserved)
	return result
