extends Node
# A standalone diagnostic, outside the exported game. Both policies receive
# the same authoritative world and use the normal capture/command pipeline.
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Factory=preload("res://scripts/ai_player_factory.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
const Runtime=preload("res://scripts/ai_runtime_coordinator.gd")
const Decisions=preload("res://scripts/ai_decision_queue.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
const Probe=preload("res://scripts/performance_probe.gd")
const Commands=preload("res://scripts/commands.gd")
const Replay=preload("res://scripts/replay_system.gd")
var runtime
var probe
var gate_calls:=0
var gate_yields:=0
var gate_wait_started: int=-1

func _ready() -> void: call_deferred("run")

func queue_tick(tick: int) -> Variant:
	var started:=Time.get_ticks_usec()
	var result: Variant=runtime.queue_commands(tick)
	probe.observe_microseconds("diagnostic.ai.owner_queue",Time.get_ticks_usec()-started)
	gate_calls+=1
	if result is Dictionary and not bool(result.get("ready",true)):
		gate_yields+=1
		if gate_wait_started<0: gate_wait_started=started
	elif gate_wait_started>=0:
		# Include frame scheduling between first not-ready and accepted boundary.
		probe.observe_microseconds("diagnostic.runtime.apply_gate_wait",Time.get_ticks_usec()-gate_wait_started)
		gate_wait_started=-1
	return result

func run() -> void:
	Engine.max_fps=0
	var input_path:=""; var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): input_path=arg.trim_prefix("--case=")
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	var case: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(input_path))
	var teams:=int(case["teams"]); var side:=int(case["side"]); var count:=int(case.get("units_per_team",500))
	var catalog=Catalog.new(); catalog.load()
	var world=World.new(Vector2i(side,side))
	world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain: Array[int]=[]; terrain.resize(side*side); terrain.fill(0)
	var heights: Array[int]=[]; heights.resize((side+1)*(side+1)); heights.fill(0)
	world.configure_map_data({"terrain_ids":terrain,"vertex_levels":heights})
	world.task_coordinator.enabled=bool(case["threaded"])
	var ais: Array=[]; var groups: Dictionary={}; var contact_groups: Dictionary={}; var march_origins: Dictionary={}
	var authored_workload: Dictionary={"gatherers":0,"marchers":0,"combatants":0,"idle":0}
	for team in range(1,teams+1):
		world.set_team_civilization(team,13); world.set_population_cap(team,count); world.set_population_housing(team,count)
		for resource in range(4): world.set_resource_amount(team,resource,2000)
		var base:=Vector2(6+((team-1)%4)*(side/4),6+((team-1)/4)*(side/2))
		world.add_building(90000+team,"town_center",base,team)
		var resources: Array=[]
		for n in range(20): resources.append(world.add_resource("tree" if n%2==0 else "berries",base+Vector2(4+(n%5)*2.5,4+(n/5)*2.5),500))
		var moving: Array[int]=[]; var contact: Array[int]=[]
		for n in range(count):
			var position:=base+Vector2(2+(n%20)*0.85,8+(n/20)*0.85)
			var in_contact: bool=count>=341 and n>=325 and n<341
			if in_contact:
				# Pair neighbouring opponents in separate contact zones, at legal
				# attack range. The remaining army still marches across the map.
				var pair_index:=int((team-1)/2); var pair_count:=int(teams/2)
				var flank: float=-1.0 if team%2==1 else 1.0
				position=Vector2(side*0.5+flank*(1.2+((n-325)%4)*0.7),side*float(pair_index+1)/float(pair_count+1)+int((n-325)/4)*0.8)
			elif n<100 and not bool(case.get("all_active",false)):
				# Some food gatherers start by their ordinary work site so the
				# short fixture covers harvesting as well as approaching trees.
				var angle: float=TAU*float(int(n/20))/5.0
				position=Vector2(resources[n%resources.size()]["pos"])+Vector2(cos(angle),sin(angle))*1.05
			position.x=clampf(position.x,1.5,side-1.5); position.y=clampf(position.y,1.5,side-1.5)
			var actor: Dictionary=world.add_unit(team,"villager" if n<225 else "archer" if n%2==0 else "clubman",position,false)
			if in_contact:
				contact.append(int(actor["id"])); authored_workload["combatants"]+=1
			elif bool(case.get("all_active",false)) or (n>=225 and n<325):
				moving.append(int(actor["id"])); march_origins[int(actor["id"])]=position; authored_workload["marchers"]+=1
			elif n<100:
				world.assign_command_gather([actor],int(resources[n%resources.size()]["id"])); authored_workload["gatherers"]+=1
			else: authored_workload["idle"]+=1
		groups[team]=moving; contact_groups[team]=contact
		var policy:=Policy.resolve()
		if String(case["algorithm"])=="competitive_v2":policy.merge(policy.get("competitive_parameters",{}),true)
		policy["algorithm_version"]=String(case["algorithm"]);policy["policy_seed"]=41721
		ais.append(Factory.create({"team":team,"ai":policy}))
	world.update_fog_of_war()
	var controller=Controller.new(world); controller.set_speed_multiplier(1.0)
	probe=Probe.new(4096); controller.performance_probe=probe; world.set_performance_probe(probe)
	for team in groups:
		if not groups[team].is_empty(): controller.enqueue_command(Commands.AttackMoveCommand.new(0,groups[team],Vector2(side/2,side/2)),true,int(team))
		var other: int=int(team)+1 if int(team)%2==1 else int(team)-1
		if not contact_groups[team].is_empty():
			for index in range(contact_groups[team].size()):
				var ids: Array[int]=[int(contact_groups[team][index])]
				controller.enqueue_command(Commands.AttackCommand.new(0,ids,int(contact_groups[other][index])),true,int(team))
	runtime=Runtime.new(); var decisions=Decisions.new()
	runtime.configure(world,controller,ais,decisions,Store.new(),world.task_coordinator)
	controller.set_before_fixed_tick(queue_tick)
	var phases: Array=[]; var memory: Array=[]; var snapshots: Array=[]
	var started:=Time.get_ticks_msec(); var progress:=started; var last_tick:=0; var warm:=false
	var ticks:=int(case.get("ticks",100)); var cold_ticks:=int(case.get("cold_ticks",20))
	memory.append({"tick":0,"godot_static_bytes":OS.get_static_memory_usage()})
	while controller.tick_index<ticks and runtime.error.is_empty() and Time.get_ticks_msec()-started<int(case.get("timeout_seconds",1800))*1000:
		controller.advance_frame(0.05,1,2,1)
		if controller.tick_index!=last_tick: last_tick=controller.tick_index; progress=Time.get_ticks_msec()
		elif Time.get_ticks_msec()-progress>120000: break
		if snapshots.size()<3 and decisions.active and not decisions.records.is_empty() and not decisions.records[0]["input"].is_empty():
			var captured_tick:=int(decisions.source_tick)
			if snapshots.is_empty() or captured_tick>int(snapshots.back()["tick"])+20:
				snapshots.append({"tick":captured_tick,"serialized_input_bytes":var_to_bytes(decisions.records[0]["input"]).size()})
		if not warm and controller.tick_index>=cold_ticks:
			phases.append({"phase":"cold","until_tick":controller.tick_index,"profile":probe.report(),"gate_calls":gate_calls,"gate_yields":gate_yields})
			probe=Probe.new(4096); controller.performance_probe=probe; world.set_performance_probe(probe)
			gate_calls=0; gate_yields=0; warm=true
			memory.append({"tick":controller.tick_index,"godot_static_bytes":OS.get_static_memory_usage()})
		await get_tree().process_frame
	phases.append({"phase":"warm","until_tick":controller.tick_index,"profile":probe.report(),"gate_calls":gate_calls,"gate_yields":gate_yields})
	memory.append({"tick":controller.tick_index,"godot_static_bytes":OS.get_static_memory_usage()})
	var state_hash:=Replay.new().world_state_hash(world,controller.tick_index,controller)
	var ai_state_hash:=hash(ais.map(func(ai): return ai.canonical_state()))
	var passed: bool=controller.tick_index==ticks and runtime.error.is_empty()
	var active_parameters:Array=[]
	if String(case["algorithm"])=="competitive_v2":
		for ai in ais:active_parameters.append(ai.economic_policy.duplicate(true))
	var report:={"fingerprint":case["fingerprint"],"case":case,"passed":passed,"tick":controller.tick_index,"seconds":float(Time.get_ticks_msec()-started)/1000.0,"runtime_error":runtime.error,"phases":phases,"memory":memory,"snapshots":snapshots,"world_hash":state_hash,"ai_state_hash":ai_state_hash,"runtime":{"release":not OS.has_feature("editor"),"executable":OS.get_executable_path()},"native":ClassDB.class_exists("RoRPathKernel"),"scope":"headless fixed mixed fixture; all_active explicitly labelled; no rendered FPS claim"}
	report["active_parameters"]=active_parameters
	var workload_events: Dictionary={}
	for event in controller.events_after(0):
		var event_type: String=String(event.get("type",""))
		workload_events[event_type]=int(workload_events.get(event_type,0))+1
	var moved_marchers:=0
	for entity_id in march_origins:
		var unit: Variant=world.find_unit(int(entity_id))
		if unit!=null and Vector2(unit["pos"]).distance_squared_to(march_origins[entity_id])>0.04: moved_marchers+=1
	authored_workload["moved_marchers"]=moved_marchers
	report["workload_events"]=workload_events; report["workload"]=authored_workload
	if count>=341:
		var workload_passed: bool=int(workload_events.get("attack",0))>0 and int(workload_events.get("damage",0))>0 and moved_marchers>0
		if not bool(case.get("all_active",false)): workload_passed=workload_passed and int(workload_events.get("resource_gathered",0))>0
		report["workload_passed"]=workload_passed; passed=passed and workload_passed; report["passed"]=passed
	controller.set_before_fixed_tick(Callable()); runtime.shutdown(); world.shutdown_derived_state()
	var file:=FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	print("AI_PERFORMANCE ",case["algorithm"]," ",teams,"x",count," ",side," threaded=",case["threaded"]," passed=",passed)
	# Dispose private planners and their retained immutable DTOs while the
	# engine worker pool still exists, before SceneTree shutdown starts.
	ais.clear(); controller=null; world=null; decisions=null; runtime=null; probe=null
	await get_tree().process_frame
	get_tree().quit(0 if passed else 1)
