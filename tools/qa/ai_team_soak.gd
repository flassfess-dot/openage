# Standalone team soak. All participants use competitive_v2.
# Uses the arena mechanics; these cases are excluded from policy fitting.
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
const Codec := preload("res://scripts/replay_system.gd")
const Metrics := preload("res://tools/ai_arena_metrics.gd")
const Probe := preload("res://scripts/performance_probe.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
var case: Dictionary = {}
var output := ""

# Evaluator-only progress. A repeated order is not movement, and a blocked
# production queue is not advancing research. These facts never enter policy.
static func progress_signature(world) -> int:
	var facts: Array=[]
	for actor in world.get_units():
		facts.append([actor["id"],Vector2(actor["pos"]).snapped(Vector2.ONE*0.01),actor.get("hp",0),actor.get("carried_amount",0),actor.get("gather_cycles",0),actor.get("deposit_cycles",0)])
	for building in world.get_buildings():
		facts.append([building["id"],building.get("hp",0),building.get("construction_progress",0),building.get("production_queue",[])])
	return hash(facts)

static func legitimate_timer(world) -> bool:
	var victory=world.victory_system
	if victory.hold_seconds.values().any(func(seconds): return float(seconds)>0.0): return true
	for rule in victory.rules:
		if String(rule.get("type",""))=="score" and float(rule.get("time_limit_seconds",0))>float(victory.elapsed_seconds): return true
		if String(rule.get("type",""))=="scenario":
			for condition in rule.get("conditions",[]):
				if String(condition.get("type",""))=="elapsed" and float(condition.get("seconds",0))>float(victory.elapsed_seconds): return true
	return false

func _initialize() -> void:
	call_deferred("run")

func save_json(file_path: String, data: Dictionary) -> void:
	var file := FileAccess.open(file_path+".pending",FileAccess.WRITE)
	if file == null: push_error("Arena output unwritable: "+file_path); return
	file.store_string(JSON.stringify(data,"\t")); file.close()
	DirAccess.rename_absolute(file_path+".pending",file_path)

func run() -> void:
	Engine.max_fps = 0
	var case_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--case="): case_path = arg.trim_prefix("--case=")
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	case = JSON.parse_string(FileAccess.get_file_as_string(case_path))
	if case.is_empty() or output.is_empty(): push_error("Arena arguments invalid"); quit(1); return
	var settings := Settings.default_settings()
	settings.merge(case.get("settings",{}),true)
	# Lobby validation requires one local human. The validated match definition
	# is subsequently controlled entirely by public AI commands in this harness.
	for slot in settings["players"]:
		slot["enabled"] = int(slot["team"]) <= int(case.get("player_count",4))
		slot["alliance_id"] = 1 if int(slot["team"])<=int(case.get("player_count",4))/2 else 2
		slot["controller"] = "human" if int(slot["team"]) == 1 else "ai"
	var bundle_path := String(case["map_bundle"])
	var built: Dictionary
	if FileAccess.file_exists(bundle_path):
		var input := FileAccess.open(bundle_path,FileAccess.READ)
		built = input.get_var(false)
	else:
		built = Settings.build(settings)
		if bool(built.get("valid",false)):
			var bundle := FileAccess.open(bundle_path+".pending",FileAccess.WRITE)
			bundle.store_var(built,false); bundle.close()
			DirAccess.rename_absolute(bundle_path+".pending",bundle_path)
	if not bool(built.get("valid",false)):
		save_json(output,{"runtime":{"release":not OS.has_feature("editor"),"executable":OS.get_executable_path(),"native":ClassDB.class_exists("RoRPathKernel")},"schema_version":1,"case_id":case["case_id"],"fingerprint":case["fingerprint"],"status":"GENERATION_ERROR","errors":built.get("errors",[])})
		quit(1); return
	var definition: Dictionary = built["definition"].duplicate(true)
	var subject_team := int(case.get("subject_team",1))
	var civilizations: Array = case.get("civilizations",[13,8])
	for player in definition["players"]:
		player["controller"] = "ai"
		player["civilization_id"] = civilizations[posmod(int(player["team"])-1,civilizations.size())]
	var catalog := Catalog.new(); catalog.load()
	var world := World.new(built["map_data"]["size"])
	if not ClassDB.class_exists("RoRPathKernel") or not ClassDB.class_exists("RoRReadModelKernel"):
		save_json(output,{"case_id":case["case_id"],"fingerprint":case["fingerprint"],"status":"BACKEND_ERROR","errors":["required_native_backend_missing"]})
		quit(1); return
	world.set_gamespec(catalog.gamespec_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data)
	Bootstrap.apply(world,definition,built["map_data"])
	world.task_coordinator.enabled = bool(case.get("threaded",false))
	var controller := Controller.new(world)
	controller.performance_probe=Probe.new(2048)
	world.set_performance_probe(controller.performance_probe)
	controller.start_recording(int(settings["seed"]),false)
	controller.set_speed_multiplier(1.0)
	var actors: Array = []
	for player in definition["players"]:
		var policy := Policy.resolve("random_map_balanced",String(settings.get("ai_difficulty_id","standard")))
		if int(player["team"])>0:
			if String(case.get("subject_policy",{}).get("algorithm_version",""))=="competitive_v2": policy.merge(policy.get("competitive_parameters",{}),true)
			policy.merge(case.get("subject_policy",{}),true)
		else:
			policy = JSON.parse_string(FileAccess.get_file_as_string("res://ai_baselines/v1/skirmish_policies.json"))["profiles"][0]["runtime"].duplicate(true)
			policy["profile"] = "skirmish_policy_v1"
			policy["algorithm_version"] = "baseline_v1"
			policy.merge(case.get("opponent_policy",{}),true)
		player["ai"] = policy
		actors.append(Factory.create(player))
	var runtime := Runtime.new(); var decisions := Decisions.new()
	runtime.configure(world,controller,actors,decisions,Store.new(),world.task_coordinator)
	var started := Time.get_ticks_msec()
	var last_event := 0
	var last_activity_tick := 0
	var activity_signature:=progress_signature(world)
	var last_activity_sample_tick:=0
	var last_progress_tick := 0
	var last_progress_wall := started
	var published_progress_tick := -1000
	var checkpoint_tick := -6000
	var max_ticks := int(case.get("maximum_ticks",36000))
	var event_metrics: Dictionary = {}
	var evaluator := Metrics.new()
	var strategy_trace: Array=[]
	evaluator.consume(world,controller)
	controller.set_before_fixed_tick(func(next_tick):
		evaluator.consume(world,controller)
		return runtime.queue_commands(next_tick))
	var status := "DRAW_TIME_LIMIT"
	while controller.tick_index < max_ticks and not bool(world.victory_system.result.get("over",false)):
		for step in range(200):
			if controller.tick_index >= max_ticks or bool(world.victory_system.result.get("over",false)): break
			var previous := controller.tick_index
			controller.advance_frame(0.05,1,2,1)
			if controller.tick_index == previous: break
		var events: Array = controller.events_after(last_event)
		if String(case["base_id"]).begins_with("dev-") or String(case["base_id"]).begins_with("validation-"):
			for actor in actors:
				if int(actor.team)!=subject_team or actor.competitive_controller==null: continue
				var selected: Dictionary=actor.strategy.metrics.get("strategic_plan",{})
				if strategy_trace.size()<4096 and not selected.is_empty(): strategy_trace.append({"tick":controller.tick_index,"team":subject_team,"facts":selected.get("facts",{}).duplicate(true),"selected":selected.get("id",""),"candidates":actor.strategy.metrics.get("strategic_alternatives",[]).duplicate(true),"provenance":"sampled policy decisions from legal observations; terminal label added by evaluator"})
		for entry in events:
			last_event = maxi(last_event,int(entry.get("sequence",entry.get("sequence_id",0))))
			var type := String(entry.get("type",""))
			if type in ["resources_deposited","resource_gathered","attack_hit","death","build_complete","research_complete","unit_produced"]: last_activity_tick = controller.tick_index
			event_metrics[type] = int(event_metrics.get(type,0))+1
		if controller.tick_index-last_activity_sample_tick>=200:
			var current_signature:=progress_signature(world)
			last_activity_sample_tick=controller.tick_index
			if current_signature!=activity_signature:
				activity_signature=current_signature; last_activity_tick=controller.tick_index
		if not runtime.error.is_empty(): status = "RUNTIME_ERROR"; break
		if Time.get_ticks_msec()-started > int(case.get("wall_timeout_seconds",3600))*1000: status = "INFRA_TIMEOUT"; break
		# The wall watchdog detects a failed gate, never chooses a game command.
		if controller.tick_index != last_progress_tick: last_progress_tick = controller.tick_index; last_progress_wall = Time.get_ticks_msec()
		elif Time.get_ticks_msec()-last_progress_wall > 30000: status = "STALLED_GATE"; break
		if controller.tick_index > 4800 and controller.tick_index-last_activity_tick > 2400 and not legitimate_timer(world): status = "STALLED"; break
		if controller.tick_index-published_progress_tick>=1000:
			published_progress_tick=controller.tick_index
			save_json(output+".progress.json",{"tick":controller.tick_index,"seconds":float(Time.get_ticks_msec()-started)/1000.0,"units":world.get_units().size(),"runtime_error":runtime.error,"performance":controller.performance_probe.report()})
		if controller.tick_index-checkpoint_tick>=6000:
			checkpoint_tick=controller.tick_index
			var diagnostic:=FileAccess.open(output+".checkpoint.dat.pending",FileAccess.WRITE)
			if diagnostic!=null:
				diagnostic.store_var({"checkpoint":Checkpoint.capture(world,controller,definition,built["map_data"]),"ai_queue":decisions.canonical_state(),"ai_states":actors.map(func(ai): return ai.canonical_state()),"case":case,"purpose":"diagnostic; case resume replays from the frozen seed"},false)
				diagnostic.close(); DirAccess.rename_absolute(output+".checkpoint.dat.pending",output+".checkpoint.dat")
		await process_frame
	var victory: Dictionary = world.get_victory_result()
	evaluator.consume(world,controller)
	if status not in ["WIN","LOSS","DRAW_TIME_LIMIT"]:
		var diagnostic:=FileAccess.open(output+".checkpoint.dat",FileAccess.WRITE)
		if diagnostic!=null: diagnostic.store_var(Checkpoint.capture(world,controller,definition,built["map_data"]),false)
	if bool(victory.get("over",false)): status = "WIN" if subject_team in victory.get("winner_teams",[victory.get("winner_team",-1)]) else "LOSS"
	var players: Array = []
	for ai in actors:
		if not decisions.active: ai.collect_feedback(controller,controller.tick_index)
		var metrics: Dictionary = ai.strategy.metrics.duplicate(true)
		metrics["idle_worker_ratio"] = float(metrics.get("idle_worker_ticks",0))/maxf(1.0,float(metrics.get("worker_ticks",0)))
		metrics["command_rejection_ratio"] = float(metrics.get("commands_rejected",0))/maxf(1.0,float(metrics.get("commands_rejected",0)+metrics.get("commands_accepted",0)))
		players.append({"team":ai.team,"metrics":metrics,"policy":ai.economic_policy})
	var codec := Codec.new()
	var final_hash := codec.world_state_hash(world,controller.tick_index,controller)
	var replay_path := output.trim_suffix(".json")+".replay.json"
	if controller.replay_recorder != null:
		var replay_file := FileAccess.open(replay_path,FileAccess.WRITE)
		replay_file.store_string(controller.replay_recorder.to_json())
	controller.set_before_fixed_tick(Callable())
	runtime.shutdown()
	world.shutdown_derived_state()
	save_json(output,{"runtime":{"release":not OS.has_feature("editor"),"executable":OS.get_executable_path(),"native":ClassDB.class_exists("RoRPathKernel")},"performance":controller.performance_probe.report(),"schema_version":1,"case_id":case["case_id"],"fingerprint":case["fingerprint"],"series":case["series"],"base_id":case["base_id"],"seed":settings["seed"],"subject_team":subject_team,"opponent":case.get("opponent","baseline"),"settings":case["settings"],"status":status,"tick":controller.tick_index,"wall_seconds":float(Time.get_ticks_msec()-started)/1000.0,"players":players,"measured":evaluator.report(),"events":event_metrics,"strategy_trace":strategy_trace,"final_hash":final_hash,"victory":victory,"runtime_error":runtime.error,"replay":replay_path})
	print("ARENA ",case["case_id"]," ",status," tick=",controller.tick_index)
	actors.clear(); controller=null; runtime=null; world=null; decisions=null
	await process_frame
	quit(0 if status in ["WIN","LOSS","DRAW_TIME_LIMIT"] else 1)
