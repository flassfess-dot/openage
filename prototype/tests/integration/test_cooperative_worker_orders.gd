extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const MatchBootstrap := preload("res://scripts/match_bootstrap.gd")
const GameController := preload("res://scripts/game_controller.gd")
const Commands := preload("res://scripts/commands.gd")
const Footprint := preload("res://scripts/footprint.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_adjacent_worker_starts_immediately(catalog)
	verify_shared_gather(catalog, "berries")
	verify_shared_gather(catalog, "gold_mine")
	verify_shared_gather(catalog, "stone_mine")
	verify_neighboring_berry_slots(catalog)
	verify_depleted_cluster_handoff(catalog)
	verify_shared_construction(catalog)
	verify_builder_rate_projection(catalog)
	verify_ai_crew_single_cost(catalog)
	verify_ai_existing_crew(catalog)
	verify_independent_workers_join_existing_foundation(catalog)
	verify_completed_builder_handoff(catalog)
	verify_generated_shared_gather(catalog, "berries")
	verify_generated_shared_gather(catalog, "gold_mine")
	verify_generated_shared_gather(catalog, "stone_mine")
	verify_generated_shared_construction(catalog)
	if failures.is_empty():
		print("Cooperative worker gathering and construction passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_adjacent_worker_starts_immediately(catalog) -> void:
	var world = fixture(catalog)
	var resource: Dictionary = world.add_resource("berries", Vector2(13.5, 14.5), 50)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(12.5, 14.5), false)
	world.assign_command_gather([worker], int(resource["id"]))
	world.update_units(0.05, 1, 2)
	if int(worker.get("gather_cycles", 0)) <= 0:
		failures.append("adjacent worker waits instead of starting berry harvest on the first work tick; %s" % worker_diagnostics([worker]))


func verify_shared_gather(catalog, kind: String) -> void:
	var world = fixture(catalog)
	world.add_building(800, "town_center", Vector2(21.5, 14.5), 1)
	var resource: Dictionary = world.add_resource(kind, Vector2(13.5, 14.5), 200)
	var workers := starting_workers(world, 8)
	world.assign_command_gather(workers, int(resource["id"]))
	var peak_active := 0
	var minimum_harvesting_clearance := INF
	for step in range(1400):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		var harvesting: Array = workers.filter(func(worker): return String(worker.get("gather_stage", "")) == "harvesting" and int(worker.get("resource_id", -1)) == int(resource["id"]))
		peak_active = maxi(peak_active, harvesting.size())
		for left_index in range(harvesting.size()):
			for right_index in range(left_index + 1, harvesting.size()):
				var left: Dictionary = harvesting[left_index]
				var right: Dictionary = harvesting[right_index]
				var clearance := Vector2(left["pos"]).distance_to(Vector2(right["pos"])) - Footprint.separation_distance(left, right)
				minimum_harvesting_clearance = minf(minimum_harvesting_clearance, clearance)
		if workers.all(func(worker): return int(worker.get("gather_cycles", 0)) > 0):
			break
	var working_count := workers.filter(func(worker): return int(worker.get("gather_cycles", 0)) > 0).size()
	if working_count != workers.size() or peak_active < 2:
		failures.append("%s: only %d/%d workers gathered, peak simultaneous=%d; %s" % [kind, working_count, workers.size(), peak_active, worker_diagnostics(workers)])
	if minimum_harvesting_clearance < -0.12:
		failures.append("%s: workers overlap while harvesting by %.2f tiles; %s" % [kind, -minimum_harvesting_clearance, worker_diagnostics(workers)])


func verify_neighboring_berry_slots(catalog) -> void:
	var world = fixture(catalog)
	var first: Dictionary = world.add_resource("berries", Vector2(13.5, 14.5), 100)
	var second: Dictionary = world.add_resource("berries", Vector2(15.5, 14.5), 100)
	var left_worker: Dictionary = world.add_unit(1, "villager", Vector2(16.5, 14.5), false)
	var right_worker: Dictionary = world.add_unit(1, "villager", Vector2(12.5, 14.5), false)
	world.assign_command_gather([left_worker], int(first["id"]))
	world.assign_command_gather([right_worker], int(second["id"]))
	var left_slot: Variant = left_worker.get("resource_approach_slot")
	var right_slot: Variant = right_worker.get("resource_approach_slot")
	if not left_slot is Vector2 or not right_slot is Vector2:
		failures.append("neighboring berry bushes did not reserve both working positions")
		return
	if left_slot.distance_to(right_slot) < Footprint.separation_distance(left_worker, right_worker):
		failures.append("neighboring berry bushes reserve overlapping worker positions: %s and %s" % [left_slot, right_slot])


func verify_depleted_cluster_handoff(catalog) -> void:
	var world = fixture(catalog)
	world.add_building(800, "town_center", Vector2(21.5, 14.5), 1)
	var first: Dictionary = world.add_resource("berries", Vector2(13.5, 14.5), 1)
	var neighbor: Dictionary = world.add_resource("berries", Vector2(15.5, 14.5), 200)
	var worker: Dictionary = starting_workers(world, 1)[0]
	world.assign_command_gather([worker], int(first["id"]))
	for step in range(1400):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		if int(worker.get("gather_cycles", 0)) > 1:
			break
	if int(worker.get("gather_cycles", 0)) <= 1 or int(worker.get("resource_id", -1)) != int(neighbor["id"]):
		failures.append("depleted berry cluster does not hand worker to adjacent bush; %s" % worker_diagnostics([worker]))


func verify_shared_construction(catalog) -> void:
	var world = fixture(catalog)
	world.set_resource_amount(1, 1, 1000)
	var workers := starting_workers(world)
	world.update_fog_of_war()
	var foundation: Variant = world.assign_command_build(workers, "house", Vector2(11.5, 14.5))
	if foundation == null:
		failures.append("house foundation rejected: %s" % world.last_build_failure)
		return
	var contributing_workers: Dictionary = {}
	var peak_builders := 0
	for step in range(1400):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		for builder_id in foundation.get("builders", {}).keys():
			contributing_workers[int(builder_id)] = true
		peak_builders = maxi(peak_builders, workers.filter(func(worker): return String(worker.get("task", "")) == "build" and Vector2(worker.get("pos", Vector2.ZERO)).distance_to(Vector2(foundation["pos"])) < 3.0).size())
		if foundation.get("state", "") == "complete":
			break
	if contributing_workers.size() < 2 or peak_builders < 2 or String(foundation.get("state", "")) != "complete":
		failures.append("house: %d/%d workers contributed, peak simultaneous=%d, state=%s progress=%.3f; %s" % [contributing_workers.size(), workers.size(), peak_builders, foundation.get("state", ""), float(foundation.get("construction_progress", 0.0)), worker_diagnostics(workers)])


func verify_independent_workers_join_existing_foundation(catalog) -> void:
	var world = fixture(catalog)
	world.set_resource_amount(1, 1, 1000)
	var first: Dictionary = world.add_unit(1, "villager", Vector2(8.5, 13.5), false)
	var second: Dictionary = world.add_unit(1, "villager", Vector2(8.5, 15.5), false)
	world.update_fog_of_war()
	var before_wood:int=world.economy_system.get_resource_amount(1,1)
	var cost:Dictionary=world.building_cost("house",1)
	var foundation: Variant = world.assign_command_build([first], "house", Vector2(11.5, 14.5))
	var joined: Variant = world.assign_command_build([second], "house", Vector2(11.5, 14.5))
	if foundation == null or joined == null:
		failures.append("independently selected workers could not target the same foundation: %s" % world.last_build_failure)
		return
	if int(joined.get("id", -1)) != int(foundation.get("id", -1)):
		failures.append("second selection created a different project instead of joining foundation %d" % int(foundation.get("id", -1)))
	if world.economy_system.get_resource_amount(1,1)!=before_wood-int(cost.get(1,0)):
		failures.append("joining a paid foundation charged a second construction cost")
	if [first, second].any(func(worker): return int(worker.get("target_building_id", -1)) != int(foundation.get("id", -1)) or String(worker.get("task", "")) != "build"):
		failures.append("construction assignment depends on the workers having shared an earlier selection group; %s" % worker_diagnostics([first, second]))


func verify_completed_builder_handoff(catalog) -> void:
	var world = fixture(catalog)
	world.set_resource_amount(1, 1, 1000)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(10.5, 14.5), false)
	world.update_fog_of_war()
	var first: Variant = world.place_foundation(1, "house", Vector2(11.5, 14.5), [worker])
	var second: Variant = world.place_foundation(1, "house", Vector2(14.5, 14.5))
	if first == null or second == null:
		failures.append("builder handoff fixture could not place adjacent foundations: %s" % world.last_build_failure)
		return
	world.update_fog_of_war()
	first["construction_required"] = 0.01
	for unused in range(40):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		if String(first.get("state", "")) == "complete" and int(worker.get("target_building_id", -1)) == int(second.get("id", -1)):
			break
	if String(first.get("state", "")) != "complete" or String(worker.get("task", "")) != "build" or int(worker.get("target_building_id", -1)) != int(second.get("id", -1)):
		failures.append("builder does not continue with a visible reachable foundation after completing its goal; %s" % worker_diagnostics([worker]))


