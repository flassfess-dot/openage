extends SceneTree
const Access:=preload("res://scripts/ai_construction_access.gd")
const Catalog:=preload("res://scripts/resource_catalog.gd")
const World:=preload("res://scripts/simulation_world.gd")
const Controller:=preload("res://scripts/game_controller.gd")
const Commands:=preload("res://scripts/commands.gd")
const Construction:=preload("res://scripts/ai_economy_construction.gd")
const State:=preload("res://scripts/ai_strategy_state.gd")
const Budget:=preload("res://scripts/ai_plan_budget.gd")
const Nav:=preload("res://scripts/ai_navigation_knowledge.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func run() -> void:
	var land: Dictionary={}
	for y in range(12):
		for x in range(18):
			if y in [5,6] or x>=10:land[Vector2i(x,y)]=true
	check(not Access.preserves(Vector2(6.5,5.5),Vector2.ONE,land),"a two-cell road cannot be sealed")
	check(Access.preserves(Vector2(13.5,3.5),Vector2.ONE,land),"an open-room site remains usable")
	land[Vector2i(7,4)]=true;land[Vector2i(7,3)]=true
	check(not Access.preserves(Vector2(7.5,5.5),Vector2.ONE,land),"a side pocket cannot be sealed even when its worker is not the builder")
	var ordered: Array[Vector2]=[]
	for y in range(12):
		for x in range(18):
			if land.has(Vector2i(x,y)):ordered.append(Vector2(x+0.5,y+0.5))
	var bounded:=Access.prepare({"cell_geometry":true,"land":ordered})
	for site in [Vector2(6.5,5.5),Vector2(13.5,3.5),Vector2(7.5,5.5),Vector2(0.5,0.5),Vector2(17.5,11.5)]:
		check(Access.preserves(site,Vector2.ONE,bounded)==Access.preserves(site,Vector2.ONE,land),"bounded row lookup preserves the full known-cell reference at "+str(site))
	check(ordered.size()==land.size(),"read-only local extraction retains the detached navigation publication")
	var separated: Dictionary={}
	for y in range(9):
		for x in [4,7]:separated[Vector2i(x,y)]=true
	check(Access.preserves(Vector2(5.5,4.5),Vector2.ONE,separated),"pre-existing disconnection is not blamed on construction")
	var catalog=Catalog.new();catalog.load()
	var world=World.new(Vector2i(18,14));world.task_coordinator.enabled=false
	world.set_gamespec(catalog.gamespec_data);world.set_object_catalog(catalog.object_catalog_data);world.set_runtime_catalog(catalog.runtime_catalog_data);world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.navigation_grid.configure_terrain(func(cell):return "grass" if ((cell.x>=1 and cell.x<=8 and cell.y in [6,7]) or (cell.x>=9 and cell.x<=16 and cell.y>=2 and cell.y<=11)) else "water")
	var depot: Dictionary=world.add_building(90,"town_center",Vector2(13.5,7.5),1)
	var builder: Dictionary=world.add_unit(1,"villager",Vector2(5.5,6.5),false)
	var carrier: Dictionary=world.add_unit(1,"villager",Vector2(3.5,7.5),false)
	world.add_unit(2,"clubman",Vector2(16.5,10.5),false)["stance"]="passive"
	carrier["carried_amount"]=10.0;carrier["carried_resource_type_id"]=1
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):world.get_fog_of_war().reveal_explored_cell(1,Vector2i(x,y))
	world.update_fog_of_war()
	var option: Dictionary={}
	for value in world.get_build_options(1):
		if String(value.get("kind",""))=="house":option=value
	check(option.has("navigation_obstruction_half_size"),"build options expose the actual obstruction dimensions")
	var observed_builder: Dictionary=builder.duplicate(true)
	observed_builder["command_options"]={"build":[option]}
	# Detached query inputs retain real own geometry and legal navigation.
	var player: Dictionary={"food":1000,"wood":1000,"stone":1000,"gold":1000,"population":4,"population_cap":4,"population_limit":50,"blocked_population_queues":1}
	var observed: Dictionary={"tick":0,"observer_team":1,"units":[observed_builder],"buildings":[depot],"resources":[],"player_state":player,"navigation":Nav.new().snapshot(world,world.get_fog_of_war(),1),"build_sites":{"house":[Vector2(6.5,6.5),Vector2(12.5,3.5)]}}
	var state=State.new();var commands: Array=[]
	Construction.construct(observed,1,1,{"competitive":true,"maximum_foundations":2,"building_limits":{"house":10},"housing_buffer":2,"minimum_structure_gap":0.0},state,Budget.new(player,[depot]),{},commands,["house"],true,false,null)
	check(commands.size()==1,"construction still offers an affordable safe house")
	var controller=Controller.new(world);controller.set_speed_multiplier(1.0)
	if commands.size()==1:
		check(Vector2(commands[0].params["target"])==Vector2(12.5,3.5),"the closer road-closing house is rejected")
		controller.enqueue_command(commands[0],true,1);controller.advance_frame(0.05,1,2,1)
		check(bool(controller.get_command_result(commands[0].sequence_id).get("accepted",false)),"the selected site uses an accepted ordinary paid build command")
		var returned=Commands.ReturnResourcesCommand.new(controller.tick_index+1,[int(carrier["id"])],int(depot["id"]))
		controller.enqueue_command(returned,true,1)
		for step in range(700):
			controller.advance_frame(0.05,1,2,1)
			if float(carrier["carried_amount"])<=0:break
			if step%50==0:await process_frame
		check(float(carrier["carried_amount"])==0.0,"another worker actually deposits its cargo after construction")
		check(controller.events_after().any(func(e):return String(e.get("type",""))=="resources_deposited" and int(e.get("payload",{}).get("worker_id",-1))==int(carrier["id"]) and int(e.get("payload",{}).get("amount",0))==10),"the worker credits exactly ten wood through a real deposit event")
	world.task_coordinator.shutdown()
	if failures.is_empty():print("Construction access real deposit regression passed");quit(0);return
	for failure in failures:push_error(failure)
	quit(1)
