extends RefCounted
const Commands:=preload("res://scripts/commands.gd")
const Footprint:=preload("res://scripts/footprint.gd")
const NavigationPolicy:=preload("res://scripts/ai_navigation_policy.gd")
const Access:=preload("res://scripts/ai_construction_access.gd")

static func plan(snapshot: Dictionary,tick: int,team: int,state,reserved: Dictionary) -> Array:
	var result: Array=[]
	if not bool(snapshot.get("navigation",{}).get("cell_geometry",false)):
		return result
	var carriers: Array=[]
	for unit in snapshot.get("units",[]):
		# Most actors carry nothing. Resolve that cheap gate before consulting
		# ownership, orders and profiles for every soldier in a large army.
		var amount: float=float(unit["carried_amount"]) if unit.has("carried_amount") else float(unit.get("ai_profile",{}).get("carried_amount",0))
		if amount<=0.0:continue
		if int(unit.get("team",0))==team and float(unit.get("hp",0))>0 and String(unit.get("task",""))=="idle" and NavigationPolicy.is_failure(String(unit.get("diagnostic_reason",""))):carriers.append(unit)
	if carriers.is_empty():return result
	carriers.sort_custom(func(a,b):return int(a["id"])<int(b["id"]))
	var known_land: Dictionary={}
	var indexed:=false
	var claimed: Array=[]
	var cursor:=posmod(int(state.metrics.get("traffic_cursor",0)),carriers.size())
	state.metrics["traffic_cursor"]=posmod(cursor+mini(8,carriers.size()),carriers.size())
	for offset in range(mini(8,carriers.size())):
		var carrier: Dictionary=carriers[posmod(cursor+offset,carriers.size())]
		var origin:=Vector2(carrier["pos"])
		var blockers: Array=snapshot.get("units",[]).filter(func(u):return Vector2(u["pos"]).distance_squared_to(origin)<=4.0 and int(u.get("team",0))==team and float(u.get("hp",0))>0 and String(u.get("task",""))=="idle" and String(u.get("movement_domain","land"))=="land" and not bool(u.get("components",{}).get("worker",{}).get("enabled",false)) and int(u.get("formation_group_id",-1))<0 and not reserved.has(int(u["id"])) and not state.cooldowns.has("traffic:"+str(int(u["id"]))))
		blockers.sort_custom(func(a,b):return int(a["id"])<int(b["id"]))
		for blocker in blockers.slice(0,3):
			if result.size()>=2:return result
			if not indexed:
				known_land=Access.prepare(snapshot["navigation"]);indexed=true
			var position:=Vector2(blocker["pos"])
			var cell:=Vector2i(position.floor())
			var radius:=float(blocker.get("footprint_radius",0.3))
			var extent:=Vector2i.ONE*ceili(3.0+radius)
			var land:=Access.local_cells(known_land,cell-extent,cell+extent)
			# At most a 2.5-cell displacement is considered. Far bodies cannot
			# intersect it; do not scan a whole army for every candidate point.
			var nearby: Array=snapshot.get("units",[]).filter(func(u):return Vector2(u["pos"]).distance_squared_to(position)<=pow(3.0+radius+float(u.get("footprint_radius",0.3)),2))
			if nearby.size()>128:continue
			var best: Variant=null
			var best_score:=INF
			for y in range(cell.y-2,cell.y+3):
				for x in range(cell.x-2,cell.x+3):
					var point:=Vector2(x+0.5,y+0.5)
					var distance:=position.distance_squared_to(point)
					if distance<0.5625 or distance>6.25 or point.distance_to(origin)<maxf(position.distance_to(origin)+0.35,radius+float(carrier.get("footprint_radius",0.3))+0.25):continue
					# A forward step can move the same blockade farther along the
					# worker's road. Prefer a side pocket when one is reachable.
					var alignment:=(point-position).normalized().dot((position-origin).normalized())
					var score:=distance+4.0*alignment*alignment
					if score>=best_score or not clear_static(position,point,radius,land):continue
					if claimed.any(func(p):return point.distance_squared_to(Vector2(p))<1.0):continue
					if not clear_bodies(blocker,position,point,nearby):continue
					best=point;best_score=score
			if best==null:continue
			var id:=int(blocker["id"])
			result.append(Commands.MoveCommand.new(tick,[id],Vector2(best)))
			claimed.append(best);reserved[id]=true
			state.cooldowns["traffic:"+str(id)]=tick+120
	return result

static func clear_static(start: Vector2,finish: Vector2,radius: float,land: Dictionary) -> bool:
	var minimum:=Vector2i((start.min(finish)-Vector2.ONE*radius).floor())
	var maximum:=Vector2i((start.max(finish)+Vector2.ONE*radius).floor())
	for y in range(minimum.y,maximum.y+1):
		for x in range(minimum.x,maximum.x+1):
			var cell:=Vector2i(x,y)
			if not land.has(cell) and Footprint.segment_cell_distance_squared(start,finish,cell)<radius*radius-0.000001:return false
	return true

static func clear_bodies(unit: Dictionary,start: Vector2,finish: Vector2,units: Array) -> bool:
	for other in units:
		if int(other.get("id",-1))==int(unit["id"]) or float(other.get("hp",0))<=0 or bool(other.get("last_known",false)) or String(other.get("movement_domain","land"))!="land":continue
		var center:=Vector2(other["pos"])
		var radius:=float(unit.get("footprint_radius",0.3))+float(other.get("footprint_radius",0.3))+0.06
		var minimum:=minf(radius*radius,start.distance_squared_to(center))
		if center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center,start,finish))<minimum-0.000001:return false
	return true
