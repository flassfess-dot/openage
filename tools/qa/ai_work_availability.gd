# Evaluator only. Never asks the live reservation/assignment APIs for a slot.
extends RefCounted
const Approach = preload("res://scripts/building_approach_geometry.gd")
const SAMPLE_TICKS = 20
const MAX_RESOURCE_CHECKS = 256
var last_tick := -1
var previous: Dictionary = {}
var totals: Dictionary = {}

func consume(world, tick: int, force: bool = false) -> void:
	if last_tick >= 0 and not force and tick-last_tick < SAMPLE_TICKS: return
	if last_tick >= 0:
		var elapsed := maxi(0,tick-last_tick)
		for team in previous:
			if not totals.has(team): totals[team]={"worker_ticks":0,"available_ticks":0,"idle_available_ticks":0,"unknown_ticks":0,"idle_unknown_ticks":0}
			for key in previous[team]: totals[team][key]+=int(previous[team][key])*elapsed
	last_tick=tick
	previous={}
	var resources: Array=world.get_resources().duplicate()
	var buildings: Array=world.get_buildings()
	for building in buildings:
		if bool(building.get("harvestable",false)) and int(building.get("amount",0))>0: resources.append(building)
	for worker in world.get_units():
		if float(worker.get("hp",0))<=0.0 or not bool(worker.get("components",{}).get("worker",{}).get("enabled",false)): continue
		var team:=int(worker.get("team",0))
		if team<=0: continue
		if not previous.has(team): previous[team]={"worker_ticks":0,"available_ticks":0,"idle_available_ticks":0,"unknown_ticks":0,"idle_unknown_ticks":0}
		var row: Dictionary=previous[team]
		row["worker_ticks"]+=1
		var idle:=String(worker.get("task","idle")) in ["idle","hold"]
		# Reservations belong to individual workers. A neighbour's own reserved
		# slot must not make this idle worker's job appear available.
		if confirmed_work(world,worker,resources,buildings):
			row["available_ticks"]+=1
			if idle: row["idle_available_ticks"]+=1
		else:
			# Failure to prove a harvest route is not proof of no work: building,
			# repair, a dock's fractional berth or a search limit may still matter.
			row["unknown_ticks"]+=1
			if idle: row["idle_unknown_ticks"]+=1

static func connected(world,worker: Dictionary,point: Vector2) -> bool:
	var radius:=float(worker.get("footprint_radius",0.3))
	var domain:=String(worker.get("movement_domain","land"))
	var restriction:=int(worker.get("terrain_restriction",-1))
	return world.navigation_grid.is_position_walkable_for(point,radius,domain,restriction) and world.pathfinder.can_reach(Vector2(worker["pos"]),point,domain,restriction,radius)

static func allowed_depots(world,worker: Dictionary,profile: Dictionary) -> Dictionary:
	var source_id:=int(profile.get("role_source_unit_id",-1))
	var source: Dictionary=world.object_record_by_id(source_id,int(worker["team"])) if source_id>=0 else {}
	var ids: Array=source.get("resources",{}).get("drop_site_ids",worker.get("components",{}).get("worker",{}).get("drop_site_ids",[]))
	var result: Dictionary={}
	for id in ids:
		if int(id)>=0: result[int(id)]=true
	return result

static func has_depot(world,worker: Dictionary,type_id: int,allowed: Dictionary,buildings: Array) -> bool:
	for building in buildings:
		if int(building.get("team",0))!=int(worker["team"]) or not world.dropoff_accepts_resource(building,type_id,allowed): continue
		var candidates:=Approach.perimeter_candidates(worker,building,world.map_size)
		var reservations: Dictionary=world.building_approach_slots.get(int(building["id"]),{}).duplicate()
		reservations.erase(int(worker["id"]))
		for point in world.available_approach_slots(worker,candidates,reservations,true):
			if connected(world,worker,point): return true
	return false

static func confirmed_work(world,worker: Dictionary,resources: Array,buildings: Array) -> bool:
	if float(worker.get("carried_amount",0.0))>0.0:
		var type_id:=int(worker.get("carried_resource_type_id",-1))
		if type_id not in [0,1,2,3]: return false
		var profile: Dictionary={}
		if int(worker.get("worker_role_source_unit_id",-1))<0: profile=world.worker_role_system.profile_for_resource_type(worker,type_id)
		return has_depot(world,worker,type_id,allowed_depots(world,worker,profile),buildings)
	var checked:=0
	var depot_cache: Dictionary={}
	for resource in resources:
		if checked>=MAX_RESOURCE_CHECKS: return false
		if int(resource.get("amount",0))<=0 or not world.resource_accessible_to_team(resource,int(worker["team"])) or not world.resource_allows_worker(resource,worker): continue
		if world.fog_of_war.state_at_world(int(worker["team"]),Vector2(resource["pos"]))==0: continue
		checked+=1
		var profile: Dictionary=world.worker_role_system.profile_for_resource(worker,resource)
		var allowed:=allowed_depots(world,worker,profile)
		var type_id:=int(resource.get("resource_type_id",-1))
		if type_id not in [0,1,2,3]: continue
		var depot_key:=str([type_id,allowed])
		if not depot_cache.has(depot_key): depot_cache[depot_key]=has_depot(world,worker,type_id,allowed,buildings)
		if not bool(depot_cache[depot_key]): continue
		var metadata: Dictionary=world.data_repository.runtime_metadata(String(resource.get("kind","")))
		var candidates: Array[Vector2]=world.resource_approach_candidates(worker,resource,metadata)
		var reservations: Dictionary=world.resource_approach_slots.get(int(resource["id"]),{}).duplicate()
		reservations.erase(int(worker["id"]))
		for point in world.available_approach_slots(worker,candidates,reservations,true):
			if connected(world,worker,point): return true
	return false

func report() -> Dictionary:
	var result:=totals.duplicate(true)
	for team in result:
		var row: Dictionary=result[team]
		var available:=float(row["available_ticks"])
		var idle:=float(row["idle_available_ticks"])
		var unknown:=float(row["unknown_ticks"])
		var idle_unknown:=float(row["idle_unknown_ticks"])
		row["confirmed_work_idle_ratio"]=idle/available if available>0 else null
		row["conditional_idle_lower_bound"]=idle/maxf(1.0,available+unknown-idle_unknown)
		row["conditional_idle_upper_bound"]=(idle+idle_unknown)/maxf(1.0,available+idle_unknown)
		row["confirmed_worker_time_coverage"]=available/maxf(1.0,float(row["worker_ticks"]))
		row["scope"]="Sampled every20 fixed ticks. Known harvest/cargo job, compatible own depot, currently free resource/depot approach and static physical path. Intermediate transient crowds are outside the path model. Unproved jobs remain UNKNOWN, including build/repair, limits and alternate dock berths. Bounds include all unknown assignments; no game decision reads this evaluator."
	return result
