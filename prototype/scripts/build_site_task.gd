class_name RoRBuildSiteTask
extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")
const NavigationData := preload("res://scripts/navigation_task_data.gd")
const Pathfinder := preload("res://scripts/pathfinder.gd")
const StaticAuditCache := preload("res://scripts/build_site_static_cache.gd")
const Placement := preload("res://scripts/simulation_building_placement_system.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const Coordinates := preload("res://scripts/coordinates.gd")
const GateSystem := preload("res://scripts/gate_system.gd")
const WallPlacement := preload("res://scripts/wall_placement.gd")
static var native_structure_audits_enabled := true
const MAX_ACTOR_BYTES := 8 * 1024 * 1024
const MAX_PROFILE_BYTES := 2 * 1024 * 1024
const MAX_PROFILES := 256

class Repository extends RefCounted:
	var profiles: Dictionary = {}
	var configured := false
	func is_configured() -> bool:
		return configured
	func has_archetype(kind: String) -> bool:
		return bool(profiles[kind]["exists"])
	func category(kind: String) -> String:
		return String(profiles[kind]["category"])
	func runtime_metadata(kind: String) -> Dictionary:
		return profiles[kind]["metadata"]

class Technology extends RefCounted:
	var researched: Dictionary = {}
	func is_researched(_team: int, technology_id: int) -> bool:
		return bool(researched.get(technology_id, false))

class Visibility extends RefCounted:
	var size := Vector2i.ONE
	var states := PackedByteArray()
	func state_at_world(_team: int, position: Vector2) -> int:
		var cell := Vector2i(floori(position.x), floori(position.y))
		if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y:
			return FogOfWar.UNKNOWN
		return int(states[cell.y * size.x + cell.x])

class ProbeOwner extends RefCounted:
	var performance_probe: Variant = null

class Executor extends RefCounted:
	var planner
	func run(input: Dictionary) -> Dictionary:
		return RoRBuildSiteTask.run(input, planner)

var navigation_grid
var pathfinder
var data_repository := Repository.new()
var technology_system := Technology.new()
var visibility_system := Visibility.new()
var tick_pipeline := ProbeOwner.new()
var building_placement_system
var units: Array = []
var buildings: Array = []
var mobile_cells: Dictionary = {}
var map_size := Vector2i.ONE
var last_build_failure := ""
var initial_seen: Dictionary = {}
var scan_ids: Dictionary = {}
var separate_fallbacks := false
var gap_fallbacks: Dictionary = {}

static func capture(world, team: int, kinds: Array) -> Dictionary:
	var cache := _capture_cache(world, team)
	var profiles: Dictionary = {}
	var researched: Dictionary = {}
	for kind_value in kinds:
		var kind := String(kind_value)
		var template := _profile_template(world, cache, kind)
		if template.is_empty(): return {}
		var metadata: Dictionary = template["metadata"]
		var technology_id := int(metadata.get("required_technology_id", -1))
		if technology_id >= 0:
			researched[technology_id] = world.technology_system.is_researched(team, technology_id)
		var profile := template.duplicate()
		profile["affordable"] = world.can_afford_resource_cost(team, world.building_cost(kind, team))
		profile.make_read_only()
		profiles[kind] = profile
	var workers: Array = []
	var mobile_cells: Dictionary[Vector2i, bool] = {}
	var seen_units: Dictionary = {}
	for unit in world.entity_read_index.legal_entities(world, team, "units"):
		if float(unit.get("hp", 0.0)) <= 0.0 or bool(unit.get("removed", false)): continue
		var position := Vector2(unit["pos"])
		var radius := float(unit.get("footprint_radius", 0.3))
		for point in [position, position + Vector2(radius, 0), position - Vector2(radius, 0), position + Vector2(0, radius), position - Vector2(0, radius)]: mobile_cells[Vector2i(point.floor())] = true
		if int(unit.get("team", 0)) != team or not world.entity_is_worker(unit) or String(unit.get("movement_domain", "land")) != "land": continue
		var id := int(unit["id"])
		seen_units[id] = true
		var version := int(world.entity_changes.revision_for(id, 1 | 2 | 8 | 128))
		var previous: Dictionary = cache["units"].get(id, {})
		if int(previous.get("version", -1)) != version:
			var row := {"id": id, "team": team, "hp": unit["hp"], "pos": position, "movement_domain": "land", "terrain_restriction": unit.get("terrain_restriction", -1), "footprint_radius": radius}
			if not Data.freeze_detached(row, 0, false): return {}
			previous = {"version": version, "row": row}
			_retain_actor(cache, "units", id, previous)
		workers.append(previous["row"])
	for id in cache["units"].keys():
		if not seen_units.has(id): _erase_actor(cache, id)
	var structures: Array = []
	var seen_buildings: Dictionary = {}
	for building in world.entity_read_index.legal_entities(world, team, "buildings"):
		var id := int(building["id"])
		seen_buildings[id] = true
		var version := int(world.entity_changes.revision_for(id, 1 | 2 | 8 | 16 | 32 | 128))
		var previous: Dictionary = cache["buildings"].get(id, {})
		if int(previous.get("version", -1)) != version:
			var row := {"id": id, "team": building.get("team", 0), "hp": building.get("hp", 0.0), "pos": building["pos"], "footprint": Data.copy(building.get("footprint", {})), "occupied_cells": Data.copy(building.get("occupied_cells", [])), "footprint_radius": building.get("footprint_radius", 1.0)}
			if not Data.freeze_detached(row, 0, false): return {}
			previous = {"version": version, "row": row}
			_retain_actor(cache, "buildings", id, previous)
		structures.append(previous["row"])
	for id in cache["buildings"].keys():
		if not seen_buildings.has(id): _erase_actor(cache, id)
	# Every actor row was validated/frozen by this producer, and each profile
	# contains only a validated template plus the current affordability boolean.
	# Certify these owned roots instead of revisiting all children in the caller.
	for publication in [workers, structures, profiles]:
		publication.make_read_only()
		Data._retain_immutable(publication)
	var planner = world.movement_system.knowledge.planner(world, team)
	return {"navigation": capture_build_topology(world, cache, planner), "native_enabled": planner.native_enabled, "profiles": profiles, "configured": world.data_repository.is_configured(), "researched": researched, "workers": workers, "buildings": structures, "mobile_cells": mobile_cells, "fog": world.get_fog_of_war().states_by_player[team].duplicate()}


static func calculate_queries(base: Dictionary, queries: Array, coordinator, tick: int, source_planner = null, probe = null) -> Array:
	var prepare_started := Time.get_ticks_usec() if probe != null else 0
	var inputs: Array = []
	var owners: Array[int] = []
	for query_index in range(queries.size()):
		var query: Dictionary = queries[query_index]
		var workers: Array = base["workers"].duplicate()
		workers.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
		var width := mini(4, maxi(1, OS.get_processor_count() - 2))
		var chunk_size := maxi(1, ceili(float(workers.size()) / float(width)))
		var previous_cells: Dictionary = {}
		var split: bool = workers.size() > 1 and String(query["kind"]) not in query["strict"]
		if not split:
			inputs.append(query)
			owners.append(query_index)
			continue
		for first in range(0, workers.size(), chunk_size):
			var input: Dictionary = query.duplicate()
			var scan_ids: Dictionary = {}
			for index in range(first, mini(first + chunk_size, workers.size())):
				scan_ids[int(workers[index]["id"])] = true
			input["scan_ids"] = scan_ids
			input["initial_seen"] = previous_cells.duplicate()
			input["separate_fallbacks"] = true
			inputs.append(input)
			owners.append(query_index)
			# An earlier worker visits every ring cell unless it already supplied
			# the full result, in which case later groups will not be consumed.
			for preferred in query["preferred"].get(query["kind"], []):
				previous_cells[Vector2i(Vector2(preferred).floor())] = true
			for index in range(first, mini(first + chunk_size, workers.size())):
				var center := Vector2i(Vector2(workers[index]["pos"]).floor())
				var radius := maxi(1, int(query["radius"]))
				for y in range(center.y - radius, center.y + radius + 1):
					for x in range(center.x - radius, center.x + radius + 1):
						var cell := Vector2i(x, y)
						if cell != center:
							previous_cells[cell] = true
	if probe != null:
		probe.observe_microseconds("presentation.ai.build_sites.prepare", Time.get_ticks_usec() - prepare_started)
	var outputs: Array = []
	var width := mini(4, maxi(1, OS.get_processor_count() - 2))
	var routes_started := Time.get_ticks_usec() if probe != null else 0
	var route_snapshot: Dictionary = source_planner.detached_route_caches() if source_planner != null else {}
	if probe != null:
		probe.observe_microseconds("presentation.ai.build_sites.routes", Time.get_ticks_usec() - routes_started)
	var configurations: Dictionary = {}
	for worker in base["workers"]:
		configurations["land:%d" % int(worker["terrain_restriction"])] = ["land", int(worker["terrain_restriction"])]
	if source_planner != null:
		var bytes_per_worker: int = int(base["navigation"]["size"].x) * int(base["navigation"]["size"].y) * 16 * maxi(1, configurations.size())
		width = mini(width, maxi(1, int(67108864 / maxi(1, bytes_per_worker))))
	for first in range(0, inputs.size(), width):
		var jobs: Array = []
		var requests: Array[int] = []
		var end := mini(first + width, inputs.size())
		for index in range(first, end):
			var context_started := Time.get_ticks_usec() if probe != null else 0
			var job := Executor.new()
			if source_planner != null:
				job.planner = source_planner.create_task_context(base["navigation"], configurations.values(), route_snapshot)
			if probe != null:
				probe.observe_microseconds("presentation.ai.build_sites.context", Time.get_ticks_usec() - context_started)
			jobs.append(job)
			var submit_started := Time.get_ticks_usec() if probe != null else 0
			requests.append(coordinator.submit("ai_observation", inputs[index], job.run, tick, tick, {}, true))
			if probe != null:
				probe.observe_microseconds("presentation.ai.build_sites.submit", Time.get_ticks_usec() - submit_started)
		for index in range(first, end):
			var wait_started := Time.get_ticks_usec() if probe != null else 0
			var collected: Dictionary = coordinator.collect(requests[index - first], true) if requests[index - first] >= 0 else {}
			outputs.append(jobs[index - first].run(inputs[index]) if collected.is_empty() else collected["data"])
			if probe != null:
				probe.observe_microseconds("presentation.ai.build_sites.wait", Time.get_ticks_usec() - wait_started)
	var result: Array = []
	for query in queries:
		result.append({"sites": {}, "fallbacks": [], "static_cache": {}, "static_profiles": {}})
	for index in range(outputs.size()):
		var owner := owners[index]
		var query: Dictionary = queries[owner]
		var merged: Dictionary = result[owner]
		var output: Dictionary = outputs[index]
		var kind := String(query["kind"])
		var sites: Array = merged["sites"].get(kind, [])
		for site in output.get("sites", {}).get(kind, []):
			if sites.size() >= int(query["maximum"]):
				break
			sites.append(site)
		if not sites.is_empty():
			merged["sites"][kind] = sites
		merged["fallbacks"].append_array(output.get("fallbacks", {}).get(kind, []))
		merged["static_cache"].merge(output.get("static_cache", {}), true)
		if merged["static_cache"].size() > 8192:
			merged["static_cache"].clear()
		merged["static_profiles"].merge(output.get("static_profiles", {}), true)
	for index in range(queries.size()):
		var query: Dictionary = queries[index]
		var merged: Dictionary = result[index]
		var kind := String(query["kind"])
		var sites: Array = merged["sites"].get(kind, [])
		for site in merged["fallbacks"]:
			if sites.size() >= int(query["maximum"]):
				break
			if site not in sites:
				sites.append(site)
		if not sites.is_empty():
			merged["sites"][kind] = sites
		merged.erase("fallbacks")
	return result

static func run(input: Dictionary, private_planner = null, static_audits = null) -> Dictionary:
	var task := RoRBuildSiteTask.new()
	var base: Dictionary = input["base"]
	task.navigation_grid = private_planner.grid if private_planner != null else NavigationData.create_grid(base["navigation"])
	task.pathfinder = private_planner if private_planner != null else Pathfinder.new(task.navigation_grid)
	task.pathfinder.native_enabled = bool(base["native_enabled"])
	task.map_size = task.navigation_grid.size
	task.data_repository.profiles = base["profiles"]
	task.data_repository.configured = bool(base["configured"])
	task.technology_system.researched = base["researched"]
	task.visibility_system.size = task.map_size
	task.visibility_system.states = base["fog"]
	task.units = base["workers"].duplicate()
	task.buildings = base["buildings"]
	task.mobile_cells = base["mobile_cells"]
	task.building_placement_system = Placement.new(task)
	task.tick_pipeline.performance_probe = task.pathfinder.performance_probe
	task.building_placement_system.page_cache = static_audits
	if native_structure_audits_enabled and static_audits != null and static_audits.native_kernel != null and static_audits.native_kernel.has_method("foundation_intersects_structures"):
		task.building_placement_system.structure_audit_kernel = static_audits.native_kernel
		var structures := {"centers":PackedVector2Array(),"halves":PackedVector2Array(),"cells":[],"ids":[]}
		for building in task.buildings:
			if float(building.get("hp",0.0)) <= 0.0: continue
			structures.centers.append(WallPlacement.masonry_center(building))
			structures.halves.append(Vector2(building.get("footprint",{}).get("obstruction_half_size",building.get("footprint",{}).get("half_size",Vector2(0.5,0.5)))))
			structures.cells.append(building.get("occupied_cells",[]))
			structures.ids.append(int(building.get("id",-1)))
		task.building_placement_system.structure_audit = structures
	task.initial_seen = input.get("initial_seen", {})
	task.scan_ids = input.get("scan_ids", {})
	task.separate_fallbacks = bool(input.get("separate_fallbacks", false))
	var kind := String(input["kind"])
	task.building_placement_system.site_map_source = task.navigation_grid
	task.building_placement_system.site_map_revision = task.navigation_grid.revision
	task.building_placement_system.site_map_cache = {kind: Data.copy(input.get("static_cache", {}))}
	task.building_placement_system.site_footprint_profiles = Data.copy(input.get("static_profiles", {}))
	var sites := task.search(int(input["team"]), [kind], int(input["maximum"]), int(input["radius"]), input["preferred"], input["strict"], float(input["gap"]))
	return {"sites": sites, "fallbacks": task.gap_fallbacks, "static_cache": task.building_placement_system.site_map_cache.get(kind, {}), "static_profiles": task.building_placement_system.site_footprint_profiles}

func building_placement_stats(kind: String, axis: int = 0) -> Dictionary:
	return GateSystem.placement_stats(unit_stats(kind), axis) if kind == "gate" else unit_stats(kind)


func unit_stats(kind: String) -> Dictionary:
	return data_repository.profiles[kind]["stats"]

func get_buildings() -> Array:
	return buildings

func get_units() -> Array:
	return units

func entity_is_worker(_unit: Dictionary) -> bool:
	return true

func building_cost(kind: String, _team: int) -> Dictionary:
	return {"affordable": data_repository.profiles[kind]["affordable"]}

func can_afford_resource_cost(_team: int, cost: Dictionary) -> bool:
	return bool(cost["affordable"])

func _mobile_foundation_obstructions() -> Dictionary:
	return mobile_cells

func _can_place_foundation(team: int, kind: String, position: Vector2, occupied: Dictionary) -> bool:
	var started := Time.get_ticks_usec() if tick_pipeline.performance_probe != null else 0
	var result: bool = building_placement_system.can_place_foundation(team, kind, position, occupied)
	if tick_pipeline.performance_probe != null: tick_pipeline.performance_probe.observe_microseconds("placement.dynamic",Time.get_ticks_usec()-started)
	return result

func worker_can_reach_foundation(worker: Dictionary, kind: String, position: Vector2) -> bool:
	var started := Time.get_ticks_usec() if tick_pipeline.performance_probe != null else 0
	var result: bool = building_placement_system.worker_can_reach_foundation(worker, kind, position)
	if tick_pipeline.performance_probe != null: tick_pipeline.performance_probe.observe_microseconds("placement.reach",Time.get_ticks_usec()-started)
	return result

func foundation_preserves_structure_gap(team: int, kind: String, position: Vector2, gap: float) -> bool:
	return building_placement_system.foundation_preserves_structure_gap(team, kind, position, gap)

func search(team: int, kinds: Array, maximum_per_kind: int = 4, search_radius: int = 12, preferred_sites: Dictionary = {}, strict_preferred_kinds: Array = [], minimum_structure_gap: float = 0.0) -> Dictionary:
	var result: Dictionary = {}
	if kinds.is_empty():
		return result
	var workers: Array = units.filter(func(unit):
		return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0 and entity_is_worker(unit) and String(unit.get("movement_domain", "land")) == "land"
	)
	workers.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	if workers.is_empty():
		return result
	if tick_pipeline.performance_probe != null:
		tick_pipeline.performance_probe.increment("ai.build_site_searches")
	# One synchronous query sees fixed unit positions. Index the exact five
	# occupancy probes once, instead of scanning every unit for every site.
	var mobile_occupied_cells := _mobile_foundation_obstructions()
	var previous_failure := last_build_failure
	for kind_value in kinds:
		var kind := String(kind_value)
		var sites: Array = []
		var fallback_sites: Array = []
		var seen_cells: Dictionary = initial_seen.duplicate()
		for preferred_value in preferred_sites.get(kind, []):
			var preferred_position := Vector2(preferred_value)
			var preferred_cell := Vector2i(floori(preferred_position.x), floori(preferred_position.y))
			if seen_cells.has(preferred_cell) or not navigation_grid.contains(preferred_cell):
				continue
			seen_cells[preferred_cell] = true
			if visibility_system.state_at_world(team, preferred_position) == FogOfWar.UNKNOWN:
				continue
			if building_placement_system.cached_map_supports_foundation(kind, preferred_position) and _can_place_foundation(team, kind, preferred_position, mobile_occupied_cells) and workers.any(func(worker): return worker_can_reach_foundation(worker, kind, preferred_position)):
				if foundation_preserves_structure_gap(team, kind, preferred_position, minimum_structure_gap):
					sites.append(preferred_position)
					if sites.size() >= maximum_per_kind:
						break
				elif fallback_sites.size() < maximum_per_kind:
					fallback_sites.append(preferred_position)
		if kind in strict_preferred_kinds:
			_append_bounded_sites(sites, fallback_sites, maximum_per_kind)
			if not sites.is_empty():
				result[kind] = sites
			continue
		for worker_value in workers:
			if not scan_ids.is_empty() and not scan_ids.has(int(worker_value["id"])):
				continue
			var worker: Dictionary = worker_value
			var center := Vector2i(floori(float(worker.get("pos", Vector2.ZERO).x)), floori(float(worker.get("pos", Vector2.ZERO).y)))
			for cell_value in worker_ring_cells(kind,center,search_radius,seen_cells):
				var cell: Vector2i = cell_value
				var position := Vector2(cell) + Vector2(0.5, 0.5)
				if building_placement_system.cached_map_supports_foundation(kind, position) and _can_place_foundation(team, kind, position, mobile_occupied_cells) and worker_can_reach_foundation(worker, kind, position):
					if foundation_preserves_structure_gap(team, kind, position, minimum_structure_gap):
						sites.append(position)
						if sites.size() >= maximum_per_kind: break
					elif fallback_sites.size() < maximum_per_kind:
						fallback_sites.append(position)
			if sites.size() >= maximum_per_kind: break
		if separate_fallbacks:
			gap_fallbacks[kind] = fallback_sites
		else:
			_append_bounded_sites(sites, fallback_sites, maximum_per_kind)
		if not sites.is_empty():
			result[kind] = sites
	last_build_failure = previous_failure
	return result


func building_perimeter_candidates(worker: Dictionary, building: Dictionary) -> Array[Vector2]:
	var half_size: Vector2 = building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))
	# Keep all mobile-radius probes outside the whole navigation cell occupied by
	# the building. Half-cell clearance is required even when the visual polygon
	# itself ends earlier inside that cell.
	var padding := float(worker.get("footprint_radius", 0.3)) + 0.55
	var side_fractions := [-0.75, -0.25, 0.25, 0.75]
	var offsets: Array[Vector2] = []
	for fraction in side_fractions:
		offsets.append(Vector2(float(fraction) * half_size.x, -half_size.y - padding))
		offsets.append(Vector2(half_size.x + padding, float(fraction) * half_size.y))
		offsets.append(Vector2(float(fraction) * half_size.x, half_size.y + padding))
		offsets.append(Vector2(-half_size.x - padding, float(fraction) * half_size.y))
	var result: Array[Vector2] = []
	for offset in offsets:
		result.append(Coordinates.clamp_world(Vector2(building["pos"]) + offset, map_size))
	return result


