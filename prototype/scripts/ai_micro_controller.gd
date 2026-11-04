extends RefCounted
const Commands := preload("res://scripts/commands.gd")
const Combat := preload("res://scripts/ai_combat_model.gd")
var last_orders: Dictionary = {}
var threats_seen: Dictionary = {}
var cursor := 0

static func bucket(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x/8.0),floori(position.y/8.0))

func plan(snapshot: Dictionary,tick: int,team: int,policy: Dictionary,state,retreating: Dictionary = {}) -> Array:
	var own: Array = []; var enemies: Dictionary = {}; var live: Dictionary = {}; var observed_targets: Dictionary = {}; var role_units: Array = []
	var allies: Array = snapshot.get("player_state",{}).get("allies",[team])
	for actor in snapshot.get("units",[])+snapshot.get("buildings",[]):
		if float(actor.get("hp",0.0))<=0.0 or bool(actor.get("last_known",false)): continue
		if int(actor.get("team",0))==team:
			live[int(actor["id"])]=true
			if String(actor.get("entity_type",""))!="building" and not bool(actor.get("components",{}).get("worker",{}).get("enabled",false)):
				role_units.append(actor)
				if not bool(actor.get("components",{}).get("cargo",{}).get("enabled",false)): own.append(actor)
		elif int(actor.get("team",0))>0 and int(actor.get("team",0)) not in allies:
			var cell = bucket(Vector2(actor.get("pos",Vector2.ZERO)))
			if not enemies.has(cell): enemies[cell]=[]
			enemies[cell].append(actor)
			observed_targets[int(actor["id"])]=true
	for id in last_orders.keys():
		if not live.has(id): last_orders.erase(id)
	for id in threats_seen.keys():
		if tick-int(threats_seen[id])>200: threats_seen.erase(id)
	if own.is_empty() or enemies.is_empty(): return []
	snapshot=snapshot.duplicate()
	snapshot["_micro_observed_targets"]=observed_targets
	snapshot["_micro_role_units"]=role_units
	var cell_lookup: Dictionary={}
	for domain in ["land","water"]:
		var cells: Dictionary={}
		for point in snapshot.get("navigation",{}).get("reachable",{}).get(domain,[]): cells[Vector2i(Vector2(point).floor())]=true
		cell_lookup[domain]=cells
	snapshot["_micro_cells"]=cell_lookup
	# Private to this plan: all targets for one origin share the same bounded
	# flood prefix. It never survives a navigation snapshot or enters AI state.
	snapshot["_micro_floods"]={}
	var reserved_damage: Dictionary = {}
	for projectile in snapshot.get("projectiles",[]):
		if int(projectile.get("team",0))==team and projectile.has("target_id"):
			var target_id = int(projectile["target_id"])
			reserved_damage[target_id]=float(reserved_damage.get(target_id,0.0))+float(projectile.get("base_damage",0.0))
	var groups: Dictionary = {}
	var maximum = mini(own.size(),int(policy.get("micro_actor_budget",48)))
	for offset in range(maximum):
		var actor: Dictionary = own[posmod(cursor+offset,own.size())]
		var id = int(actor["id"])
		if String(actor.get("task","")) in ["board","embarked","build","gather","repair"]: continue
		var nearby: Array = []
		var origin = Vector2(actor.get("pos",Vector2.ZERO))
		var cell = bucket(origin)
		for y in range(cell.y-2,cell.y+3):
			for x in range(cell.x-2,cell.x+3): nearby.append_array(enemies.get(Vector2i(x,y),[]))
		nearby = nearby.filter(func(e): return origin.distance_squared_to(Vector2(e.get("pos",Vector2.ZERO)))<=400.0)
		if nearby.is_empty(): continue
		nearby.sort_custom(func(a,b): return origin.distance_squared_to(Vector2(a["pos"]))<origin.distance_squared_to(Vector2(b["pos"])) if not is_equal_approx(origin.distance_squared_to(Vector2(a["pos"])),origin.distance_squared_to(Vector2(b["pos"]))) else int(a["id"])<int(b["id"]))
		nearby = nearby.slice(0,32)
		var intent = decide(actor,nearby,own,snapshot,tick,team,policy,state,reserved_damage,retreating.has(id))
		if intent.is_empty(): continue
		var signature = str([intent["type"],intent.get("target_id",-1),intent.get("position",Vector2.ZERO)])
		var last: Dictionary = last_orders.get(id,{})
		if String(last.get("signature",""))==signature and tick-int(last.get("tick",-1000))<int(policy.get("micro_repeat_ticks",20)): continue
		var key = str([intent["type"],intent.get("target_id",-1),Vector2i(Vector2(intent.get("position",origin))*2.0),bucket(origin),String(actor.get("movement_domain","land"))])
		if not groups.has(key): groups[key] = {"intent":intent,"ids":[]}
		groups[key]["ids"].append(id)
		if String(intent["type"])=="attack":
			var target: Dictionary = intent.get("target",{})
			reserved_damage[int(intent["target_id"])]=float(reserved_damage.get(int(intent["target_id"]),0.0))+Combat.dps(actor,target)*maxf(0.1,float(actor.get("ai_profile",{}).get("period",2.0)))
	cursor += maxi(1,maximum)
	var result: Array = []
	var keys: Array = groups.keys(); keys.sort()
	for key in keys:
		var group: Dictionary = groups[key]; var intent: Dictionary = group["intent"]
		var ids: Array[int] = []
		for id in group["ids"]: ids.append(int(id))
		ids.sort()
		var command = null
		match String(intent["type"]):
			"move": command=Commands.MoveCommand.new(tick,ids,Vector2(intent["position"]))
			"hold": command=Commands.HoldCommand.new(tick,ids)
			"attack": command=Commands.AttackCommand.new(tick,ids,int(intent["target_id"]))
			"attack_ground": command=Commands.AttackGroundCommand.new(tick,ids,Vector2(intent["position"]))
			"heal": command=Commands.HealCommand.new(tick,ids,int(intent["target_id"]))
			"convert": command=Commands.ConvertCommand.new(tick,ids,int(intent["target_id"]))
		if command==null: continue
		command.params["_ai_feedback"]={"key":"micro:"+key,"cost":{},"priority":int(intent.get("priority",80)),"reason":intent.get("reason","micro"),"micro_signature":str([intent["type"],intent.get("target_id",-1),intent.get("position",Vector2.ZERO)])}
		if not state.cooldowns.has(command.params["_ai_feedback"]["key"]): result.append(command)
	return result

