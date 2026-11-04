# Exact arena-only adapter. Frozen policy source remains untouched. For every
# remembered target retain its exact nearest legal approach (including ties).
# The frozen algorithm cannot choose any other point from the full array.
extends "res://ai_baselines/v1/scripts/ai_strategy_state.gd"

func choose_goal(snapshot: Dictionary,team: int,policy: Dictionary,decision: int) -> Dictionary:
	var known: Array=enemies(int(snapshot.get("tick",0)),policy)
	if known.is_empty(): return super.choose_goal(snapshot,team,policy,decision)
	var maximum_range:={"land":0.0,"water":0.0}
	for unit in snapshot.get("units",[]):
		var domain:=String(unit.get("movement_domain","land"))
		if int(unit.get("team",0))==team and domain in maximum_range and bool(unit.get("combat_enabled",false)) and not bool(unit.get("components",{}).get("worker",{}).get("enabled",false)):
			maximum_range[domain]=maxf(float(maximum_range[domain]),float(Combat.profile(unit).get("range",0.0)))
	var reduced: Dictionary={}
	for domain in ["land","water"]:
		var buckets: Dictionary={}
		var points: Array=snapshot.get("navigation",{}).get("reachable",{}).get(domain,snapshot.get("navigation",{}).get(domain,[]))
		for value in points:
			var cell:=Vector2i(Vector2(value).floor())
			if not buckets.has(cell): buckets[cell]=[]
			buckets[cell].append(value)
		var kept: Dictionary={}
		for actor in known:
			var target:=Vector2(actor.get("pos",Vector2.ZERO))
			var radius:=float(actor.get("footprint_radius",1.0))+maxf(2.0,float(maximum_range[domain]))
			var low:=Vector2i((target-Vector2.ONE*radius).floor()); var high:=Vector2i((target+Vector2.ONE*radius).floor())
			var best: Variant=null; var distance:=radius*radius
			for y in range(low.y,high.y+1):
				for x in range(low.x,high.x+1):
					for value in buckets.get(Vector2i(x,y),[]):
						var point:=Vector2(value); var candidate:=point.distance_squared_to(target)
						if candidate<=distance and (best==null or candidate<distance or (candidate==distance and (point.y<Vector2(best).y or point.y==Vector2(best).y and point.x<Vector2(best).x))): best=point; distance=candidate
			if best!=null: kept[best]=true
		var values: Array=kept.keys(); values.sort_custom(func(a,b): return a.y<b.y if a.y!=b.y else a.x<b.x)
		reduced[domain]=values
	var compact:=snapshot.duplicate(); compact["navigation"]=snapshot.get("navigation",{}).duplicate()
	compact["navigation"]["reachable"]=reduced
	return super.choose_goal(compact,team,policy,decision)
