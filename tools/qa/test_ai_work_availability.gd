extends SceneTree
const Work = preload("./ai_work_availability.gd")
const Catalog = preload("res://scripts/resource_catalog.gd")
const World = preload("res://scripts/simulation_world.gd")
const Controller = preload("res://scripts/game_controller.gd")
const Codec = preload("res://scripts/replay_system.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	var catalog=Catalog.new();catalog.load()
	for scenario in ["open","sealed","hidden","cargo"]:
		var world=World.new(Vector2i(32,32))
		world.set_gamespec(catalog.gamespec_data);world.set_object_catalog(catalog.object_catalog_data);world.set_graphics_catalog(catalog.graphics_catalog_data);world.set_runtime_catalog(catalog.runtime_catalog_data);world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.navigation_grid.configure_terrain(func(_cell):return "grass")
		world.task_coordinator.enabled=false;world.set_team_civilization(1,13)
		world.add_building(9000,"town_center",Vector2(5.5,10.5),1)
		var worker: Dictionary=world.add_unit(1,"villager",Vector2(10.5,10.5) if scenario!="sealed" else Vector2(22.5,10.5),false)
		var berries: Dictionary=world.add_resource("berries",Vector2(12.5,10.5) if scenario=="open" else Vector2(26.5,10.5),1000)
		if scenario=="sealed":
			for y in range(32):world.add_building(9100+y,"wall",Vector2(16.5,float(y)+0.5),0)
		if scenario=="cargo":
			world.set_entity_field(worker,"carried_amount",10.0);world.set_entity_field(worker,"carried_resource_type_id",0)
		world.update_fog_of_war()
		var controller=Controller.new(world)
		var before: String=Codec.new().world_state_hash(world,0,controller)
		var available: bool=Work.confirmed_work(world,worker,world.get_resources(),world.get_buildings())
		check(available==(scenario in ["open","cargo"]),scenario+": only a known job and reachable compatible depot confirm work")
		check(before==Codec.new().world_state_hash(world,0,controller),scenario+": querying work never changes authoritative state or reservations")
		if scenario=="cargo":
			world.set_entity_field(worker,"carried_resource_type_id",-1)
			check(not Work.confirmed_work(world,worker,[],world.get_buildings()),"unknown cargo cannot prove work")
		if scenario=="open":
			var sampler=Work.new();sampler.consume(world,0)
			world.set_entity_field(worker,"task","gather")
			sampler.consume(world,20);sampler.consume(world,40)
			var result: Dictionary=sampler.report()[1]
			check(result["available_ticks"]==40 and result["idle_available_ticks"]==20,"sampling integrates the prior fixed interval")
			check(is_equal_approx(result["conditional_idle_lower_bound"],0.5) and is_equal_approx(result["conditional_idle_upper_bound"],0.5),"confirmed work produces the measured conditional idle ratio")
			var points: Array[Vector2]=preload("res://scripts/building_approach_geometry.gd").perimeter_candidates(worker,world.get_buildings()[0],world.map_size)
			var reservations: Dictionary={}
			for index in range(points.size()):reservations[1000+index]=points[index]
			world.building_approach_slots[9000]=reservations
			before=Codec.new().world_state_hash(world,0,controller)
			check(not Work.confirmed_work(world,worker,world.get_resources(),world.get_buildings()),"fully reserved delivery approaches cannot confirm available work")
			check(before==Codec.new().world_state_hash(world,0,controller),"checking occupied approaches preserves every reservation")
			reservations.erase(1000);reservations[int(worker["id"])]=points[0]
			check(Work.confirmed_work(world,worker,world.get_resources(),world.get_buildings()),"a worker retains access to its own reserved approach")
		if scenario=="sealed":
			var sampler=Work.new();sampler.consume(world,0);sampler.consume(world,20)
			var result: Dictionary=sampler.report()[1]
			check(result["unknown_ticks"]==20 and is_equal_approx(result["conditional_idle_upper_bound"],1.0),"unproved jobs remain unknown instead of reducing the idle denominator")
		print("WORK_AVAILABILITY ",scenario," confirmed=",available," resource=",berries["id"])
		world.shutdown_derived_state()
	for failure in failures:push_error(failure)
	print("Work availability: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