func _append_bounded_sites(sites: Array, fallback_sites: Array, maximum: int) -> void:
	for fallback_position in fallback_sites:
		if sites.size() >= maximum:
			break
		sites.append(fallback_position)

static func _erase_actor(cache: Dictionary, id: Variant) -> void:
	var retained: Dictionary = cache["retained"]
	if retained.has(id):
		cache["bytes"] = int(cache["bytes"]) - int(retained[id]["bytes"])
		cache[retained[id]["category"]].erase(id)
		retained.erase(id)

static func _retain_actor(cache: Dictionary, category: String, id: int, record: Dictionary) -> void:
	_erase_actor(cache, id)
	var bytes := var_to_bytes(record).size() + 96
	if bytes > MAX_ACTOR_BYTES: return
	while not cache["retained"].is_empty() and (cache["retained"].size() >= 8192 or int(cache["bytes"]) + bytes > MAX_ACTOR_BYTES): _erase_actor(cache, cache["retained"].keys()[0])
	cache[category][id] = record
	cache["retained"][id] = {"category": category, "bytes": bytes}
	cache["bytes"] = int(cache["bytes"]) + bytes


static func capture_build_topology(world, cache: Dictionary, planner) -> Dictionary:
	var started := Time.get_ticks_usec() if world.tick_pipeline.performance_probe != null else 0
	if cache.get("topology_source") != planner.grid:
		cache["topology_source"] = planner.grid
		cache["topology_generation"] = int(cache.get("topology_generation", -1)) + 1
		cache.erase("topology")
	var topology := NavigationData.capture_chunked(planner.grid, cache.get("topology", {}), int(cache["topology_generation"]))
	cache["topology"] = topology
	# This producer retains a previously validated immutable publication. Refresh
	# its certificate before the caller freezes the small placement envelope.
	if not topology.is_empty(): Data._retain_immutable(topology)
	if world.tick_pipeline.performance_probe != null:
		world.tick_pipeline.performance_probe.observe_microseconds("navigation.task_topology.capture", Time.get_ticks_usec() - started)
	return topology

