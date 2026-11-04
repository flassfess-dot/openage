extends SceneTree
const Catalog:=preload("res://scripts/resource_catalog.gd")
const World:=preload("res://scripts/simulation_world.gd")
const Controller:=preload("res://scripts/game_controller.gd")
const Snapshot:=preload("res://scripts/simulation_snapshot.gd")
const Commands:=preload("res://scripts/commands.gd")
const Traffic:=preload("res://scripts/ai_traffic_clearance.gd")
const State:=preload("res://scripts/ai_strategy_state.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func run() -> void:
	var catalog=Catalog.new();catalog.load()
	var world=World.new(Vector2i(18,12));world.task_coordinator.enabled=false
	world.set_gamespec(catalog.gamespec_data);world.set_object_catalog(catalog.object_catalog_data);world.set_runtime_catalog(catalog.runtime_catalog_data);world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.navigation_grid.configure_terrain(func(cell):return "grass" if (cell.y==5 or (cell.x==7 and cell.y in [6,7]) or (cell.x>=10 and cell.x<=15 and cell.y>=2 and cell.y<=9)) else "water")
	var depot: Dictionary=world.add_building(90,"town_center",Vector2(13.5,5.5),1)
	world.add_building(91,"town_center",Vector2(16.5,10.5),2)
	var carrier: Dictionary=world.add_unit(1,"villager",Vector2(5.5,5.5),false)
	var soldier: Dictionary=world.add_unit(1,"clubman",Vector2(7.5,5.5),false)
	carrier["carried_amount"]=10.0;carrier["carried_resource_type_id"]=1;carrier["diagnostic_reason"]="stuck_stopped_nearest_valid"
	for y in range(world.map_size.y):
		for x in range(world.map_size.x):world.get_fog_of_war().reveal_explored_cell(1,Vector2i(x,y))
	world.update_fog_of_war()
	var options:={"compact_entities":true,"include_ai_profiles":true,"include_navigation":true,"include_build_sites":false,"include_fog_cells":false}
	var snapshot:=Snapshot.with_queries(world,0,1,options)
	var state=State.new();var reserved: Dictionary={}
	var moves:=Traffic.plan(snapshot,1,1,state,reserved)
	check(moves.size()==1,"one idle friendly soldier yields into the side pocket")
	check(moves.is_empty() or moves[0].unit_ids==[int(soldier["id"])],"clearance never redirects the loaded worker")
	check(Traffic.plan(snapshot,2,1,state,{}).is_empty(),"the retry cooldown prevents repeated orders")
	for protected_task in ["hold","attack","gather","build"]:
		var changed: Dictionary=snapshot.duplicate(true)
		for unit in changed["units"]:
			if int(unit["id"])==int(soldier["id"]):unit["task"]=protected_task
		check(Traffic.plan(changed,1,1,State.new(),{}).is_empty(),"active or held units retain their orders: "+protected_task)
	var foreign: Dictionary=snapshot.duplicate(true)
	for unit in foreign["units"]:
		if int(unit["id"])==int(soldier["id"]):unit["team"]=2
	check(Traffic.plan(foreign,1,1,State.new(),{}).is_empty(),"an enemy cannot be issued a clearance order")
	var controller=Controller.new(world);controller.set_speed_multiplier(1.0)
	for move in moves:controller.enqueue_command(move,true,1)
	for step in range(100):controller.advance_frame(0.05,1,2,1)
	for move in moves:check(bool(controller.get_command_result(move.sequence_id).get("accepted",false)),"the real clearance move is accepted")
	var returned=Commands.ReturnResourcesCommand.new(controller.tick_index+1,[int(carrier["id"])],int(depot["id"]))
	controller.enqueue_command(returned,true,1)
	for step in range(400):
		controller.advance_frame(0.05,1,2,1)
		if float(carrier["carried_amount"])<=0:break
		if step%50==0:await process_frame
	if float(carrier["carried_amount"])>0:
		print("Traffic delivery diagnostic ",{"carrier_pos":carrier["pos"],"task":carrier["task"],"reason":carrier["diagnostic_reason"],"path":carrier["path"],"soldier_pos":soldier["pos"],"soldier_reason":soldier["diagnostic_reason"],"moves":moves.map(func(c):return c.params),"return_result":controller.get_command_result(returned.sequence_id),"battle_over":world.battle_over})
	check(float(carrier["carried_amount"])==0,"the worker completes its real delivery after the soldier yields")
	check(controller.events_after().any(func(e):return String(e.get("type",""))=="resources_deposited" and int(e.get("payload",{}).get("worker_id",-1))==int(carrier["id"]) and int(e.get("payload",{}).get("amount",0))==10),"clearance results in exactly ten wood credited to its owner")
	world.task_coordinator.shutdown()
	if failures.is_empty():print("AI traffic clearance real deposit regression passed");quit(0);return
	for failure in failures:push_error(failure)
	quit(1)
