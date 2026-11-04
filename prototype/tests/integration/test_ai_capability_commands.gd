extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Commands=preload("res://scripts/commands.gd")
const Replay=preload("res://scripts/replay_system.gd")
const Planner=preload("res://scripts/ai_capability_planner.gd")
const State=preload("res://scripts/ai_strategy_state.gd")
const Budget=preload("res://scripts/ai_plan_budget.gd")
const Regions=preload("res://scripts/ai_region_model.gd")
const Snapshot=preload("res://scripts/simulation_snapshot.gd")
const Store=preload("res://scripts/ai_observation_store.gd")
var failures: Array[String]=[]
func _initialize() -> void:
	var catalog=Catalog.new(); catalog.load()
	var world=World.new(Vector2i(32,32)); world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.set_team_civilization(1,13); world.grant_technology(1,101)
	for resource in range(4): world.change_resource_amount(1,resource,1000)
	world.set_population_cap(1,50); world.set_population_housing(1,50)
	var granary: Dictionary=world.add_building(90,"granary",Vector2(10.5,10.5),1)
	var farm: Dictionary=world.add_building(91,"farm",Vector2(15.5,10.5),1)
	world.add_building(92,"market",Vector2(22.5,10.5),1)
	farm["amount"]=10
	world.add_unit(1,"villager",Vector2(10.5,13.5),false)
	world.add_unit(2,"clubman",Vector2(29.5,29.5),false)
	world.set_alliance(1,2,true); world.update_fog_of_war()
	var controller=Controller.new(world)
	var snapshot:=Snapshot.with_queries(world,0,1,{"compact_entities":true,"include_ai_profiles":true,"include_projectiles":false,"include_scenario":false})
	var state=State.new(); state.goal={"home":granary["pos"]}
	var commands: Array=Planner.plan(snapshot,0,1,{},state,Budget.new(snapshot["player_state"],snapshot["buildings"]),{},Regions.new())
	var reseed:=commands.filter(func(c): return c.command_type()=="farm_reserve")
	check(reseed.size()==1,"AI proposes one paid reseed through a granary")
	var wood_before: int=world.get_resource_amount(1,1)
	for command in reseed: submit(controller,command,1)
	check(world.economy_system.farm_reseed_queues_by_team.get(1,[]).size()==1,"accepted reserve is actually stored")
	check(world.get_resource_amount(1,1)<wood_before,"reserve is paid exactly once")
	# Keep two opposing participants while advancing the fixture; an entirely
	# allied conquest match would already finish on its first fixed tick.
	world.set_alliance(1,2,false)
	var tree: Dictionary=world.add_resource("tree",Vector2(14.5,13.5),2)
	world.update_fog_of_war()
	var clearing:=Store.new().observe_with_queries(world,controller.tick_index,1,{"compact_entities":true,"include_ai_profiles":true,"include_navigation":true,"include_projectiles":false,"include_scenario":false})
	state.goal={"home":Vector2(10.5,10.5),"position":Vector2(24.5,13.5),"needs_transport":true}
	var clearing_commands: Array=Planner.plan(clearing,controller.tick_index,1,{"competitive":true},state,Budget.new(clearing["player_state"],clearing["buildings"]),{},Regions.new()).filter(func(c): return c.command_type()=="gather" and int(c.params.get("resource_id",-1))==int(tree["id"]))
	check(not clearing_commands.is_empty(),"AI probes a known forest barrier through an ordinary gather order")
	for command in clearing_commands: check(bool(submit(controller,command,1).get("accepted",false)),"clearing order crosses the same legal command boundary")
	# A source tree must first be felled, finish its falling animation, and then
	# yield wood. Keep its real hit points and work intervals in this scenario.
	for tick in range(1200):
		controller.advance_frame(0.05,1,2)
		if int(tree.get("amount",0))==0: break
	check(int(tree.get("amount",0))==0,"worker actually spends simulation time harvesting the obstructing tree")
	if int(tree.get("amount",0))>0: print("CLEARING_DIAGNOSTIC tick=",controller.tick_index," tree=",tree["amount"]," workers=",world.get_units().filter(func(u): return int(u.get("team",0))==1).map(func(u): return {"id":u["id"],"task":u["task"],"stage":u["gather_stage"],"cycles":u["gather_cycles"]}))
	world.set_alliance(1,2,true)
	state.goal={"home":granary["pos"]}
	var intent=Commands.TeamIntentCommand.new(0,2,"resource",granary["pos"],1,150)
	check(bool(submit(controller,intent,1).get("accepted",false)),"mutual ally accepts a legal intention")
	check(world.ai_distress_system.intents_for_team(world,2).size()==1,"recipient sees only the public intent")
	var codec=Replay.new(); codec.record_command(intent)
	var decoded=codec.command_from_record(codec.command_records[0])
	check(decoded!=null and decoded.command_type()=="team_intent" and decoded.params==intent.params,"intent survives replay codec")
	world.set_alliance(1,2,false)
	check(world.ai_distress_system.intents_for_team(world,2).is_empty(),"diplomacy break removes access to intentions")
	check(not bool(submit(controller,Commands.TeamIntentCommand.new(0,2,"attack",granary["pos"]),1).get("accepted",false)),"enemy cannot receive a private allied intention")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("AI capability commands: ",failures.size()," failures"); quit(0 if failures.is_empty() else 1)
func submit(controller,command,team: int) -> Dictionary:
	controller.enqueue_command(command,true,team); controller.process_commands(); return controller.get_command_result(command.sequence_id)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
