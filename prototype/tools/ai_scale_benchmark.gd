extends SceneTree
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
var rows: Array=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=0
	var catalog=Catalog.new(); catalog.load()
	for teams in [2,4,8]:
		for side in [96,192]:
			var world=World.new(Vector2i(side,side)); world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
			var terrain: Array[int]=[]; terrain.resize(side*side); terrain.fill(0)
			var heights: Array[int]=[]; heights.resize((side+1)*(side+1)); heights.fill(0)
			world.configure_map_data({"terrain_ids":terrain,"vertex_levels":heights})
			world.task_coordinator.enabled=true
			var ais: Array=[]; var groups: Dictionary={}
			for team in range(1,teams+1):
				world.set_team_civilization(team,13); world.set_population_cap(team,500); world.set_population_housing(team,500)
				for resource in range(4): world.set_resource_amount(team,resource,2000)
				var base:=Vector2(6+(team-1)%4*(side/4),6+(team-1)/4*(side/2))
				world.add_building(90000+team,"town_center",base,team)
				for n in range(20): world.add_resource("tree",base+Vector2(4+n%5,4+n/5),500)
				var moving: Array[int]=[]
				for n in range(500):
					var pos:=base+Vector2(2+(n%20)*0.85,8+(n/20)*0.85)
					pos.x=clampf(pos.x,1.5,side-1.5); pos.y=clampf(pos.y,1.5,side-1.5)
					var actor: Dictionary=world.add_unit(team,"villager" if n<225 else "archer" if n%2==0 else "clubman",pos,false)
					if n>=225 and n<325: moving.append(int(actor["id"]))
					elif n<100:
						var trees: Array=world.get_resources().filter(func(r): return String(r.get("kind",""))=="tree")
						if not trees.is_empty(): world.assign_command_gather([actor],int(trees[posmod(n,trees.size())]["id"]))
				groups[team]=moving
				var policy:=Policy.resolve(); policy.merge(policy.get("competitive_parameters",{}),true); policy["algorithm_version"]="competitive_v2"
				ais.append(Factory.create({"team":team,"ai":policy}))
			world.update_fog_of_war()
			var controller=Controller.new(world); controller.set_speed_multiplier(1.0)
			var probe=Probe.new(2048); controller.performance_probe=probe; world.set_performance_probe(probe)
			for team in groups:
				controller.enqueue_command(Commands.AttackMoveCommand.new(0,groups[team],Vector2(side/2,side/2)),true,int(team))
			var runtime=Runtime.new(); var decisions=Decisions.new(); runtime.configure(world,controller,ais,decisions,Store.new(),world.task_coordinator)
			controller.set_before_fixed_tick(Callable(runtime,"queue_commands"))
			var started:=Time.get_ticks_msec(); var last_tick:=0; var last_progress:=started
			while controller.tick_index<100 and runtime.error.is_empty() and Time.get_ticks_msec()-started<600000:
				controller.advance_frame(0.05,1,2)
				if controller.tick_index!=last_tick: last_tick=controller.tick_index; last_progress=Time.get_ticks_msec()
				elif Time.get_ticks_msec()-last_progress>120000: break
				await process_frame
			rows.append({"teams":teams,"units_per_team":500,"side":side,"tick":controller.tick_index,"seconds":float(Time.get_ticks_msec()-started)/1000.0,"runtime_error":runtime.error,"profile":probe.report(),"note":"headless threaded mixed work/idle/march fixture; no graphical FPS claim"})
			print("SCALE ",teams,"x500 ",side," tick=",controller.tick_index," error=",runtime.error)
			runtime.shutdown(); world.shutdown_derived_state()
			var file:=FileAccess.open("res://qa/ai-competitive/competitive-20261030/scale_benchmark.json",FileAccess.WRITE); file.store_string(JSON.stringify({"rows":rows},"\t"))
			await process_frame
	quit(0 if rows.all(func(r): return int(r["tick"])>=100 and String(r["runtime_error"]).is_empty()) else 1)
