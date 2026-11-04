extends SceneTree
const Catalog=preload("res://scripts/resource_catalog.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
const Commands=preload("res://scripts/commands.gd")
const Snapshot=preload("res://scripts/simulation_snapshot.gd")
const Construction=preload("res://scripts/ai_economy_construction.gd")
const State=preload("res://scripts/ai_strategy_state.gd")
const Budget=preload("res://scripts/ai_plan_budget.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	var catalog=Catalog.new(); catalog.load()
	var world=World.new(Vector2i(32,32))
	world.set_gamespec(catalog.gamespec_data); world.set_object_catalog(catalog.object_catalog_data); world.set_graphics_catalog(catalog.graphics_catalog_data); world.set_runtime_catalog(catalog.runtime_catalog_data); world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	world.task_coordinator.enabled=false
	for team in [1,2]: world.set_population_cap(team,50); world.set_population_housing(team,50)
	world.set_team_civilization(1,13); world.grant_technology(1,101)
	world.add_building(90,"town_center",Vector2(5.5,5.5),1)
	world.add_building(91,"town_center",Vector2(28.5,28.5),2)
	var foundation: Dictionary=world.add_building(80,"market",Vector2(14.5,14.5),1,false)
	var house: Dictionary=world.add_building(81,"house",Vector2(7.5,18.5),1,false)
	var worker: Dictionary=world.add_unit(1,"villager",Vector2(5.5,16.5),false)
	# A route can become blocked after a foundation is laid. Surround only the
	# abandoned market, keeping a second real construction job reachable.
	var minimum:=Vector2i(32,32); var maximum:=Vector2i.ZERO
	for cell in foundation["occupied_cells"]: minimum=minimum.min(cell); maximum=maximum.max(cell)
	var id:=200
	for y in range(minimum.y-1,maximum.y+2):
		for x in range(minimum.x-1,maximum.x+2):
			if x in [minimum.x-1,maximum.x+1] or y in [minimum.y-1,maximum.y+1]:
				world.add_building(id,"wall",Vector2(x+0.5,y+0.5),1); id+=1
	world.update_fog_of_war()
	var controller=Controller.new(world)
	var build=Commands.BuildCommand.new(0,[int(worker["id"])],"house",house["pos"])
	controller.enqueue_command(build,true,1); controller.process_commands()
	check(bool(controller.get_command_result(build.sequence_id).get("accepted",false)),"the reachable construction uses an ordinary build order")
	var state=State.new(); var policy:={"competitive":true,"maximum_foundations":2,"foundation_stall_ticks":600}
	plan(world,controller,state,policy)
	for tick in range(601): controller.advance_frame(0.05,1,2,1)
	# A very slow active foundation must survive even before visible HP rises.
	world.set_entity_field(house,"state","foundation"); world.set_entity_field(house,"construction_progress",0.01)
	var observed:=Snapshot.with_queries(world,controller.tick_index,1,{"compact_entities":true})
	var own: Array=observed["buildings"].filter(func(b): return int(b.get("id",-1))==81)
	check(not own.is_empty() and is_equal_approx(float(own[0].get("construction_progress",0.0)),0.01),"own AI observation exposes exact construction progress")
	var commands:=plan(world,controller,state,policy)
	var abandoned:=commands.filter(func(c): return c.command_type()=="delete_entity" and 80 in c.unit_ids)
	check(abandoned.size()==1,"AI releases the foundation that made no construction progress")
	check(not commands.any(func(c): return c.command_type()=="delete_entity" and 81 in c.unit_ids),"active or completed construction is retained")
	var wood_before: int=world.get_resource_amount(1,1)
	for command in abandoned:
		command.params.erase("_ai_feedback")
		controller.enqueue_command(command,true,1); controller.process_commands()
		check(bool(controller.get_command_result(command.sequence_id).get("accepted",false)),"abandonment crosses ordinary owned-entity validation")
	check(float(foundation["hp"])<=0.0,"the blocked foundation is actually removed from play")
	check(world.get_resource_amount(1,1)==wood_before,"recovery does not fabricate a resource refund")
	check(not state.metrics.get("last_abandoned_foundation",{}).is_empty(),"the recovery reason is observable and saved in AI state")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("AI foundation recovery: ",failures.size()," failures"); quit(0 if failures.is_empty() else 1)

func plan(world,controller,state,policy: Dictionary) -> Array:
	var snapshot:=Snapshot.with_queries(world,controller.tick_index,1,{"compact_entities":true,"include_ai_profiles":true,"recover_abandoned_foundations_only":false})
	var structures: Array=snapshot["buildings"].filter(func(b): return int(b.get("team",0))==1 and float(b.get("hp",0))>0)
	var units: Array=snapshot["units"].filter(func(u): return int(u.get("team",0))==1)
	var workers: Array=units.filter(func(u): return bool(u.get("components",{}).get("worker",{}).get("enabled",false)))
	var result: Array=[]
	Construction.resume_foundations(snapshot,controller.tick_index,policy,state,Budget.new(snapshot["player_state"],structures),{},result,structures,units,workers)
	return result
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