func verify_generated_shared_gather(catalog, kind: String) -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = "grasslands"
	settings["map_size_id"] = "compact"
	settings["seed"] = 41721
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = index < 2
	var built := SkirmishSettings.build(settings)
	if not bool(built.get("valid", false)):
		failures.append("generated %s match invalid: %s" % [kind, built.get("errors", [])])
		return
	var world = fixture(catalog, Vector2i(built["map_data"]["size"]))
	MatchBootstrap.apply(world, built["definition"], built["map_data"])
	var workers: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "villager")
	var start := Vector2(built["definition"]["players"][0]["start"])
	var candidates: Array = world.get_resources().filter(func(resource): return String(resource.get("kind", "")) == kind and Vector2(resource.get("pos", Vector2.ZERO)).distance_to(start) <= 20.0)
	candidates.sort_custom(func(left, right): return Vector2(left["pos"]).distance_squared_to(start) < Vector2(right["pos"]).distance_squared_to(start))
	if candidates.is_empty():
		failures.append("generated %s has no nearby resource" % kind)
		return
	for y in range(floori(start.y) - 4, floori(start.y) + 5):
		for x in range(floori(start.x) - 4, floori(start.x) + 5):
			if workers.size() >= 8:
				break
			var position := Vector2(x + 0.5, y + 0.5)
			if workers.any(func(worker): return Vector2(worker["pos"]).distance_to(position) < 0.8):
				continue
			if not world.navigation_grid.is_position_walkable_for(position, 0.3, "land", int(workers[0].get("terrain_restriction", -1))):
				continue
			if world.pathfinder.find_path(position, Vector2(workers[0]["pos"]), "land", int(workers[0].get("terrain_restriction", -1))).is_empty():
				continue
			workers.append(world.add_unit(1, "villager", position, false))
	if workers.size() < 8:
		failures.append("generated %s could place only %d test workers" % [kind, workers.size()])
		return
	var worker_ids: Array[int] = []
	for worker in workers:
		worker_ids.append(int(worker["id"]))
	var controller := GameController.new(world)
	var command = Commands.GatherCommand.new(1, worker_ids, int(candidates[0]["id"]))
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	if not bool(controller.get_command_result(command.sequence_id).get("accepted", false)):
		failures.append("generated %s group gather command was rejected" % kind)
		return
	for step in range(1400):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		if workers.all(func(worker): return int(worker.get("gather_cycles", 0)) > 0):
			break
	var working_count := workers.filter(func(worker): return int(worker.get("gather_cycles", 0)) > 0).size()
	if working_count != workers.size():
		failures.append("generated %s: only %d/%d workers gathered; %s" % [kind, working_count, workers.size(), worker_diagnostics(workers)])


