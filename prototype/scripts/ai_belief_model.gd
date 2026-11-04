extends RefCounted

const ROUTE_NEIGHBORS := [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN,Vector2i(-1,-1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(1,1)]
const MAX_ROUTE_CELLS := 64
const MAX_ROUTE_HYPOTHESES := 16
const ROUTES_PER_OBSERVATION := 2

static func permanent(actor: Dictionary) -> bool:
	return String(actor.get("entity_type","")) == "building" or String(actor.get("movement_domain","")) == "static"

static func confidence(entry: Dictionary, tick: int, lifetime: int) -> float:
	if bool(entry.get("observed",false)): return 1.0
	if permanent(entry.get("entity",{})): return 0.8
	return clampf(1.0-float(tick-int(entry.get("seen_tick",0)))/float(maxi(1,lifetime)),0.0,1.0)

static func uncertainty(entry: Dictionary, tick: int) -> float:
	if permanent(entry.get("entity",{})) or bool(entry.get("observed",false)): return 0.0
	return minf(64.0,maxf(0.0,float(tick-int(entry.get("seen_tick",0)))/20.0)*float(entry.get("entity",{}).get("ai_profile",{}).get("speed",0.8)))


# A bounded hypothesis through this observer's learned terrain. It is never
# permission for a command or proof that an unseen unit cannot be elsewhere:
# unknown terrain and a gate changed after the sighting remain uncertain.
static func route_area(entry: Dictionary, tick: int, navigation: Dictionary) -> Dictionary:
	var actor: Dictionary=entry.get("entity",{})
	var domain:=String(actor.get("movement_domain","land"))
	if permanent(actor) or bool(entry.get("observed",false)) or domain not in ["land","water"] or not bool(navigation.get("cell_geometry",false)): return {}
	var known: Array=navigation.get(domain,[])
	if known.is_empty(): return {}
	var frontier: Array=navigation.get("frontier",{}).get(domain,[])
	var origin:=Vector2(actor.get("pos",Vector2.ZERO))
	var start:=Vector2i(origin.floor())
	var radius:=uncertainty(entry,tick)
	var max_steps:=ceili(radius)+1
	var radius_squared:=(radius+0.72)*(radius+0.72)
	var queue: Array[Vector2i]=[start]
	var depth: Array[int]=[0]
	var visited: Dictionary={start:true}
	var membership: Dictionary={}
	var head:=0
	var points: Array[Vector2]=[]
	var start_known:=_known(known,start,membership)
	var unknown_exit:=not start_known
	var truncated:=false
	# Empty now is not empty forever. Keep the last sighting untouched, and
	# exclude its origin only when this observation actually disproves it.
	var origin_empty_now:=bool(entry.get("origin_disproved",false)) and int(entry.get("origin_disproved_tick",-1))==tick
	while head<queue.size():
		var cell:=queue[head]
		var steps:=depth[head]
		head+=1
		if not frontier.is_empty() and _ordered_contains(frontier,cell): unknown_exit=true
		if (cell!=start or start_known) and not (cell==start and origin_empty_now): points.append(Vector2(cell)+Vector2(0.5,0.5))
		if steps>=max_steps: continue
		for offset in ROUTE_NEIGHBORS:
			var next: Vector2i=cell+offset
			if visited.has(next) or origin.distance_squared_to(Vector2(next)+Vector2(0.5,0.5))>radius_squared: continue
			if not _known(known,next,membership): continue
			if offset.x!=0 and offset.y!=0 and (not _known(known,cell+Vector2i(offset.x,0),membership) or not _known(known,cell+Vector2i(0,offset.y),membership)): continue
			if queue.size()>=MAX_ROUTE_CELLS:
				truncated=true
				continue
			visited[next]=true
			queue.append(next)
			depth.append(steps+1)
	return {"tick":tick,"seen_tick":int(entry.get("seen_tick",0)),"domain":domain,"radius":radius,"points":points,"expanded":head,"membership_queries":membership.size(),"unknown_exit":unknown_exit,"truncated":truncated,"hypothesis_only":true}


static func _known(ordered: Array, cell: Vector2i, cache: Dictionary) -> bool:
	if not cache.has(cell): cache[cell]=_ordered_contains(ordered,cell)
	return bool(cache[cell])


static func _ordered_contains(ordered: Array, cell: Vector2i) -> bool:
	var target:=Vector2(cell)+Vector2(0.5,0.5)
	var first:=0
	var last:=ordered.size()
	while first<last:
		var middle: int=(first+last)/2
		var point:=Vector2(ordered[middle])
		if point.y<target.y or (point.y==target.y and point.x<target.x): first=middle+1
		else: last=middle
	return first<ordered.size() and Vector2(ordered[first])==target


static func valid_route_area(area: Variant) -> bool:
	if not area is Dictionary: return false
	if area.is_empty(): return true
	if not area.get("points") is Array or area["points"].size()>MAX_ROUTE_CELLS: return false
	if String(area.get("domain","")) not in ["land","water"] or not bool(area.get("hypothesis_only",false)): return false
	if int(area.get("tick",-1))<int(area.get("seen_tick",0)) or int(area.get("seen_tick",-1))<0: return false
	if not is_finite(float(area.get("radius",-1.0))) or float(area.get("radius",-1.0))<0.0 or float(area["radius"])>64.0: return false
	if int(area.get("expanded",-1))<0 or int(area["expanded"])>MAX_ROUTE_CELLS or int(area.get("membership_queries",-1))<0 or int(area["membership_queries"])>MAX_ROUTE_CELLS*12: return false
	for flag in ["unknown_exit","truncated","hypothesis_only"]:
		if not area.get(flag) is bool: return false
	for point in area["points"]:
		if not point is Vector2 or not point.is_finite(): return false
	return true

static func importance(entry: Dictionary, tick: int) -> float:
	var actor: Dictionary = entry.get("entity",{})
	var score = 100.0 if permanent(actor) else 20.0
	if bool(actor.get("components",{}).get("conversion",{}).get("enabled",false)): score += 80.0
	if float(actor.get("components",{}).get("combat",{}).get("blast_range",0.0)) > 0.0: score += 80.0
	return score + (40.0 if bool(entry.get("observed",false)) else 0.0) - minf(20.0,float(tick-int(entry.get("seen_tick",0)))*0.01)

static func summary(actors: Array) -> Dictionary:
	var result: Dictionary = {}
	for actor in actors:
		var key = "%d:%s:%s" % [int(actor.get("team",0)),String(actor.get("kind","")),str(Vector2i(Vector2(actor.get("pos",Vector2.ZERO))/16.0))]
		if not result.has(key): result[key] = {"count":0,"confidence":0.0,"position":actor.get("pos",Vector2.ZERO),"kind":actor.get("kind","")}
		result[key]["count"] += 1
		result[key]["confidence"] += float(actor.get("confidence",1.0))
	return result
