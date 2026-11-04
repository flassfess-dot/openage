extends SceneTree
# Controlled AI components, ordinary commands and real simulation. This does
# not replace full-policy matches or measure strength/FPS.
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
const Rules=preload("res://scripts/ai_economy_rules.gd")
const Support=preload("res://scripts/ai_support_planner.gd")
const State=preload("res://scripts/ai_strategy_state.gd")
const Checkpoint=preload("res://scripts/game_checkpoint.gd")
const Replay=preload("res://scripts/replay_system.gd")
const TICKS=1200
var failures: Array[String]=[]
var output: String=""

func _initialize() -> void: run.call_deferred()

func run() -> void:
	Engine.max_fps=0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	var catalog=Catalog.new(); catalog.load()
	var results: Array=[]
	for count in [4,8]:
		var live: Dictionary=await execute(catalog,count,"live")
		var saved: Dictionary=await execute(catalog,count,"saved")
		var playback: Dictionary=await execute(catalog,count,"replay",live.get("replay",{}))
		for peer in [saved,playback]:
			check(peer.get("world_hash")==live.get("world_hash"),"%dv%d %s final world matches live" % [count/2,count/2,peer.get("mode","")])
			check(peer.get("commands")==live.get("commands"),"%dv%d %s public command trace matches live" % [count/2,count/2,peer.get("mode","")])
		for row in [live,saved,playback]:
			row.erase("replay"); results.append(row)
	var report:={"passed":failures.is_empty(),"failures":failures,"results":results,"runtime":{"native":ClassDB.class_exists("RoRPathKernel"),"release":not OS.has_feature("editor")},"scope":"Six controlled component executions:2v2/4v4 each live, real-file save continuation and command replay. Actual allied repair and completed trade voyages; normal commands from legal observations. No independently running full strategic AI, strength, FPS or human-rating claim."}
	var file=FileAccess.open(output,FileAccess.WRITE)
	if file==null: push_error("Team economy report cannot be opened"); quit(1); return
	file.store_string(JSON.stringify(report,"\t")); file.close()
	for failure in failures: push_error(failure)
	print("AI_TEAM_ECONOMY ",failures.is_empty()," cases=",results.size())
	quit(0 if failures.is_empty() else 1)

func fixture(catalog,count: int) -> Dictionary:
	var world=World.new(Vector2i(28,28))
	world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	var terrain: Array[int]=[]
	for y in range(28):
		for x in range(28): terrain.append(1 if x<=6 else 2 if x==7 else 0)
	var levels: Array[int]=[]; levels.resize(29*29); levels.fill(0)
	var map:={"size":Vector2i(28,28),"terrain_ids":terrain,"vertex_levels":levels}
	world.configure_map_data(map)
	world.configure_victory_rules([{"type":"score","time_limit_seconds":3600.0}])
	world.task_coordinator.enabled=false
	for team in range(1,count+1):
		world.set_team_civilization(team,13); world.set_population_cap(team,50); world.set_population_housing(team,50)
		for resource in range(4): world.set_resource_amount(team,resource,3000 if resource==1 else 1000)
		if team>2: world.add_unit(team,"villager",Vector2(23.5,2.5+(team-3)*3),false)
	for left in range(1,count+1):
		for right in range(left+1,count+1): world.set_alliance(left,right,(left<=count/2)==(right<=count/2))
	var home: Dictionary=world.add_building(1501,"dock",Vector2(5.5,9.5),1)
	var target: Dictionary=world.add_building(1502,"dock",Vector2(5.5,22.5),2)
	var trader: Dictionary=world.add_unit(1,"trade_boat",Vector2(5.5,20.5),false)
	var asset: Dictionary=world.add_building(1503,"granary",Vector2(14.5,13.5),1)
	world.set_entity_field(asset,"hp",maxf(1.0,float(asset["max_hp"])-200.0))
	var worker: Dictionary=world.add_unit(2,"villager",Vector2(14.5,16),false)
	world.trade_system.set_trade_goods(2,100.0)
	world.update_fog_of_war()
	return {"world":world,"controller":Controller.new(world),"map":map,"trader":int(trader["id"]),"asset":int(asset["id"]),"worker":int(worker["id"]),"target":int(target["id"]),"home":int(home["id"])}

