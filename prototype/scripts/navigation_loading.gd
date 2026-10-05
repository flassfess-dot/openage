class_name RoRNavigationLoading
extends RefCounted

const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const NavigationData := preload("res://scripts/navigation_task_data.gd")
const Preparation := preload("res://scripts/navigation_preparation_task.gd")
var coordinator := Coordinator.new()
var records: Array = []
var complete := true
var match_players: Array = []

func is_loading() -> bool:
	return not complete

func begin(world, players: Array = []) -> void:
	shutdown()
	match_players = players.duplicate(true)
	var owners: Array = [{"planner": world.pathfinder, "units": world.get_units()}]
	for player in match_players:
		var team := int(player.get("team", 0))
		if team > 0:
			owners.append({"planner": world.movement_system.knowledge.planner(world, team), "units": world.get_units().filter(func(unit): return int(unit.get("team", 0)) == team)})
	if not coordinator.is_enabled("navigation_prepare"):
		for owner in owners:
			owner["planner"].prepare_native_kernels_for_units(owner["units"])
		return
	for owner in owners:
		var planner = owner["planner"]
		var topology: Dictionary = planner.detached_task_topology()
		var configurations: Dictionary = {"land:-1": {"domain": "land", "restriction": -1, "radii": [0.0]}, "water:-1": {"domain": "water", "restriction": -1, "radii": [0.0]}}
		for unit in owner["units"]:
			var domain := String(unit.get("movement_domain", "land"))
			var restriction := int(unit.get("terrain_restriction", -1))
			var key := "%s:%d" % [domain, restriction]
			if not configurations.has(key):
				configurations[key] = {"domain": domain, "restriction": restriction, "radii": [0.0]}
			var radius := float(unit.get("footprint_radius", 0.3))
			radius = 0.0 if radius < 0.5 else radius
			if radius not in configurations[key]["radii"] and configurations[key]["radii"].size() < 16:
				configurations[key]["radii"].append(radius)
		var keys: Array = configurations.keys()
		keys.sort()
		for key in keys:
			var input: Dictionary = configurations[key].duplicate()
			input["grid"] = topology
			records.append({"planner": planner, "input": input, "request": -2, "output": {}})
	complete = records.is_empty()

func poll(world) -> bool:
	if complete:
		return true
	var running := coordinator.pending.size()
	for record in records:
		if int(record["request"]) == -2 and running < 4:
			var grid = record["planner"].grid
			record["request"] = coordinator.submit("navigation_prepare", record["input"], Preparation.run, -1, -1, {"topology": grid.revision, "surface": grid.surface_revision}, true)
			if int(record["request"]) < 0:
				record["output"] = Preparation.run(record["input"])
			else:
				running += 1
	var all_ready := true
	for record in records:
		var request_id := int(record["request"])
		if request_id >= 0:
			if coordinator.is_ready(request_id):
				var result := coordinator.collect(request_id)
				record["output"] = result.get("data", {})
				record["request"] = -1
				if record["output"].is_empty():
					record["output"] = Preparation.run(record["input"])
			else:
				all_ready = false
		elif request_id == -2:
			all_ready = false
	if not all_ready:
		return false
	for record in records:
		var grid = record["planner"].grid
		var output: Dictionary = record["output"]
		if int(output["revision"]) != grid.revision or int(output["surface_revision"]) != grid.surface_revision:
			begin(world, match_players)
			return false
	for record in records:
		var planner = record["planner"]
		var output: Dictionary = record["output"]
		planner.grid.surface_component_cache[output["key"]] = output["components"]
		if planner.uses_native_kernel():
			var kernel = ClassDB.instantiate("RoRPathKernel")
			kernel.configure(planner.grid.size.x, planner.grid.size.y, planner.grid.revision, output["mask"])
			for component in output.get("native_components", []):
				kernel.install_connectivity(component["labels"], float(component["radius"]))
			planner.native_kernels[output["key"]] = kernel
	records.clear()
	complete = true
	return true

func shutdown() -> void:
	coordinator.shutdown()
	records.clear()
	complete = true