func decide(actor: Dictionary,enemies: Array,allies: Array,snapshot: Dictionary,tick: int,team: int,policy: Dictionary,state,reserved_damage: Dictionary,retreating: bool) -> Dictionary:
	var p: Dictionary = actor.get("ai_profile",{})
	var origin = Vector2(actor.get("pos",Vector2.ZERO))
	var danger = projectile_dodge(actor,snapshot,tick,team,int(policy.get("reaction_ticks",4)))
	if danger!=Vector2.ZERO:
		var point = movement_point(origin+danger*2.0,actor,snapshot)
		if point is Vector2: return {"type":"move","position":point,"priority":120,"reason":"visible_projectile"}
	if retreating: return {}
	var nearest: Dictionary = enemies[0]
	var delta = origin-Vector2(nearest.get("pos",origin))
	var distance = delta.length()
	var cooldown = float(p.get("cooldown",0.0))
	var phase = String(p.get("action_phase",""))
	if phase=="PerformAction" and cooldown<=0.0 and String(actor.get("task","")) not in ["heal","convert"]: return {}
	if String(actor.get("movement_domain","land"))=="water" and float(actor.get("hp",1.0))<float(p.get("max_hp",1.0))*0.35:
		var docks: Array = snapshot.get("buildings",[]).filter(func(b): return int(b.get("team",0))==team and String(b.get("kind",""))=="dock")
		if not docks.is_empty():
			docks.sort_custom(func(a,b): return origin.distance_squared_to(Vector2(a["pos"]))<origin.distance_squared_to(Vector2(b["pos"])))
			var point = movement_point(Vector2(docks[0]["pos"]),actor,snapshot)
			if point is Vector2: return {"type":"move","position":point,"priority":110,"reason":"repair_ship"}
	var healing = bool(actor.get("components",{}).get("healing",{}).get("enabled",false))
	var converting = "converter" in actor.get("behavior_tags",[]) or bool(p.get("conversion",{}).get("enabled",false))
	if healing or converting:
		var action := String(actor.get("task",""))
		var current_target := int(actor.get("target_id",actor.get("components",{}).get("order",{}).get("target_entity_id",-1)))
		var target_observed: bool=snapshot["_micro_observed_targets"].has(current_target) if snapshot.has("_micro_observed_targets") else snapshot.get("units",[]).any(func(unit): return int(unit.get("id",-1))==current_target and not bool(unit.get("last_known",false)))
		var lost_conversion: bool=action=="convert" and current_target>=0 and not target_observed
		# Keep useful work in progress. Reposition before a cast; cancel an
		# existing conversion only when its observed survival chance is poor.
		if not lost_conversion and action in ["heal","convert"] and distance>2.0: return {}
		if not lost_conversion and action=="convert" and viable_conversion(actor,enemies,p.get("conversion",{})): return {}
		if distance<3.0:
			var point = movement_point(origin+delta.normalized()*3.0,actor,snapshot)
			if point is Vector2: return {"type":"move","position":point,"priority":115,"reason":"protect_priest"}
		var cover := role_anchor(actor,allies,snapshot,"front")
		if not cover.is_empty() and distance<4.5:
			var toward := (Vector2(nearest["pos"])-Vector2(cover["position"])).normalized()
			if (origin-Vector2(cover["position"])).dot(toward)>-1.0:
				var shelter := role_move(Vector2(cover["position"])-toward*2.5,actor,snapshot,"behind_cover",112)
				if not shelter.is_empty(): return shelter
		if lost_conversion: return {"type":"hold","priority":105,"reason":"lost_conversion_target"}
		if action in ["heal","convert"]: return {}
		var heal: Dictionary = {}; var urgency = 0.0
		for ally in allies:
			if int(ally.get("id",-1))==int(actor["id"]) or origin.distance_to(Vector2(ally.get("pos",origin)))>6.0: continue
			var missing = float(ally.get("max_hp",ally.get("ai_profile",{}).get("max_hp",1.0)))-float(ally.get("hp",0.0))
			if missing>urgency: urgency=missing; heal=ally
		if healing and not heal.is_empty(): return {"type":"heal","target_id":int(heal["id"]),"priority":95,"reason":"triage"}
		var conversion: Dictionary=p.get("conversion",{})
		if converting and float(conversion.get("faith",0.0))+0.0001>=float(conversion.get("max_faith",100.0)):
			var valuable: Dictionary = {}; var value = -INF
			for enemy in enemies:
				if String(enemy.get("entity_type",""))=="building" or origin.distance_to(Vector2(enemy["pos"]))>10.0: continue
				var estimate = float(enemy.get("max_hp",enemy.get("ai_profile",{}).get("max_hp",1.0)))-origin.distance_to(Vector2(enemy["pos"]))*5.0
				if estimate>value: value=estimate; valuable=enemy
			if not valuable.is_empty(): return {"type":"convert","target_id":int(valuable["id"]),"priority":90,"reason":"valuable_conversion"}
		return {}
	if not bool(actor.get("combat_enabled",false)): return {}
	var reach = float(p.get("range",0.0))
	var enemy_reach = float(nearest.get("ai_profile",{}).get("range",0.0))
	if reach>2.0 and cooldown>0.15 and distance<minf(reach,enemy_reach+2.0):
		var point = movement_point(origin+delta.normalized()*2.0,actor,snapshot)
		if point is Vector2: return {"type":"move","position":point,"priority":100,"reason":"recover_between_shots"}
	var screen := role_anchor(actor,allies,snapshot,"support") if screen_role(actor) else {}
	var escort := role_anchor(actor,allies,snapshot,"transport") if String(actor.get("movement_domain","land"))=="water" else {}
	var target: Dictionary = {}; var best = -INF
	for enemy in enemies:
		var domain = String(enemy.get("movement_domain","land"))
		if domain=="static": domain="land"
		if domain not in actor.get("target_domains",["land","water"]): continue
		var separation = origin.distance_to(Vector2(enemy.get("pos",origin)))
		var engagement: float = reach+maxf(3.0,float(p.get("speed",0.0))*2.0)
		if not screen.is_empty():
			var ranged_threat: bool = float(enemy.get("ai_profile",{}).get("range",0.0))>2.0 or "converter" in enemy.get("behavior_tags",[])
			var hostile_reach := maxf(float(enemy.get("ai_profile",{}).get("range",0.0)),8.0 if "converter" in enemy.get("behavior_tags",[]) else 0.0)
			if ranged_threat and Vector2(enemy["pos"]).distance_to(Vector2(screen["position"]))<hostile_reach+4.0:
				# A screen closes with a ranged attacker instead of standing
				# idle under its fire. Fast harmless decoys remain filtered below.
				engagement=maxf(engagement,minf(8.0,hostile_reach+1.5))
		if separation>engagement: continue
		var contact=reach+float(actor.get("footprint_radius",0.3))+float(enemy.get("footprint_radius",0.3))+0.15
		if domain!=String(actor.get("movement_domain","land")) and separation>contact: continue
		if not screen.is_empty() and separation>contact and float(enemy.get("ai_profile",{}).get("speed",0.0))>maxf(0.1,float(p.get("speed",0.0)))*1.15:
			var threat_distance := Vector2(enemy["pos"]).distance_to(Vector2(screen["position"]))
			if threat_distance>maxf(5.0,float(enemy.get("ai_profile",{}).get("range",0.0))+2.0): continue
		if separation>contact and not locally_reachable(actor,enemy,snapshot,contact): continue
		var remaining = float(enemy.get("hp",enemy.get("ai_profile",{}).get("max_hp",1.0)))-float(reserved_damage.get(int(enemy["id"]),0.0))
		if remaining<=0.0: continue
		var score = Combat.dps(actor,enemy)*8.0/maxf(1.0,remaining)-separation*0.4
		if bool(enemy.get("combat_enabled",false)): score+=5.0
		if not screen.is_empty(): score+=maxf(0.0,6.0-Vector2(enemy["pos"]).distance_to(Vector2(screen["position"])))*2.0
		if String(actor.get("movement_domain","land"))=="water":
			if "transport" in enemy.get("behavior_tags",[]): score+=10.0
			if not escort.is_empty() and bool(enemy.get("combat_enabled",false)) and Vector2(enemy["pos"]).distance_to(Vector2(escort["position"]))<float(enemy.get("ai_profile",{}).get("range",0.0))+3.0: score+=12.0
		if siege_role(actor) and String(state.goal.get("strategic_plan",""))=="siege" and String(enemy.get("kind","")) in ["tower","wall","gate","town_center"]: score+=12.0
		if "converter" in enemy.get("behavior_tags",[]) or float(enemy.get("ai_profile",{}).get("blast_range",0.0))>0.0: score+=12.0
		if String(state.goal.get("strategic_plan",""))=="pressure" and bool(enemy.get("components",{}).get("worker",{}).get("enabled",false)): score+=8.0
		if score>best: best=score; target=enemy
	if target.is_empty():
		if not screen.is_empty():
			var front := (Vector2(nearest["pos"])-Vector2(screen["position"])).normalized()
			var lateral := float(posmod(int(actor.get("id",0)),3)-1)*0.8
			var guard_point := Vector2(screen["position"])+front*2.0+front.orthogonal()*lateral
			if origin.distance_to(guard_point)>1.25: return role_move(guard_point,actor,snapshot,"screen_ranged_support",86)
			if String(actor.get("task","")) in ["attack","move","attack_move"]: return {"type":"hold","priority":86,"reason":"retain_screen"}
		return {}
	var blast = float(p.get("blast_range",0.0))
	if blast>0.0:
		var target_position = Vector2(target["pos"])
		if allies.any(func(ally): return int(ally.get("id",-1))!=int(actor["id"]) and Vector2(ally.get("pos",Vector2.ZERO)).distance_to(target_position)<blast):
			var point = movement_point(origin+(origin-target_position).normalized()*2.0,actor,snapshot)
			return {"type":"move","position":point,"priority":90,"reason":"avoid_friendly_blast"} if point is Vector2 else {}
		if enemies.filter(func(e): return Vector2(e.get("pos",Vector2.ZERO)).distance_to(target_position)<blast).size()>=2: return {"type":"attack_ground","position":target_position,"priority":85,"reason":"visible_cluster"}
	if int(actor.get("target_id",-1))==int(target["id"]) and String(actor.get("task",""))=="attack": return {}
	return {"type":"attack","target_id":int(target["id"]),"target":target,"priority":80,"reason":"focus_without_overkill"}

