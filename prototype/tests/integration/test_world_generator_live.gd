extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Bootstrap := preload("res://scripts/match_bootstrap.gd")
const World := preload("res://scripts/simulation_world.gd")
const Geography := preload("res://scripts/random_map_watershed_world.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Commands := preload("res://scripts/commands.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Settings := preload("res://scripts/skirmish_settings.gd")
const DIRECTORY := "res://qa/world-generator-20261018"
var failures: Array[String] = []

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	var catalog = Catalog.new()
	catalog.load()
	var rows: Array = []
	var profiles: Array = Geography.PROFILES.duplicate()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--profiles="): profiles = argument.trim_prefix("--profiles=").split(",")
	for profile in profiles:
		var file := FileAccess.open(DIRECTORY.path_join(profile + "-large.bin"), FileAccess.READ)
		var built: Dictionary = {}
		if file != null and "--use-cache" in OS.get_cmdline_user_args():
			built = file.get_var()
		else:
			var settings := Settings.default_settings()
			settings["map_type_id"] = profile
			settings["map_size_id"] = "large"
			for player in settings["players"]: player["enabled"] = true
			built = Settings.build(settings)
		check(bool(built.get("valid", false)), "%s live fixture builds: %s" % [profile, built.get("errors", [])])
		if not built.get("valid", false): continue
		var data: Dictionary = built["map_data"]
		var world = World.new(data["size"])
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		var runtime_definition: Dictionary = built["definition"].duplicate(true)
		for player in runtime_definition["players"]:
			player["controller"] = "human"
			player["ai"]["enabled"] = false
		Bootstrap.apply(world, runtime_definition, data)
		for actor in world.get_units():
			check(world.query_units_near(actor["pos"], 0.0).any(func(candidate): return candidate["id"] == actor["id"]), "%s spatial index contains every actor at its settled starting position" % profile)
		var grid = world.navigation_grid
		for clearing in data.get("building_clearings", []):
			var cells: Array = []
			var origin: Vector2i = clearing["origin"]
			for y in range(origin.y, origin.y + clearing["width"]):
				for x in range(origin.x, origin.x + clearing["width"]): cells.append(Vector2i(x, y))
			check(grid.can_build_for(cells, "land"), "%s protected expansion clearing admits a real foundation" % profile)
		var expected := Navigation.mask(data, built["definition"])
		for i in range(expected.size()):
			check((expected[i] != 0) == grid.is_walkable(Vector2i(i % grid.size.x, i / grid.size.x)), "%s generator and real land occupancy agree" % profile)
		var paths := 0
		for player in built["definition"]["players"]:
			var team := int(player["team"])
			var workers: Array = world.get_units().filter(func(unit): return unit.get("team", 0) == team and unit.get("kind", "") == "villager")
			check(not workers.is_empty(), "%s starting workers bootstrap" % profile)
			if workers.is_empty(): continue
			for starting_worker in workers:
				check(grid.is_position_walkable_for(starting_worker["pos"], starting_worker["footprint_radius"], "land", starting_worker["terrain_restriction"]), "%s player %d starts each worker on a valid footprint" % [profile, team])
			var worker: Dictionary = workers[0]
			for kind in ["tree", "berries"]:
				var reachable := false
				var resources: Array = world.get_resources().filter(func(resource): return resource.get("kind", "") == kind and Vector2(resource["pos"]).distance_to(player["start"]) <= 20.0)
				resources.sort_custom(func(a, b): return Vector2(a["pos"]).distance_squared_to(worker["pos"]) < Vector2(b["pos"]).distance_squared_to(worker["pos"]))
				for resource in resources:
					for approach in world.resource_approach_candidates(worker, resource):
						if not grid.is_position_walkable_for(approach, float(worker.get("footprint_radius", 0.3)), "land", int(worker.get("terrain_restriction", -1))): continue
						var path: Array = world.pathfinder.find_path(worker["pos"], approach, "land", int(worker.get("terrain_restriction", -1)), float(worker.get("footprint_radius", 0.3)))
						if not path.is_empty(): reachable = true; break
					if reachable: break
				check(reachable, "%s player %d can reach starting %s through real pathfinding" % [profile, team, kind])
				paths += int(reachable)
		var masks: Dictionary = {}
		for restriction in [3, 6, 7]: masks[restriction] = grid.native_walkability_mask("land" if restriction == 7 else "water", restriction)
		for ford in data["fords"]:
			for cell in ford["cells"]:
				for restriction in [3, 6, 7]: check(masks[restriction][cell.y * grid.size.x + cell.x] != 0, "%s ford admits infantry and both ship restrictions" % profile)
			check(grid.is_segment_walkable_for(ford["bank_a"], ford["bank_b"], 0.3, "land", 7), "%s ford joins its banks with real infantry clearance" % profile)
		var crossings: Array = []
		if not data["fords"].is_empty():
			# Resource access above uses the complete eight-player bootstrap. For
			# crossing orders, isolate actors without changing terrain or obstacles:
			# wildlife/combat and existing destination slots are unrelated to a ford.
			for actor in world.get_units().duplicate():
				world.release_unit_destination(actor)
				world.detach_unit_for_transport(int(actor["id"]))
			var controller = Controller.new(world)
			var ford: Dictionary = data["fords"][0]
			var center := Vector2(ford["center"]) + Vector2.ONE * 0.5
			var cross_axis: Vector2 = (ford["bank_b"] - ford["bank_a"]).normalized()
			var tangent := Vector2(-cross_axis.y, cross_axis.x)
			for kind in ["clubman", "fishing_boat"]:
				var start: Vector2 = ford["bank_a"] if kind == "clubman" else center - tangent
				var goal: Vector2 = ford["bank_b"] if kind == "clubman" else center + tangent
				var unit: Dictionary = world.add_unit(1, kind, start, false)
				if kind=="fishing_boat":
					var route:Array=world.pathfinder.find_path(start,goal,"water",unit["terrain_restriction"],unit["footprint_radius"])
					if unit["pos"].distance_to(start)>0.1 or route.is_empty() or Vector2(route[-1]).distance_to(goal)>0.2:
						crossings.append({"kind":kind,"reason":"natural_river_too_narrow"})
						world.detach_unit_for_transport(int(unit["id"]))
						continue
				var spawned_at: Vector2 = unit["pos"]
				var command = Commands.MoveCommand.new(controller.tick_index+1, [int(unit["id"])], goal)
				controller.enqueue_command(command, true, 1)
				controller.advance_frame(0.05, 1, 2)
				check(controller.get_command_result(command.sequence_id).get("accepted", false), "%s accepts %s ford movement" % [profile, kind])
				check(unit.get("reserved_destination") == goal, "%s reserves the requested %s ford endpoint" % [profile, kind])
				for tick in range(700):
					controller.advance_frame(0.05, 1, 2)
					if unit["pos"].distance_to(goal) < 0.45: break
				var arrived: bool = unit["pos"].distance_to(goal) < 0.45
				check(arrived, "%s %s actually crosses its ford" % [profile, kind])
				crossings.append({"kind": kind, "arrived": arrived, "requested_start": str(start), "goal": str(goal), "position": str(unit["pos"]),
					"goal_valid": grid.is_position_walkable_for(goal, float(unit["footprint_radius"]), unit["movement_domain"], int(unit.get("terrain_restriction", -1))),
					"radius": unit["footprint_radius"], "path_status": unit.get("path_status", ""), "task": unit.get("task", "")})
				crossings[-1].merge({"spawned_at": str(spawned_at), "reserved_goal": str(unit.get("reserved_destination", Vector2.ZERO)), "hp": unit.get("hp", 0)})
				world.release_unit_destination(unit)
				world.detach_unit_for_transport(int(unit["id"]))
		world.task_coordinator.shutdown()
		rows.append({"profile": profile, "players": built["definition"]["players"].size(), "resource_paths": paths, "fords": data["fords"].size(), "crossings": crossings})
		print(JSON.stringify(rows[-1]))
	FileAccess.open(DIRECTORY.path_join("live.json" if profiles.size() == Geography.PROFILES.size() else "live-subset.json"), FileAccess.WRITE).store_string(JSON.stringify({"valid": failures.is_empty(), "rows": rows, "failures": failures}, "\t"))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(value: bool, context: String) -> void:
	if not value and context not in failures: failures.append(context)