func execute(catalog,count: int,mode: String,replay_data: Dictionary={}) -> Dictionary:
	var f: Dictionary=fixture(catalog,count)
	var world=f["world"]; var controller=f["controller"]
	var state=State.new(); state.goal={"home":Vector2(14.5,13.5)}
	var codec=Replay.new(); var recorder: Variant=null
	if mode=="replay": check(controller.load_replay(replay_data),"recorded team commands load")
	else: recorder=controller.start_recording(41721,false)
	var initial_hp: float=float(world.find_building(f["asset"])["hp"])
	var initial_gold: int=world.get_resource_amount(1,3)
	var initial_wood: int=world.get_resource_amount(2,1)
	var checkpoint_proof: Dictionary={}
	while controller.tick_index<TICKS:
		if mode!="replay" and controller.tick_index%20==0:
			var own: Dictionary=observe(world,controller.tick_index,1)
			var proposals: Array=Rules.plan_idle_trade(own,controller.tick_index+1,1,own["units"].filter(func(u): return int(u["team"])==1),own["buildings"].filter(func(b): return int(b["team"])==1))
			for command in proposals: controller.enqueue_command(command,true,1)
			for command in Support.plan(observe(world,controller.tick_index,2),controller.tick_index+1,2,{},state): controller.enqueue_command(command,true,2)
		controller.advance_frame(0.05,1,count)
		if mode=="saved" and controller.tick_index==60:
			var original_hash: String=codec.world_state_hash(world,controller.tick_index,controller)
			var original_ai: Dictionary=state.canonical_state()
			var path: String=output+".%d.checkpoint.json" % count
			var file=FileAccess.open(path,FileAccess.WRITE)
			file.store_string(JSON.stringify({"checkpoint":Checkpoint.pack(Checkpoint.capture(world,controller,{},f["map"])),"ai":codec.encode_exact_variant(original_ai)})); file.close()
			var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
			var replacement: Dictionary=fixture(catalog,count)
			var restored=replacement["world"]; var resumed=replacement["controller"]
			check(Checkpoint.restore(Checkpoint.unpack(data["checkpoint"]),restored,resumed),"team economy checkpoint restores")
			var new_state=State.new(); check(new_state.restore_state(codec.decode_variant(data["ai"])),"team repair planner state restores")
			var exact: bool=codec.world_state_hash(restored,resumed.tick_index,resumed)==original_hash and new_state.canonical_state()==original_ai
			check(exact,"team economy immediately restores exact world and planner state")
			var asset: Dictionary=world.find_building(f["asset"])
			var trade: Dictionary=world.find_unit(f["trader"])["components"]["trade"]
			checkpoint_proof={"tick":60,"exact_world_ai":exact,"repair_progress":float(asset["hp"])-initial_hp,"trade_stage":trade.get("stage"),"trade_task":world.find_unit(f["trader"])["task"],"file_sha256":FileAccess.get_sha256(path)}
			check(float(asset["hp"])>initial_hp and float(asset["hp"])<float(asset["max_hp"]),"save occurs during actual partial allied repair")
			check(world.find_unit(f["trader"])["task"]=="trade","save occurs during an actual trade route")
			resumed.replay_recorder=recorder; resumed.record_replay_state_hashes=false
			world.shutdown_derived_state(); world=restored; controller=resumed; state=new_state
		if controller.tick_index%200==0: await process_frame
		if world.battle_over: check(false,"team economy must reach its full horizon"); break
	var trader: Dictionary=world.find_unit(f["trader"])
	var asset: Dictionary=world.find_building(f["asset"])
	var trade: Dictionary=trader["components"]["trade"]
	var events: Array=controller.events_after()
	check(float(asset["hp"])>initial_hp,"allied repair restores real HP")
	check(world.get_resource_amount(2,1)<initial_wood,"allied worker pays actual repair wood")
	check(int(trade.get("trip_count",0))>=1 and world.get_resource_amount(1,3)>initial_gold,"AI trade route returns real gold")
	var recorded: Dictionary=recorder.to_dictionary() if recorder!=null else replay_data
	var commands: Array=recorded.get("commands",[])
	check(commands.any(func(c):return c.get("type")=="trade"),"public AI trade command was recorded")
	check(commands.any(func(c):return c.get("type")=="repair"),"public AI repair command was recorded")
	var row:={"teams":count,"mode":mode,"tick":controller.tick_index,"repaired_hp":float(asset["hp"])-initial_hp,"repair_wood":initial_wood-world.get_resource_amount(2,1),"trips":int(trade.get("trip_count",0)),"gold":world.get_resource_amount(1,3)-initial_gold,"world_hash":codec.world_state_hash(world,controller.tick_index,controller),"commands":commands,"checkpoint":checkpoint_proof,"replay":recorded}
	world.shutdown_derived_state()
	return row

func observe(world,tick: int,team: int) -> Dictionary:
	return Store.new().observe_with_queries(world,tick,team,{"compact_entities":true,"include_ai_profiles":true,"include_navigation":false,"include_projectiles":false,"include_scenario":false})

func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