static func locally_reachable(actor: Dictionary,target: Dictionary,snapshot: Dictionary,reach: float) -> bool:
	var domain=String(actor.get("movement_domain","land"))
	var origin=Vector2(actor.get("pos",Vector2.ZERO)); var destination=Vector2(target.get("pos",Vector2.ZERO))
	var start=Vector2i(origin.floor())
	var radius=reach+0.5
	if (Vector2(start)+Vector2(0.5,0.5)).distance_to(destination)<=radius: return true
	if not is_finite(radius): return false
	var cache: Dictionary=snapshot.get("_micro_floods",{})
	var key: Array=[domain,start]
	var search: Dictionary=cache.get(key,{})
	if search.is_empty():
		search={"processed":{},"visited":{start:true},"queue":[start],"cursor":0}
		if snapshot.has("_micro_floods") and cache.size()<64: cache[key]=search
	var processed: Dictionary=search["processed"]
	var first=Vector2i((destination-Vector2.ONE*(radius+1.0)).floor())
	var last=Vector2i((destination+Vector2.ONE*(radius+1.0)).ceil())
	if processed.size()<(last.x-first.x+1)*(last.y-first.y+1):
		for cell in processed:
			if (Vector2(cell)+Vector2(0.5,0.5)).distance_to(destination)<=radius: return true
	else:
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var cell=Vector2i(x,y)
				if processed.has(cell) and (Vector2(cell)+Vector2(0.5,0.5)).distance_to(destination)<=radius: return true
	var cells: Dictionary=snapshot.get("_micro_cells",{}).get(domain,{})
	var visited: Dictionary=search["visited"]; var queue: Array=search["queue"]; var cursor=int(search["cursor"])
	while cursor<queue.size() and cursor<256:
		var cell: Vector2i=queue[cursor]; cursor+=1
		processed[cell]=true
		# Expand before returning so another target can resume this exact BFS
		# order. Queued but unprocessed cells never count as reachable.
		for delta in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next=cell+delta
			if cells.has(next) and not visited.has(next): visited[next]=true; queue.append(next)
		if (Vector2(cell)+Vector2(0.5,0.5)).distance_to(destination)<=radius:
			search["cursor"]=cursor
			return true
	search["cursor"]=cursor
	return false

