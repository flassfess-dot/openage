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
	for category in ["artifact","ruin"]:
		var world=World.new(Vector2i(32,32))
		world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		world.task_coordinator.enabled=false
		for team in [1,2]: world.set_team_civilization(team,13); world.set_population_cap(team,50); world.set_population_housing(team,50)
		world.add_building(9000,"town_center",Vector2(5.5,5.5),1)
		world.add_building(9001,"town_center",Vector2(28.5,28.5),2)
		for index in range(6): world.add_unit(1,"clubman",Vector2(12.5+index%3,12.5+index/3),false)
		# The owned scout sees the objective without being within capture range.
		world.add_unit(1,"villager",Vector2(15.5,15.5),false)
		var objective: Dictionary=world.add_unit(0,"artifact",Vector2(18.5,15.5),false) if category=="artifact" else world.add_victory_object("ruin",Vector2(18.5,15.5))
		world.configure_victory_rules([{"type":category+"s","required_count":1,"hold_seconds":1.0}])
		world.update_fog_of_war()
		var policy:=Policy.resolve(); policy["algorithm_version"]="competitive_v2"; policy["initial_attack_delay_ticks"]=0; policy["minimum_attack_group_size"]=3; policy["policy_seed"]=71
		var ai=Factory.create({"team":1,"ai":policy})
		var controller=Controller.new(world); controller.set_speed_multiplier(1.0)
		var runtime=Runtime.new(); runtime.configure(world,controller,[ai],Decisions.new(),Store.new(),world.task_coordinator)
		controller.set_before_fixed_tick(Callable(runtime,"queue_commands"))
		var selected:=false
		while controller.tick_index<1200 and not world.is_battle_over() and runtime.error.is_empty():
			controller.advance_frame(0.05,1,2)
			selected=selected or String(ai.strategy.goal.get("objective_category",""))==category
			await process_frame
		var outcome: Dictionary=world.get_victory_result()
		check(selected,category+": legal objective changes the actual AI goal")
		check(int(objective.get("team",0))==1,category+": AI troops capture the real objective through normal movement")
		check(bool(outcome.get("over",false)) and int(outcome.get("winner_team",0))==1 and String(outcome.get("reason",""))==category+"s",category+": ordinary hold timer produces the correct victory")
		check(runtime.error.is_empty() and int(ai.strategy.metrics.get("commands_accepted",0))>0,category+": real AI commands were accepted")
		print("AI_OBJECTIVE ",category," tick=",controller.tick_index," outcome=",outcome," goal=",ai.strategy.goal)
		controller.set_before_fixed_tick(Callable()); runtime.shutdown(); world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