static func _capture_cache(world, team: int) -> Dictionary:
	var cache: Dictionary = world.ai_build_capture_cache.get(team, {})
	if int(cache.get("epoch", -1)) != int(world.entity_changes.epoch): cache = {"epoch": world.entity_changes.epoch, "units": {}, "buildings": {}, "retained": {}, "bytes": 0}
	if cache.get("profile_source") != world.data_repository or int(cache.get("profile_revision", -1)) != world.data_repository.revision:
		cache["profiles"] = {}
		cache["profile_sizes"] = {}
		cache["profile_bytes"] = 0
		cache["profile_source"] = world.data_repository
		cache["profile_revision"] = world.data_repository.revision
	if not world.ai_build_capture_cache.has(team) and world.ai_build_capture_cache.size() >= 8: world.ai_build_capture_cache.erase(world.ai_build_capture_cache.keys()[0])
	world.ai_build_capture_cache[team] = cache
	return cache

static func _profile_template(world, cache: Dictionary, kind: String) -> Dictionary:
	if cache["profiles"].has(kind): return cache["profiles"][kind]
	var template := Data.capture_frozen({"stats":world.unit_stats(kind), "metadata":world.data_repository.runtime_metadata(kind), "exists":world.data_repository.has_archetype(kind), "category":world.data_repository.category(kind)})
	if template.is_empty(): return {}
	var bytes := var_to_bytes(template).size() + kind.length() * 4
	if bytes > MAX_PROFILE_BYTES: return template
	while not cache["profiles"].is_empty() and (cache["profiles"].size() >= MAX_PROFILES or int(cache["profile_bytes"]) + bytes > MAX_PROFILE_BYTES):
		var expired = cache["profiles"].keys()[0]
		cache["profile_bytes"] -= cache["profile_sizes"][expired]
		cache["profile_sizes"].erase(expired)
		cache["profiles"].erase(expired)
	cache["profiles"][kind] = template
	cache["profile_sizes"][kind] = bytes
	cache["profile_bytes"] += bytes
	return template