func projectile_dodge(actor: Dictionary,snapshot: Dictionary,tick: int,team: int,reaction: int) -> Vector2:
	var origin = Vector2(actor.get("pos",Vector2.ZERO))
	for projectile in snapshot.get("projectiles",[]):
		if int(projectile.get("team",0))==team: continue
		var id = int(projectile.get("id",-1))
		if not threats_seen.has(id): threats_seen[id]=int(snapshot.get("tick",tick))
		if threats_seen.size()>1024:
			var ids: Array = threats_seen.keys()
			ids.sort_custom(func(a,b): return int(threats_seen[a])<int(threats_seen[b]) if int(threats_seen[a])!=int(threats_seen[b]) else int(a)<int(b))
			threats_seen.erase(ids[0])
			if not threats_seen.has(id): continue
		if tick-int(threats_seen[id])<reaction: continue
		var velocity = Vector2(projectile.get("velocity",Vector2.ZERO))
		if velocity.length_squared()<0.01: continue
		var position = Vector2(projectile.get("pos",origin))+velocity*maxf(0.0,float(tick-int(snapshot.get("tick",tick)))/20.0)
		var intercept = (origin-position).dot(velocity)/velocity.length_squared()
		if intercept<0.0 or intercept>1.5: continue
		var closest = position+velocity*intercept
		var radius = maxf(float(projectile.get("blast_range",0.0)),float(projectile.get("radius",0.1)))+float(actor.get("footprint_radius",0.3))+0.25
		if origin.distance_to(closest)<radius:
			var direction = velocity.normalized().orthogonal()
			return direction if posmod(int(actor["id"]),2)==0 else -direction
	return Vector2.ZERO

