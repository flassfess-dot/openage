extends SceneTree
const Settings := preload("res://scripts/skirmish_settings.gd")
const Policy := preload("res://scripts/skirmish_ai_policy.gd")
const Factory := preload("res://scripts/ai_player_factory.gd")
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Runtime := preload("res://scripts/ai_runtime_coordinator.gd")
const Decisions := preload("res://scripts/ai_decision_queue.gd")
const Store := preload("res://scripts/ai_observation_store.gd")
const Probe := preload("res://scripts/performance_probe.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var algorithm := "competitive_v2"; var civilization := 8; var output := "res://qa/ai-competitive/competitive-20261030/opening.json"; var maximum_ticks:=36000
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--algorithm="): algorithm=arg.trim_prefix("--algorithm=")
		if arg.begins_with("--civilization="): civilization=int(arg.trim_prefix("--civilization="))
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--max-ticks="): maximum_ticks=int(arg.trim_prefix("--max-ticks="))
	var settings := Settings.default_settings(); settings["map_size_id"]="compact"; settings["seed"]=41721; settings["players"][1]["civilization_id"]=civilization
	var built := Settings.build(settings)
	if not bool(built.get("valid",false)): push_error(str(built.get("errors",[]))); quit(1); return
	var catalog := Catalog.new(); catalog.load()
	var world := World.new(built["map_data"]["size"])
	world.set_gamespec(catalog.gamespec_data); world.set_terrain_catalog(catalog.terrain_catalog_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world,built["definition"],built["map_data"])
	world.task_coordinator.enabled=false
	# This is the same passive, durable opponent as the original economy probe.
	# Its HP cannot increase AI resources or shorten any production/research time.
	for actor in world.get_units()+world.get_buildings():
		if int(actor.get("team",0))==1:
			actor["hp"]=100000.0
			actor["combat_enabled"]=false
			actor["stance"]="passive"
	var definition: Dictionary = built["definition"]["players"][1].duplicate(true)
	definition["ai"]=Policy.resolve()
	if algorithm=="competitive_v2": definition["ai"].merge(definition["ai"].get("competitive_parameters",{}),true)
	definition["ai"]["algorithm_version"]=algorithm; definition["ai"]["policy_seed"]=41721
	var ai = Factory.create(definition)
	var controller := Controller.new(world); controller.set_speed_multiplier(1.0)
	var probe := Probe.new(2048); controller.performance_probe=probe
	var runtime := Runtime.new(); var decisions := Decisions.new()
	runtime.configure(world,controller,[ai],decisions,Store.new(),world.task_coordinator)
	controller.set_before_fixed_tick(Callable(runtime,"queue_commands"))
	var started := Time.get_ticks_msec()
	while controller.tick_index<maximum_ticks and world.get_current_age(2)<101 and runtime.error.is_empty():
		for step in range(200):
			if controller.tick_index>=maximum_ticks or world.get_current_age(2)>=101: break
			var previous := controller.tick_index; controller.advance_frame(0.05,1,2,1)
			if previous==controller.tick_index: break
		if Time.get_ticks_msec()-started>600000: break
		await process_frame
	var complete: Array = world.get_buildings().filter(func(b): return int(b.get("team",0))==2 and String(b.get("state",""))=="complete").map(func(b): return b.get("kind",""))
	var passed := world.get_current_age(2)>=101 and world.technology_system.direct_prerequisites_met(2,101) and runtime.error.is_empty()
	var report := {"algorithm":algorithm,"civilization":civilization,"seed":41721,"tick":controller.tick_index,"age":world.get_current_age(2),"passed":passed,"seconds":float(Time.get_ticks_msec()-started)/1000.0,"structures":complete,"metrics":ai.strategy.metrics,"performance":probe.report(),"runtime_error":runtime.error}
	report["active_parameters"]=ai.economic_policy.duplicate(true)
	report["map_content_hash"]=built["map_data"].get("content_hash","")
	report["all_structures"]=world.get_buildings().filter(func(b): return int(b.get("team",0))==2).map(func(b): return {"kind":b.get("kind",""),"state":b.get("state",""),"position":b.get("pos",Vector2.ZERO),"progress":b.get("construction_progress",0.0),"builders":b.get("builders",{})})
	report["stockpile"]={}
	for resource_type in range(4): report["stockpile"][resource_type]=world.get_resource_amount(2,resource_type)
	report["workers"]=world.get_units().filter(func(u): return int(u.get("team",0))==2 and bool(u.get("components",{}).get("worker",{}).get("enabled",false))).map(func(u): return {"id":u["id"],"task":u.get("task",""),"cycles":u.get("gather_cycles",0),"deposits":u.get("deposit_cycles",0),"resource":u.get("resource_id",-1),"stage":u.get("gather_stage",""),"reason":u.get("diagnostic_reason","")})
	controller.set_before_fixed_tick(Callable())
	runtime.shutdown(); world.shutdown_derived_state()
	var file := FileAccess.open(output,FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t"))
	print("OPENING ",algorithm," civ=",civilization," tick=",controller.tick_index," passed=",passed)
	quit(0 if passed else 1)