func verify_generated_shared_construction(catalog) -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_type_id"] = "grasslands"
	settings["map_size_id"] = "compact"
	settings["seed"] = 41721
	for index in range(settings["players"].size()):
		settings["players"][index]["enabled"] = index < 2
	var built := SkirmishSettings.build(settings)
	if not bool(built.get("valid", false)):
		failures.append("generated construction match invalid: %s" % [built.get("errors", [])])
		return
	var world = fixture(catalog, Vector2i(built["map_data"]["size"]))
	MatchBootstrap.apply(world, built["definition"], built["map_data"])
	world.set_resource_amount(1, 1, 1000)
	var workers: Array = world.get_units().filter(func(unit): return int(unit.get("team", 0)) == 1 and String(unit.get("kind", "")) == "villager")
	var sites: Array = world.get_local_build_sites(1, ["house"], 1, 8).get("house", [])
	if sites.is_empty():
		failures.append("generated construction has no reachable house site")
		return
	var worker_ids: Array[int] = []
	for worker in workers:
		worker_ids.append(int(worker["id"]))
	var controller := GameController.new(world)
	var command = Commands.BuildCommand.new(1, worker_ids, "house", sites[0])
	controller.enqueue_command(command, true, 1)
	controller.advance_frame(0.05, 1, 2)
	if not bool(controller.get_command_result(command.sequence_id).get("accepted", false)):
		failures.append("generated construction group command was rejected")
		return
	var foundations: Array = world.get_buildings().filter(func(building): return String(building.get("kind", "")) == "house" and String(building.get("state", "")) == "foundation" and Vector2(building.get("pos", Vector2.ZERO)).distance_to(Vector2(sites[0])) < 0.1)
	var foundation: Variant = foundations[0] if not foundations.is_empty() else null
	if foundation == null:
		failures.append("generated construction rejected: %s" % world.last_build_failure)
		return
	var contributing: Dictionary = {}
	for step in range(1400):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		world.update_fog_of_war()
		for worker_id in foundation.get("builders", {}).keys():
			contributing[int(worker_id)] = true
		if String(foundation.get("state", "")) == "complete":
			break
	if contributing.size() < 2 or String(foundation.get("state", "")) != "complete":
		failures.append("generated house: %d workers contributed, state=%s; %s" % [contributing.size(), foundation.get("state", ""), worker_diagnostics(workers)])


