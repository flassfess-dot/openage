extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Factory=preload("res://scripts/ai_player_factory.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
const Runtime=preload("res://scripts/ai_runtime_coordinator.gd")
const Decisions=preload("res://scripts/ai_decision_queue.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
var failures: Array[String]=[]

func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=0
	var catalog=Catalog.new(); catalog.load()
	var world=World.new(Vector2i(48,48))
	world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.task_coordinator.enabled=false
	for team in [1,2]: world.set_team_civilization(team,13); world.set_population_cap(team,50); world.set_population_housing(team,50)
	for technology in [101,102,103]: world.grant_technology(1,technology)
	world.add_building(9000,"town_center",Vector2(8.5,8.5),1)
	world.add_building(9001,"town_center",Vector2(43.5,43.5),2)
	for index in range(23): world.add_unit(1,"villager",Vector2(12.5+index%6,12.5+index/6),false)
	for resource in [1,2,3]: world.set_resource_amount(1,resource,1200)
	world.set_resource_amount(1,0,0)
	world.configure_victory_rules([{"type":"wonder","hold_seconds":1.0}])
	world.update_fog_of_war()
	var policy:=Policy.resolve(); policy["algorithm_version"]="competitive_v2"; policy["style"]="pressure"; policy["construction_priorities"]=["wonder"]; policy["policy_seed"]=71
	var ai=Factory.create({"team":1,"ai":policy})
	var controller=Controller.new(world); controller.set_speed_multiplier(1.0)
	var runtime=Runtime.new(); runtime.configure(world,controller,[ai],Decisions.new(),Store.new(),world.task_coordinator)
	controller.set_before_fixed_tick(Callable(runtime,"queue_commands"))
	var paid_foundation:=false
	while controller.tick_index<36000 and not world.is_battle_over() and runtime.error.is_empty():
		controller.advance_frame(0.05,1,2,1)
		for building in world.buildings:
			if String(building.get("kind",""))=="wonder" and int(building.get("team",0))==1:
				paid_foundation=true
		if controller.tick_index>0 and controller.tick_index%4000==0: print("AI_WONDER_PROGRESS ",controller.tick_index," paid=",paid_foundation)
		await process_frame
	var outcome: Dictionary=world.get_victory_result()
	check(paid_foundation,"AI legally issues a paid wonder foundation at population 50")
	check(world.get_resource_amount(1,2)<=200 and world.get_resource_amount(1,3)<=200,"ordinary construction spends wonder stone and gold")
	check(bool(outcome.get("over",false)) and int(outcome.get("winner_team",0))==1 and String(outcome.get("reason",""))=="wonder","AI workers finish the actual wonder and its ordinary hold timer wins")
	check(runtime.error.is_empty(),"wonder runtime has no errors")
	print("AI_WONDER ",controller.tick_index," outcome=",outcome," abandoned=",ai.strategy.metrics.get("last_abandoned_foundation",{}))
	controller.set_before_fixed_tick(Callable()); runtime.shutdown(); world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
