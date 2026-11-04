extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Factory=preload("res://scripts/ai_player_factory.gd")
const Snapshot=preload("res://scripts/simulation_snapshot.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
const Runtime=preload("res://scripts/ai_runtime_coordinator.gd")
const Decisions=preload("res://scripts/ai_decision_queue.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=0
	var catalog=Catalog.new(); catalog.load()
	for scenario in ["stranded_cargo","unreachable_food"]:
		var world=World.new(Vector2i(32,32))
		world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		world.task_coordinator.enabled=false
		for team in [1,2]: world.set_team_civilization(team,13); world.set_population_cap(team,50); world.set_population_housing(team,50)
		world.grant_technology(1,101)
		world.add_building(9000,"town_center",Vector2(5.5,15.5),1)
		world.add_building(9001,"town_center",Vector2(28.5,28.5),2)
		world.add_building(9002,"market",Vector2(7.5,25.5),1)
		world.add_building(9003,"archery_range",Vector2(8.5,7.5),1)
		world.add_building(9004,"granary",Vector2(5.5,21.5),1)
		for y in range(32): world.add_building(9100+y,"wall",Vector2(16.5,float(y)+0.5),0)
		var carrier: Dictionary={}
		if scenario=="stranded_cargo":
			carrier=world.add_unit(1,"villager",Vector2(23.5,15.5),false)
			world.set_entity_field(carrier,"carried_amount",10.0);world.set_entity_field(carrier,"carried_resource_type_id",0)
			var prior_role: int = int(carrier.get("worker_role_source_unit_id",-1))
			var delivery_profile: Dictionary = preload("res://scripts/ai_observation_profile.gd").actor(world,{"id":carrier["id"],"team":1,"entity_type":"unit"},1)
			check("granary" in delivery_profile.get("delivery_drop_site_kinds",[]),"generic cargo exposes the depot permitted after the normal return role transition")
			check(int(carrier.get("worker_role_source_unit_id",-1))==prior_role,"observing prospective delivery depots never changes the real worker role")
		else:
			for index in range(12): world.add_unit(1,"villager",Vector2(9.5+index%4,12.5+index/4),false)
			var scout: Dictionary=world.add_unit(1,"clubman",Vector2(15.5,15.5),false); scout["stance"]="passive"
		var berries: Dictionary=world.add_resource("berries",Vector2(18.5,15.5),10000)
		world.set_resource_amount(1,0,260);world.set_resource_amount(1,1,600)
		world.update_fog_of_war()
		if scenario=="unreachable_food":
			var visible:=Snapshot.with_queries(world,0,1,{"compact_entities":true})
			check(visible.get("resources",[]).any(func(r): return int(r.get("id",-1))==int(berries["id"]) and int(r.get("amount",0))>=10000 and int(r.get("resource_type_id",-1))==0),"unreachable food is actually known to the AI before its recovery")
		var policy:=Policy.resolve(); policy["algorithm_version"]="competitive_v2";policy["style"]="fast_age"
		if scenario=="stranded_cargo": policy["competitive_parameters"]["opening_definitions"]={"fast_age":{"workers":1,"age_workers":1}};policy["competitive_parameters"]["age_defender_minimum"]=0
		var ai=Factory.create({"team":1,"ai":policy})
		var controller=Controller.new(world);controller.set_speed_multiplier(1.0)
		var runtime=Runtime.new();runtime.configure(world,controller,[ai],Decisions.new(),Store.new(),world.task_coordinator)
		controller.set_before_fixed_tick(Callable(runtime,"queue_commands"))
		var limit:=18000 if scenario=="unreachable_food" else 6000
		var saw_food_fallback:=false
		while controller.tick_index<limit and runtime.error.is_empty():
			controller.advance_frame(0.05,1,2,1)
			saw_food_fallback=saw_food_fallback or bool(ai.strategy.metrics.get("food_shortfall",{}).get("fallback",false))
			if scenario=="stranded_cargo" and float(carrier.get("carried_amount",0))<0.01: break
			if scenario=="unreachable_food" and world.get_current_age(1)>=102: break
			await process_frame
		var granaries: Array=world.get_buildings().filter(func(b): return int(b.get("team",0))==1 and b.get("kind")=="granary" and String(b.get("state",""))=="complete")
		var farms: Array=world.get_buildings().filter(func(b): return int(b.get("team",0))==1 and b.get("kind")=="farm" and String(b.get("state",""))=="complete")
		if scenario=="stranded_cargo":
			check(granaries.any(func(b): return Vector2(b["pos"]).x>17.0),"AI pays for a reachable remote granary instead of repeatedly selecting the inaccessible home")
			check(float(carrier.get("carried_amount",0))<0.01 and int(carrier.get("deposit_cycles",0))>0,"stranded cargo reaches the real stockpile through normal deposit orders")
		else:
			check(saw_food_fallback and not farms.is_empty(),"no actual food income triggers farms despite known unreachable berries")
			check(world.get_current_age(1)>=102,"farms restore sufficient paid income for the actual Bronze research")
		check(runtime.error.is_empty(),scenario+": runtime has no errors")
		print("AI_FOOD_RECOVERY ",scenario," tick=",controller.tick_index," age=",world.get_current_age(1)," farms=",farms.size()," granaries=",granaries.size()," recovery=",ai.strategy.metrics.get("infrastructure_recovery",{})," shortfall=",ai.strategy.metrics.get("food_shortfall",{}))
		controller.set_before_fixed_tick(Callable());runtime.shutdown();world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
