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
		for builder_id in foundation.get("builders", {}).keys():
			contributing_workers[int(builder_id)] = true
		peak_builders = maxi(peak_builders, workers.filter(func(worker): return String(worker.get("task", "")) == "build" and Vector2(worker.get("pos", Vector2.ZERO)).distance_to(Vector2(foundation["pos"])) < 3.0).size())
		if foundation.get("state", "") == "complete":
			break
	if contributing_workers.size() < 2 or peak_builders < 2 or String(foundation.get("state", "")) != "complete":
		failures.append("house: %d/%d workers contributed, peak simultaneous=%d, state=%s progress=%.3f; %s" % [contributing_workers.size(), workers.size(), peak_builders, foundation.get("state", ""), float(foundation.get("construction_progress", 0.0)), worker_diagnostics(workers)])


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
		details.append("id%d task=%s cycles=%d pos=%s slot=%s path=%s reason=%s" % [int(worker.get("id", -1)), worker.get("task", ""), int(worker.get("gather_cycles", 0)), str(worker.get("pos", Vector2.ZERO)), str(worker.get("resource_approach_slot", worker.get("building_approach_slot", null))), worker.get("path_status", ""), worker.get("diagnostic_reason", "")])
	return "; ".join(details)
