extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
const Economy=preload("res://scripts/ai_adaptive_economy.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
const State=preload("res://scripts/ai_strategy_state.gd")
const Budget=preload("res://scripts/ai_plan_budget.gd")
var failures: Array[String]=[]
func _initialize() -> void:
	var catalog=Catalog.new(); catalog.load()
	for configuration in [{"civilization":13,"food":50},{"civilization":15,"food":50},{"civilization":15,"food":75}]:
		var food:=int(configuration["food"]); var civilization:=int(configuration["civilization"])
		var world=World.new(Vector2i(24,24)); world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.navigation_grid.configure_terrain(func(_cell): return "grass")
		world.set_team_civilization(1,civilization); world.set_population_cap(1,50); world.set_population_housing(1,50)
		world.set_resource_amount(1,0,food)
		var center: Dictionary=world.add_building(9000,"town_center",Vector2(5.5,5.5),1)
		world.add_building(9001,"barracks",Vector2(12.5,5.5),1)
		for index in range(9): world.add_unit(1,"villager",Vector2(5.5+index,12.5),false)
		world.add_unit(2,"clubman",Vector2(21.5,21.5),false)
		world.update_fog_of_war()
		check(int(world.unit_resource_cost("villager",1).get(0,0))==(75 if civilization==15 else 50),"fixture uses the actual civilization's villager price")
		var snapshot:=Store.new().observe_with_queries(world,0,1,{"compact_entities":true,"include_ai_profiles":true,"include_navigation":true,"include_projectiles":false,"include_scenario":false,"economic_production_options_only":true})
		var policy:=Policy.resolve(); policy["competitive"]=true; policy["style"]="fast_age"
		var state=State.new(); state.goal={"home":center["pos"],"type":"explore"}
		var commands: Array=Economy.plan(snapshot,1,1,policy,state,Budget.new(snapshot["player_state"],snapshot["buildings"]),{}, {})
		var training: Array=commands.filter(func(c): return c.command_type()=="train")
		if civilization==15 and food==50:
			check(training.is_empty(),"cheaper military production cannot repeatedly consume the essential worker fund")
			check(int(state.metrics.get("worker_food_reservation",{}).get("protected",0))==50,"partial food fund is retained while the civilian is not affordable")
		else:
			if civilization==15: check(training.size()==1 and int(center["id"]) in training[0].unit_ids,"the accumulated fund produces the worker through the actual TC")
			else: check(training.size()==1 and int(center["id"]) not in training[0].unit_ids,"a normal-priced economy with nine workers can still fund its first defender")
			var controller=Controller.new(world)
			for command in training:
				command.params.erase("_ai_feedback")
				controller.enqueue_command(command,true,1); controller.advance_frame(0.05,1,2)
				check(bool(controller.get_command_result(command.sequence_id).get("accepted",false)),"ordinary production validates the proposed worker")
			check(world.get_resource_amount(1,0)==0,"production pays the actual food price exactly once")
			if civilization==15: check(center.get("production_queue",[]).size()==1,"the TC actually starts the Palmyran worker")
		world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