static func prepare_topology(world, team: int) -> void:
	var cache := _capture_cache(world, team)
	capture_build_topology(world, cache, world.movement_system.knowledge.planner(world, team))
	for kind in world.data_repository.archetype_aliases("building"):
		_profile_template(world, cache, kind)

func worker_ring_cells(kind: String, center: Vector2i, radius: int, seen: Dictionary) -> Array:
	var cache: Variant = building_placement_system.page_cache
	if cache != null and cache.active and cache.native_kernel != null and cache.native_kernel.has_method("build_site_ring_cells"):
		if not building_placement_system.site_footprint_profiles.has(kind):
			building_placement_system.cached_map_supports_foundation(kind,Vector2(center)+Vector2(0.5,0.5))
		if not cache.profiles.has(kind): cache.prepare_kind(kind,building_placement_system.site_footprint_profiles[kind])
		return cache.ring_cells(kind,center,maxi(1,radius),map_size,seen)
	var result: Array = []
	for r in range(1,maxi(1,radius)+1):
		for y in range(center.y-r,center.y+r+1):
			var columns: Array = range(center.x-r,center.x+r+1) if absi(y-center.y) == r else [center.x-r,center.x+r]
			for x in columns:
				var cell := Vector2i(x,y)
				if seen.has(cell) or not navigation_grid.contains(cell): continue
				seen[cell] = true
				result.append(cell)
	return result