static func movement_point(desired: Vector2,actor: Dictionary,snapshot: Dictionary) -> Variant:
	var domain = String(actor.get("movement_domain","land"))
	var points: Array = snapshot.get("navigation",{}).get("reachable",{}).get(domain,snapshot.get("navigation",{}).get(domain,[]))
	var best: Variant = null; var distance = 16.0
	var stride = maxi(1,ceili(float(points.size())/256.0))
	for index in range(0,points.size(),stride):
		var point = Vector2(points[index]); var value = point.distance_squared_to(desired)
		if value<distance: distance=value; best=point
	return best

func record_sent(commands: Array,tick: int) -> void:
	for command in commands:
		var metadata: Dictionary = command.params.get("_ai_feedback",{})
		if not metadata.has("micro_signature"): continue
		for id in command.unit_ids: last_orders[int(id)]={"signature":metadata["micro_signature"],"tick":tick}

func canonical_state() -> Dictionary:
	return {"last_orders":last_orders.duplicate(true),"threats_seen":threats_seen.duplicate(true),"cursor":cursor}

func restore_state(data: Dictionary) -> bool:
	if not data.get("last_orders",{}) is Dictionary or not data.get("threats_seen",{}) is Dictionary or data.get("last_orders",{}).size()>4096 or data.get("threats_seen",{}).size()>1024: return false
	last_orders=data.get("last_orders",{}).duplicate(true); threats_seen=data.get("threats_seen",{}).duplicate(true); cursor=int(data.get("cursor",0))
	return cursor>=0


