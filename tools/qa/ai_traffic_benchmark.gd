extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const StuckRecovery=preload("res://scripts/stuck_recovery.gd")
const Probe=preload("res://scripts/performance_probe.gd")
var world
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=0
	var catalog=Catalog.new(); catalog.load()
	var rows: Array=[]; var correct:=true
	for shape in ["clear","short_wall","long_wall"]:
		world=World.new(Vector2i(24,24)); world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		world.set_team_civilization(1,13)
		var actor: Dictionary=world.add_unit(1,"villager",Vector2(5.5,7.5),false)
		var neighbors: Array=[]
		if shape!="clear":
			for index in range(8 if shape=="short_wall" else 30):
				neighbors.append(world.add_unit(1,"villager",Vector2(8.5,(5.0 if shape=="short_wall" else 1.5)+index*0.7),false))
		var results: Dictionary={}; var signatures: Dictionary={}
		for mode in ["reference","heap"]:
			var timings: Array=[]; var outcomes: Array=[]
			for iteration in range(17):
				actor["task"]="gather"; actor["pos"]=Vector2(5.5,7.5); actor["destination"]=Vector2(15.5,7.5); actor["target"]=actor["destination"]; actor["path"]=[]; actor["path_index"]=0
				var started:=Time.get_ticks_usec()
				var found: bool=reference_route(actor,world.pathfinder,neighbors) if mode=="reference" else world.movement_system._try_local_work_route(actor,world.pathfinder,neighbors)
				var elapsed:=Time.get_ticks_usec()-started
				if iteration>0: timings.append(elapsed)
				outcomes.append(found)
				if found:
					correct=correct and not actor["path"].is_empty() and Vector2(actor["path"].back()).distance_to(Vector2(15.5,7.5))<0.12
					correct=correct and world.movement_system._work_segment_clear(actor,Vector2(5.5,7.5),actor["path"][0],neighbors)
			results[mode]=Probe.summarize(timings); signatures[mode]=outcomes
		correct=correct and signatures["reference"]==signatures["heap"]
		rows.append({"shape":shape,"microseconds":results,"same_reachability":signatures["reference"]==signatures["heap"],"reachable":signatures["heap"][0]})
		world.shutdown_derived_state(); world=null
		await process_frame
	var file:=FileAccess.open("res://qa/ai-competitive/competitive-20261030/traffic_heap_benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"correct":correct,"rows":rows,"scope":"same inputs and native geometry, old bounded sort versus heap; warm16 samples, limit256; not game FPS"},"\t")); file.close()
	print("TRAFFIC_HEAP ",correct," ",rows)
	quit(0 if correct else 1)

func reference_route(unit: Dictionary,planner,neighbors: Array) -> bool:
	# Search only the immediate traffic neighbourhood. Static A* alone routes
	# through harvesting bodies; one straight detour waypoint cannot get around
	# a concave group of workers in a forest/mineral passage.
	var origin:=Vector2(unit["pos"]); var destination:=Vector2(unit["destination"])
	var radius:=float(unit["footprint_radius"]); var domain:=String(unit["movement_domain"]); var restriction:=int(unit["terrain_restriction"])
	var goal:=destination
	if origin.distance_to(goal)>5.0:
		var leg:=Vector2(unit["target"])-origin
		if leg.length()<0.2: return false
		goal=origin+leg.normalized()*minf(5.0,leg.length())
	var step:=maxf(0.5,radius)
	var open: Array=[Vector2i.ZERO]; var previous: Dictionary={}; var costs: Dictionary={Vector2i.ZERO:0.0}; var expanded:=0
	var directions: Array=[Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,1),Vector2i(-1,1),Vector2i(-1,-1),Vector2i(1,-1)]
	while not open.is_empty() and expanded<256:
		open.sort_custom(func(a,b):
			var av:=float(costs[a])+(origin+Vector2(a)*step).distance_to(goal); var bv:=float(costs[b])+(origin+Vector2(b)*step).distance_to(goal)
			return av<bv if not is_equal_approx(av,bv) else a.y<b.y if a.y!=b.y else a.x<b.x)
		var cell: Vector2i=open.pop_front(); var point:=origin+Vector2(cell)*step; expanded+=1
		if cell!=Vector2i.ZERO and point.distance_to(goal)<=1.5 and planner.is_segment_walkable(point,goal,radius,domain,restriction) and world.movement_system._work_segment_clear(unit,point,goal,neighbors):
			var local: Array[Vector2]=[goal]
			var cursor:=cell
			while cursor!=Vector2i.ZERO:
				local.push_front(origin+Vector2(cursor)*step); cursor=previous[cursor]
			if goal.distance_squared_to(destination)>0.0001:
				var tail: Array[Vector2]=planner.find_path(goal,destination,domain,restriction,radius)
				if tail.is_empty() or tail.back().distance_squared_to(destination)>0.0144: continue
				local.append_array(tail)
			var prepared: Dictionary=world.navigation_service.register_resolved_path(int(unit["id"]),origin,destination,local,domain,restriction,"work_traffic_local",radius)
			if world.movement_system.assign_unit_destination(unit,destination,false,false,prepared):
				StuckRecovery.reset(unit); world.set_entity_field(unit,"diagnostic_reason","work_traffic_local"); return true
		for direction in directions:
			var next: Vector2i=cell+direction
			if abs(next.x)>12 or abs(next.y)>12: continue
			var candidate:=origin+Vector2(next)*step; var cost:=float(costs[cell])+Vector2(direction).length()*step
			if costs.has(next) and float(costs[next])<=cost: continue
			if not planner.is_segment_walkable(point,candidate,radius,domain,restriction) or not world.movement_system._work_segment_clear(unit,point,candidate,neighbors): continue
			costs[next]=cost; previous[next]=cell
			if next not in open: open.append(next)
	return false