func fixture(catalog, size: Vector2i = Vector2i(32, 32)):
	var world = SimulationWorld.new(size)
	world.set_gamespec(catalog.gamespec_data)
	world.set_terrain_catalog(catalog.terrain_catalog_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func starting_workers(world, count: int = 4) -> Array:
	var workers: Array = []
	for index in range(count):
		workers.append(world.add_unit(1, "villager", Vector2(8.5 + float(index / 4) * 0.7, 12.5 + float(index % 4)), false))
	return workers


func worker_diagnostics(workers: Array) -> String:
	var details: Array[String] = []
	for worker_value in workers:
		var worker: Dictionary = worker_value
		details.append("id%d task=%s cycles=%d pos=%s slot=%s path=%s reason=%s stage=%s leg=%s destination=%s velocity=%s stuck=%s retries=%s watch=%s" % [int(worker.get("id", -1)), worker.get("task", ""), int(worker.get("gather_cycles", 0)), str(worker.get("pos", Vector2.ZERO)), str(worker.get("resource_approach_slot", worker.get("building_approach_slot", null))), worker.get("path_status", ""), worker.get("diagnostic_reason", ""),worker.get("gather_stage",""),str(worker.get("target")),str(worker.get("destination")),str(worker.get("actual_velocity")),str(worker.get("stuck_ticks")),str(worker.get("work_recovery_attempts",0)),str(worker.get("navigation_progress",{}))])
	return "; ".join(details)


func verify_builder_rate_projection(catalog) -> void:
	var queries=preload("res://scripts/simulation_observation_queries.gd")
	var world=fixture(catalog)
	world.set_resource_amount(1,1,1000)
	var first:Dictionary=world.add_unit(1,"villager",Vector2(9.5,13.5),false)
	var second:Dictionary=world.add_unit(1,"villager",Vector2(9.5,15.5),false)
	var enemy:Dictionary=world.add_unit(2,"villager",Vector2(18.5,14.5),false)
	var berries:Dictionary=world.add_resource("berries",Vector2(7.5,13.5),100)
	world.assign_command_gather([first],int(berries["id"]))
	var role:Dictionary=world.worker_role_system.profile_for_task(first,"build")
	var role_id:=int(role.get("role_source_unit_id",-1))
	if role_id<0:failures.append("builder role missing in productivity fixture");world.shutdown_derived_state();return
	var base_rate:float=world.worker_role_system.expected_task_work_rate(first,"build")
	var technology=world.technology_system
	technology.catalog=technology.catalog.duplicate(false)
	technology.catalog["effect_bundles"]=technology.catalog.get("effect_bundles",{}).duplicate(false)
	technology.catalog["effect_bundles"]["900001"]={"commands":[{"type_id":5,"attr_a":role_id,"attr_b":-1,"attr_c":13,"attr_d":1.25},{"type_id":4,"attr_a":role_id,"attr_b":-1,"attr_c":13,"attr_d":0.2}]}
	technology.apply_effect_bundle(1,900001)
	var own_rate:float=world.worker_role_system.expected_task_work_rate(first,"build")
	if not is_equal_approx(own_rate,base_rate*1.25+0.2):failures.append("own builder technology modifiers were omitted from the forecast")
	technology.apply_effect_bundle(2,900001)
	if not is_equal_approx(world.worker_role_system.expected_task_work_rate(first,"build"),own_rate):failures.append("foreign builder technology contaminated the own forecast")
	world.update_fog_of_war()
	var input:={"tick":0,"observer_team":1,"units":[first,second,enemy],"buildings":[],"resources":[]}
	var options:={"include_navigation":false,"include_build_sites":false,"include_worker_command_options":false,"include_builder_productivity":true}
	var before:=var_to_bytes([first,second,enemy])
	var projected:Dictionary=queries.enrich(world,input,options)
	if var_to_bytes([first,second,enemy])!=before:failures.append("future builder productivity query changed an authoritative worker")
	var expected:Dictionary={}
	for row in projected["units"]:
		if int(row["team"])==1:
			if not row.has("construction_work_rate"):failures.append("owned builder productivity was not projected")
			else:expected[int(row["id"])]=float(row["construction_work_rate"])
		elif row.has("construction_work_rate"):failures.append("builder productivity exposed a foreign worker's private role")
	var legacy_options:Dictionary=options.duplicate(true);legacy_options.erase("include_builder_productivity")
	if queries.enrich(world,input,legacy_options)["units"].any(func(row):return row.has("construction_work_rate")):failures.append("legacy observation gained builder-only metadata")
	var tactical:Dictionary=input.duplicate(false);tactical["tactical_only"]=true
	if queries.enrich(world,tactical,options)["units"].any(func(row):return row.has("construction_work_rate")):failures.append("tactical-only capture performed economic builder projection")
	var foundation:Variant=world.assign_command_build([first,second],"house",Vector2(11.5,14.5))
	if foundation==null:failures.append("builder projection fixture foundation rejected");return
	var rate:=0.0
	for worker in [first,second]:
		var actual:=float(worker["components"]["worker"]["work_rate"])
		if not expected.has(int(worker["id"])) or not is_equal_approx(actual,float(expected[int(worker["id"])])):failures.append("predicted builder role rate disagrees with actual assignment")
		rate+=actual
	var progress:=float(foundation["construction_progress"])
	world.update_units(0.05,1,2)
	var delta:=float(foundation["construction_progress"])-progress
	var predicted_delta:=0.05*rate/float(foundation["construction_required"])
	if not is_equal_approx(delta,predicted_delta):failures.append("crew additive work forecast disagrees with authoritative construction progress: %f vs %f" % [delta,predicted_delta])
	world.shutdown_derived_state()


func verify_ai_crew_single_cost(catalog) -> void:
	var queries=preload("res://scripts/simulation_observation_queries.gd")
	var construction=preload("res://scripts/ai_economy_construction.gd")
	var state=preload("res://scripts/ai_strategy_state.gd").new()
	var budget_type=preload("res://scripts/ai_plan_budget.gd")
	var snapshot_type=preload("res://scripts/simulation_snapshot.gd")
	var world=fixture(catalog)
	world.set_resource_amount(1,1,1000)
	var first:Dictionary=world.add_unit(1,"villager",Vector2(9.5,13.5),false)
	var second:Dictionary=world.add_unit(1,"villager",Vector2(9.5,15.5),false)
	world.set_population_housing(1,2)
	world.update_fog_of_war()
	var snapshot:={"tick":0,"observer_team":1,"units":[first,second],"buildings":[],"resources":[],"navigation":{},"player_state":snapshot_type.presentation_player_state(world,1)}
	snapshot=queries.enrich(world,snapshot,{"include_navigation":false,"include_build_sites":false,"include_builder_productivity":true})
	# This controlled flat fixture supplies its legal site after the optional
	# site producer has been disabled; enrich intentionally clears that root.
	snapshot["build_sites"]={"house":[Vector2(11.5,14.5)]}
	snapshot=preload("res://scripts/isolated_task_data.gd").capture_frozen(snapshot)
	if snapshot.is_empty():failures.append("AI crew fixture snapshot was not detached");world.shutdown_derived_state();return
	var budget=budget_type.new(snapshot["player_state"],[])
	var policy:={"competitive":true,"building_limits":{"house":1},"maximum_foundations":2,"housing_buffer":3,"minimum_structure_gap":0.0}
	var commands: Array=[]
	var reserved: Dictionary={}
	var before:=var_to_bytes(snapshot)
	construction.construct(snapshot,1,1,policy,state,budget,reserved,commands,["house"],true,false,null)
	if var_to_bytes(snapshot)!=before:failures.append("AI crew planning changed its legal snapshot")
	if commands.size()!=1 or commands[0].unit_ids.size()!=2:
		print("AI_CREW_DIAGNOSTIC ",JSON.stringify({"commands":commands.map(func(c):return {"type":c.command_type(),"ids":c.unit_ids}),"sites":snapshot.get("build_sites",{}),"workers":snapshot["units"].map(func(w):return {"team":w.get("team"),"hp":w.get("hp"),"task":w.get("task"),"domain":w.get("movement_domain"),"worker":w.get("components",{}).get("worker",{})}),"player":snapshot["player_state"],"metrics":state.metrics,"budget":budget.remaining}))
		failures.append("AI blocked-housing plan did not choose one shared two-worker project")
		world.shutdown_derived_state();return
	var cost:Dictionary=world.building_cost("house",1)
	if int(budget.remaining[1])!=1000-int(cost.get(1,0)):failures.append("AI crew budget charged the foundation per worker")
	var controller:=GameController.new(world)
	controller.enqueue_command(commands[0],true,1)
	controller.advance_frame(0.05,1,2)
	if var_to_bytes(snapshot)!=before:failures.append("ordinary build execution changed the captured AI input")
	var foundations:Array=world.get_buildings().filter(func(b):return String(b.get("kind",""))=="house" and String(b.get("state",""))=="foundation")
	if not bool(controller.get_command_result(commands[0].sequence_id).get("accepted",false)) or foundations.size()!=1 or world.economy_system.get_resource_amount(1,1)!=1000-int(cost.get(1,0)):failures.append("AI crew command did not create one normally paid foundation through the controller")
	world.shutdown_derived_state()


func verify_ai_existing_crew(catalog) -> void:
	var queries=preload("res://scripts/simulation_observation_queries.gd")
	var construction=preload("res://scripts/ai_economy_construction.gd")
	var state=preload("res://scripts/ai_strategy_state.gd").new()
	var budget_type=preload("res://scripts/ai_plan_budget.gd")
	var snapshot_type=preload("res://scripts/simulation_snapshot.gd")
	var data=preload("res://scripts/isolated_task_data.gd")
	var world=fixture(catalog)
	world.set_resource_amount(1,1,1000)
	var first:Dictionary=world.add_unit(1,"villager",Vector2(9.5,13.5),false)
	var second:Dictionary=world.add_unit(1,"villager",Vector2(9.5,15.5),false)
	world.set_population_housing(1,2);world.update_fog_of_war()
	var foundation:Variant=world.assign_command_build([first],"house",Vector2(11.5,14.5))
	if foundation==null:failures.append("existing AI crew fixture rejected");return
	var paid_stock:int=world.economy_system.get_resource_amount(1,1)
	var snapshot:={"tick":0,"observer_team":1,"units":[first,second],"buildings":[foundation],"resources":[],"navigation":{"unit_regions":{int(first["id"]):1,int(second["id"]):1}},"player_state":snapshot_type.presentation_player_state(world,1)}
	snapshot=queries.enrich(world,snapshot,{"include_navigation":false,"include_build_sites":false,"include_builder_productivity":true,"recover_abandoned_foundations_only":true})
	snapshot["navigation"]={"unit_regions":{int(first["id"]):1,int(second["id"]):1}}
	snapshot=data.capture_frozen(snapshot)
	var policy:={"competitive":true,"maximum_foundations":2}
	var commands: Array=[]
	var budget=budget_type.new(snapshot["player_state"],snapshot["buildings"])
	construction.resume_foundations(snapshot,1,policy,state,budget,{},commands,snapshot["buildings"],snapshot["units"],snapshot["units"])
	if commands.size()!=1 or commands[0].unit_ids!=[int(second["id"])]:failures.append("active foundation ROI did not add only the new helper")
	if int(budget.remaining[1])!=paid_stock:failures.append("active crew reserved another foundation price")
	var reserved:Dictionary={};reserved[int(second["id"])]=true
	var blocked: Array=[]
	construction.resume_foundations(snapshot,1,policy,state,budget,reserved,blocked,snapshot["buildings"],snapshot["units"],snapshot["units"])
	if not blocked.is_empty():failures.append("active crew stole a reserved helper")
	var disconnected:Dictionary=snapshot.duplicate(true)
	disconnected["navigation"]["unit_regions"][int(second["id"])]=2
	blocked=[]
	construction.resume_foundations(disconnected,1,policy,state,budget,{},blocked,disconnected["buildings"],disconnected["units"],disconnected["units"])
	if not blocked.is_empty():failures.append("active crew recruited a worker from a known disconnected component")
	if commands.size()==1:
		var before:=var_to_bytes(snapshot)
		var controller:=GameController.new(world)
		controller.enqueue_command(commands[0],true,1);controller.advance_frame(0.05,1,2)
		if not bool(controller.get_command_result(commands[0].sequence_id).get("accepted",false)) or world.get_buildings().size()!=1 or world.economy_system.get_resource_amount(1,1)!=paid_stock:failures.append("active helper did not join the already paid project")
		if int(first.get("target_building_id",-1))!=int(foundation["id"]) or int(second.get("target_building_id",-1))!=int(foundation["id"]):failures.append("active crew lost construction ownership")
		if var_to_bytes(snapshot)!=before:failures.append("active crew execution changed retained input")
	world.shutdown_derived_state()
