extends "res://tests/integration/test_cooperative_worker_orders.gd"
func _initialize() -> void:
	var catalog=ResourceCatalog.new(); catalog.load()
	verify_trace(catalog,"gold_mine")
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func verify_trace(catalog,kind: String) -> void:
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
	for worker in workers:
		var cursor:=Vector2(worker["pos"]); var length:=0.0
		var exact: Array[Vector2]=world.pathfinder.find_path(cursor,Vector2(workers[0]["pos"]),"land",int(worker["terrain_restriction"]),float(worker["footprint_radius"]))
		var exact_length:=0.0
		for point in exact: exact_length+=cursor.distance_to(point); cursor=point
		print("EXACT_TO_BASE ",worker["id"]," length=",exact_length," radius=",worker["footprint_radius"])
		cursor=Vector2(worker["pos"])
		for point in worker["path"]: length+=cursor.distance_to(Vector2(point)); cursor=point
		print("INITIAL_ROUTE ",worker["id"]," length=",length," minimum_seconds=",length/float(worker["speed"])," start=",worker["pos"]," slot=",worker["resource_approach_slot"]," path=",worker["path"])
