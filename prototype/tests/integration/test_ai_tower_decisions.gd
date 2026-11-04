extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
const Planner=preload("res://scripts/ai_capability_planner.gd")
const State=preload("res://scripts/ai_strategy_state.gd")
const Budget=preload("res://scripts/ai_plan_budget.gd")
const Regions=preload("res://scripts/ai_region_model.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	var catalog=Catalog.new(); catalog.load()
	var world=World.new(Vector2i(32,32))
	world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.task_coordinator.enabled=false
	for team in [1,2]: world.set_population_cap(team,50); world.set_population_housing(team,50)
	var tower: Dictionary=world.add_building(80,"tower",Vector2(12.5,12.5),1)
	var archer: Dictionary=world.add_unit(1,"archer",Vector2(9.5,12.5),false)
	var enemy: Dictionary=world.add_unit(2,"clubman",Vector2(15.5,12.5),false)
	enemy["stance"]="passive"
	world.add_building(81,"town_center",Vector2(28.5,28.5),2)
	world.update_fog_of_war()
	var controller=Controller.new(world)
	var snapshot:=Store.new().observe_with_queries(world,0,1,{"compact_entities":true,"include_ai_profiles":true,"include_navigation":true,"include_projectiles":false,"include_scenario":false})
	var state=State.new(); state.goal={"home":Vector2(7.5,12.5)}
	state.observe(snapshot,1,{"competitive":true})
	var commands: Array=Planner.plan(snapshot,0,1,{"competitive":true},state,Budget.new(snapshot["player_state"],snapshot["buildings"]),{},Regions.new())
	var boards:=commands.filter(func(c): return c.command_type()=="board" and int(c.params.get("transport_id",-1))==80)
	check(boards.size()==1,"observed threat makes the AI offer a real tower boarding command")
	for command in boards: check(submit(controller,command),"AI tower boarding passes ordinary validation")
	for tick in range(400):
		controller.advance_frame(0.05,1,2,1)
		if world.transport_system.passenger_count(tower)==1: break
	check(world.transport_system.passenger_count(tower)==1,"the archer physically enters the tower")
	check(world.find_unit(int(archer["id"]))==null,"garrisoned archer leaves the map through transport ownership")
	# Clear the observed threat through the authoritative death path; the new
	# observation then represents a later decision with no retained threat.
	if float(enemy.get("hp",0))>0: enemy["hp"]=0; world.begin_death(enemy)
	for tick in range(120): controller.advance_frame(0.05,1,2,1)
	world.update_fog_of_war()
	snapshot=Store.new().observe_with_queries(world,controller.tick_index,1,{"compact_entities":true,"include_ai_profiles":true,"include_navigation":true,"include_projectiles":false,"include_scenario":false})
	state=State.new(); state.goal={"home":Vector2(7.5,12.5)}; state.observe(snapshot,1,{"competitive":true})
	commands=Planner.plan(snapshot,controller.tick_index,1,{"competitive":true},state,Budget.new(snapshot["player_state"],snapshot["buildings"]),{},Regions.new())
	var unloads:=commands.filter(func(c): return c.command_type()=="unload")
	check(unloads.size()==1,"the AI releases the garrison after the threat disappears")
	for command in unloads: check(submit(controller,command),"AI tower unload passes ordinary validation")
	check(world.transport_system.passenger_count(tower)==0 and world.find_unit(int(archer["id"]))!=null,"the archer actually returns to the map")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("AI tower decisions: ",failures.size()," failures"); quit(0 if failures.is_empty() else 1)

func submit(controller,command) -> bool:
	command.tick=controller.tick_index
	command.params.erase("_ai_feedback")
	controller.enqueue_command(command,true,1); controller.process_commands()
	var result: Dictionary=controller.get_command_result(command.sequence_id)
	if not bool(result.get("accepted",false)): print("AI_TOWER_REJECTION ",command.command_type()," ",result," ",command.params)
	return bool(result.get("accepted",false))
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