static func siege_role(actor: Dictionary) -> bool:
	var profile: Dictionary=actor.get("ai_profile",{})
	return float(profile.get("range",0.0))>2.0 and (float(profile.get("blast_range",0.0))>0.0 or "siege" in actor.get("behavior_tags",[]) or String(actor.get("kind","")) in ["ballista","helepolis","stone_thrower","catapult","heavy_catapult"])

# Per-plan spatial summaries keep role attention independent of army size.
# A melee escort reads at most nine local cells, rather than every ally.
static func role_context(units: Array,team: int,trusted_owned: bool=false) -> Dictionary:
	var result: Dictionary={}
	for unit in units:
		if String(unit.get("task","")) in ["board","embarked"]: continue
		var components: Dictionary=unit.get("components",{})
		if not trusted_owned and (int(unit.get("team",0))!=team or float(unit.get("hp",0.0))<=0.0 or bool(components.get("worker",{}).get("enabled",false))): continue
		var profile: Dictionary=unit.get("ai_profile",{})
		var tags: Array=unit.get("behavior_tags",[])
		var ranged: bool=float(profile.get("range",0.0))>2.0
		var transport: bool=bool(components.get("cargo",{}).get("enabled",false))
		var caster: bool="converter" in tags or bool(components.get("healing",{}).get("enabled",false))
		var siege: bool=ranged and (float(profile.get("blast_range",0.0))>0.0 or "siege" in tags or String(unit.get("kind","")) in ["ballista","helepolis","stone_thrower","catapult","heavy_catapult"])
		var support := 3.0 if transport or siege else 2.0 if caster else 1.0 if ranged else 0.0
		var front := 1.0 if support==0.0 and bool(unit.get("combat_enabled",false)) else 0.0
		var position := Vector2(unit.get("pos",Vector2.ZERO))
		var domain := String(unit.get("movement_domain","land"))
		if not result.has(domain): result[domain]={}
		var cells: Dictionary=result[domain]
		var cell := bucket(position)
		var entry: Variant=cells.get(cell)
		if entry==null:
			entry=[Vector2.ZERO,0.0,Vector2.ZERO,0.0,Vector2.ZERO,0.0]
			cells[cell]=entry
		var values: Array=entry
		if support>0.0:
			values[0]=Vector2(values[0])+position*support; values[1]=float(values[1])+support
		if front>0.0:
			values[2]=Vector2(values[2])+position*front; values[3]=float(values[3])+front
		if transport:
			values[4]=Vector2(values[4])+position; values[5]=float(values[5])+1.0
	return result

