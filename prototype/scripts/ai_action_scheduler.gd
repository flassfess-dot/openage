extends RefCounted
# Integer token bucket: 1200 ticks per game minute, one group command = one action.
var tokens := -1
var last_tick := -1
var first_seen: Dictionary = {}
var admitted := 0
var deferred := 0
var waiting: Dictionary = {}
const MAX_REACTION_TRACKS := 8192

func react(snapshot: Dictionary,tick: int,team: int,policy: Dictionary) -> Dictionary:
	var delay := clampi(int(policy.get("reaction_ticks",8)),0,40)
	var result := snapshot.duplicate()
	var live: Dictionary = {}
	for category in ["units","buildings"]:
		var rows: Array = []
		for actor in snapshot.get(category,[]):
			var id := int(actor.get("id",-1))
			var owner := int(actor.get("team",0))
			if owner<=0 or owner==team or owner in snapshot.get("player_state",{}).get("allies",[team]) or bool(actor.get("last_known",false)):
				rows.append(actor); continue
			live[id]=true
			if not first_seen.has(id): first_seen[id]=tick
			if tick-int(first_seen[id])>=delay: rows.append(actor)
			elif result.has("ai_visible_memory_locations"):
				result["ai_visible_memory_locations"]=result["ai_visible_memory_locations"].duplicate()
				result["ai_visible_memory_locations"].erase(id)
		result[category]=rows
	# Losing contact requires a fresh reaction after reacquisition.
	for id in first_seen.keys():
		if not live.has(id): first_seen.erase(id)
	if first_seen.size()>MAX_REACTION_TRACKS:
		var ids: Array=first_seen.keys(); ids.sort()
		for id in ids.slice(MAX_REACTION_TRACKS): first_seen.erase(id)
	return result

func admit(commands: Array,tick: int,policy: Dictionary,state,operations) -> Array:
	var apm := clampi(int(policy.get("commands_per_minute",180)),30,600)
	var capacity := clampi(int(policy.get("command_burst",4)),1,12)*1200
	if tokens<0: tokens=capacity
	if last_tick>=0: tokens=mini(capacity,tokens+maxi(0,tick-last_tick)*apm)
	last_tick=tick
	var ranked: Array=[]
	for index in range(commands.size()):
		var command=commands[index]
		var kind:=String(command.command_type())
		var priority:=10
		if kind in ["train","research","build","farm_reserve"]: priority=40
		if kind in ["gather","return_resources"]: priority=30
		if kind in ["attack","heal","convert","attack_ground"]: priority=20
		if kind in ["move","formation_move"] and String(state.goal.get("type",""))=="defend": priority=50
		priority=maxi(priority,int(command.params.get("_ai_feedback",{}).get("priority",0)))
		if waiting.has(kind): priority+=mini(60,maxi(0,tick-int(waiting[kind])))
		ranked.append({"command":command,"priority":priority,"index":index})
	ranked.sort_custom(func(a,b): return int(a["priority"])>int(b["priority"]) if int(a["priority"])!=int(b["priority"]) else int(a["index"])<int(b["index"]))
	var result: Array=[]
	for entry in ranked:
		var command=entry["command"]
		if tokens>=1200:
			tokens-=1200; admitted+=1; result.append(command)
			waiting.erase(String(command.command_type()))
		else:
			deferred+=1
			if not waiting.has(String(command.command_type())): waiting[String(command.command_type())]=tick
			var operation_id:=int(command.params.get("_ai_feedback",{}).get("operation_id",-1))
			if operations.groups.has(operation_id): operations.groups[operation_id]["last_order_tick"]=-1
	state.metrics["action_budget"]={"admitted":admitted,"deferred":deferred,"tokens":tokens,"apm":apm}
	return result

func canonical_state() -> Dictionary:
	return {"tokens":tokens,"last_tick":last_tick,"first_seen":first_seen.duplicate(true),"waiting":waiting.duplicate(true),"admitted":admitted,"deferred":deferred}

func restore_state(data: Dictionary) -> bool:
	if not data.get("first_seen") is Dictionary or data["first_seen"].size()>MAX_REACTION_TRACKS: return false
	if not data.get("waiting") is Dictionary or data["waiting"].size()>40: return false
	if int(data.get("tokens",-2)) < -1 or int(data.get("tokens",-2))>14400: return false
	tokens=int(data["tokens"]); last_tick=int(data.get("last_tick",-1)); first_seen=data["first_seen"].duplicate(true)
	admitted=int(data.get("admitted",0)); deferred=int(data.get("deferred",0))
	waiting=data["waiting"].duplicate(true)
	return admitted>=0 and deferred>=0