static func role_anchor(actor: Dictionary,allies: Array,snapshot: Dictionary,role: String) -> Dictionary:
	var context: Dictionary
	if snapshot.has("_micro_floods"):
		# Lazily create once, only if an attended actor needs a role. An empty
		# summary is a valid cached result, never a reason for another scan.
		if not snapshot.has("_micro_role_context"): snapshot["_micro_role_context"]=role_context(snapshot.get("_micro_role_units",snapshot.get("units",allies)),int(actor.get("team",0)),snapshot.has("_micro_role_units"))
		context=snapshot["_micro_role_context"]
	else: context=role_context(allies,int(actor.get("team",0)))
	var origin := Vector2(actor.get("pos",Vector2.ZERO))
	var cell := bucket(origin)
	var domain := String(actor.get("movement_domain","land"))
	var best: Dictionary={}; var score := INF
	var cells: Dictionary=context.get(domain,{})
	if cells.is_empty():return {}
	var index := 0 if role=="support" else 2 if role=="front" else 4
	for y in range(cell.y-1,cell.y+2):
		for x in range(cell.x-1,cell.x+2):
			var entry: Array=cells.get(Vector2i(x,y),[])
			if entry.is_empty():continue
			var weight := float(entry[index+1])
			if weight<=0.0: continue
			var position := Vector2(entry[index])/weight
			var distance := origin.distance_to(position)
			if distance>9.0: continue
			var value := distance-minf(2.0,weight*0.25)
			if value<score: score=value; best={"position":position,"weight":weight}
	return best

static func role_move(desired: Vector2,actor: Dictionary,snapshot: Dictionary,reason: String,priority: int) -> Dictionary:
	var point: Variant=movement_point(desired,actor,snapshot)
	if not point is Vector2: return {}
	if snapshot.has("_micro_cells") and not locally_reachable(actor,{"pos":point},snapshot,0.2): return {}
	return {"type":"move","position":point,"priority":priority,"reason":reason}


static func viable_conversion(actor: Dictionary,enemies: Array,conversion: Dictionary) -> bool:
	if not bool(conversion.get("active",false)): return false
	var target_id := int(conversion.get("target_id",actor.get("target_id",-1)))
	var targets: Array=enemies.filter(func(enemy): return int(enemy.get("id",-1))==target_id and not bool(enemy.get("last_known",false)))
	if targets.is_empty(): return false
	var chance := clampf(float(conversion.get("base_success_chance",0.3))*float(conversion.get("chance_multiplier",1.0)),0.0,1.0)
	var target: Dictionary=targets[0]
	if "chariot" in target.get("behavior_tags",[]) or String(target.get("movement_domain","land"))=="water": chance*=float(conversion.get("resistant_target_multiplier",0.25))
	if chance<=0.0: return false
	var incoming := 0.0
	var origin := Vector2(actor.get("pos",Vector2.ZERO))
	for enemy in enemies:
		if not bool(enemy.get("combat_enabled",false)): continue
		var contact := float(enemy.get("ai_profile",{}).get("range",0.0))+float(enemy.get("footprint_radius",0.3))+float(actor.get("footprint_radius",0.3))+0.25
		if origin.distance_to(Vector2(enemy.get("pos",Vector2.ZERO)))<=contact: incoming+=Combat.dps(enemy,actor)
	if incoming<=0.0: return true
	var interval := maxf(0.1,float(conversion.get("chant_interval",1.5)))
	var remaining := maxf(0.0,float(maxi(1,int(conversion.get("min_chants",3))-int(conversion.get("chants",0))))*interval-float(conversion.get("chant_elapsed",0.0)))
	var survival := maxf(0.0,float(actor.get("hp",0.0)))/incoming
	var attempts := clampi(floori((survival-remaining)/interval)+1,0,16)
	return 1.0-pow(1.0-chance,attempts)>=0.25


static func screen_role(actor: Dictionary) -> bool:
	# Pursuit is limited by relative speed and distance in decide(); mobile
	# melee may intercept while slower escorts retain the protective line.
	return bool(actor.get("combat_enabled",false)) and not bool(actor.get("components",{}).get("worker",{}).get("enabled",false)) and not bool(actor.get("components",{}).get("cargo",{}).get("enabled",false)) and String(actor.get("task","")) not in ["board","embarked"] and float(actor.get("ai_profile",{}).get("range",0.0))<=2.0
