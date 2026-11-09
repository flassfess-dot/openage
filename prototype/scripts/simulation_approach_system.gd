class_name RoRSimulationApproachSystem
extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")

var world_ref: WeakRef
var native_slot_checks_enabled := true
var slot_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func assign_reachable_slot(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Variant:
	var probe: Variant = world.tick_pipeline.performance_probe
	var portion_started := Time.get_ticks_usec() if probe != null else 0
	var available:=available_slots(worker,candidates,reservations,respect_footprints)
	if probe != null: probe.observe_microseconds("simulation.approach.available", Time.get_ticks_usec() - portion_started)
	if respect_footprints and String(worker.get("task",""))=="gather":
		# Euclidean-nearest can lie behind the mineral/forest cluster, requiring
		# a map-sized detour. Minimize actual route length among bounded slots.
		var origin:=Vector2(worker["pos"])
		var planner=world.movement_system.knowledge.planner(world,int(worker["team"]))
		var best: Variant=null; var best_cost:=INF
		if probe != null: portion_started = Time.get_ticks_usec()
		for candidate in available.slice(0,32):
			if origin.distance_to(candidate)>=best_cost: break
			var route: Array[Vector2]=planner.find_path(origin,candidate,String(worker["movement_domain"]),int(worker["terrain_restriction"]),float(worker["footprint_radius"]))
			if route.is_empty() or route.back().distance_squared_to(candidate)>0.0144: continue
			var cursor:=origin; var cost:=0.0
			for point in route: cost+=cursor.distance_to(point); cursor=point
			if cost<best_cost: best=candidate; best_cost=cost
		if probe != null: probe.observe_microseconds("simulation.approach.routes", Time.get_ticks_usec() - portion_started)
		if best is Vector2 and resume(worker,best): return best
		return null
	for candidate in available:
		if resume(worker, candidate):
			return candidate
	return null


func available_slots(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Array[Vector2]:
	var simulation_world = world
	var result: Array[Vector2] = []
	var radius := float(worker.get("footprint_radius", 0.3))
	var domain := String(worker.get("movement_domain", "land"))
	var restriction := int(worker.get("terrain_restriction", -1))
	var resource_occupancy := _native_occupied_slots(worker, candidates, simulation_world) if respect_footprints else PackedByteArray()
	var idle_occupancy := _native_idle_occupied_slots(worker, candidates, simulation_world) if respect_footprints else PackedByteArray()
	var walkability: PackedByteArray = simulation_world.pathfinder.position_walkability(candidates, radius, domain, restriction)
	for candidate_index in range(candidates.size()):
		var candidate := candidates[candidate_index]
		if walkability[candidate_index] == 0:
			continue
		var too_close := false
		for other_id in reservations:
			var separation := 0.3
			if respect_footprints:
				var other: Variant = simulation_world.units_by_id.get(int(other_id))
				separation = Footprint.separation_distance(worker, other) if other != null else radius * 2.0 + Footprint.DEFAULT_CLEARANCE
			if Vector2(reservations[other_id]).distance_squared_to(candidate) < separation * separation:
				too_close = true
				break
		if not too_close and respect_footprints:
			too_close = resource_occupancy[candidate_index] != 0 if resource_occupancy.size() == candidates.size() else _resource_slot_occupied(worker, candidate, simulation_world)
		if not too_close and respect_footprints:
			# Finished workers release reservations but remain solid at the depot.
			# Do not keep assigning their occupied position to the next carrier.
			if idle_occupancy.size() == candidates.size():
				too_close = idle_occupancy[candidate_index] != 0
			else:
				for other in simulation_world.query_units_near(candidate, radius + 2.0):
					if int(other["id"]) == int(worker["id"]) or float(other.get("hp", 0.0)) <= 0.0 or String(other.get("movement_domain", "land")) != domain or String(other.get("task", "idle")) not in ["idle", "hold"]: continue
					var separation := Footprint.separation_distance(worker, other)
					if Vector2(other["pos"]).distance_squared_to(candidate) < separation * separation:
						too_close = true
						break
		if not too_close:
			result.append(candidate)
	var origin := Vector2(worker.get("pos", Vector2.ZERO))
	result.sort_custom(func(left: Vector2, right: Vector2):
		var left_distance := origin.distance_squared_to(left)
		var right_distance := origin.distance_squared_to(right)
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		if not is_equal_approx(left.y, right.y):
			return left.y < right.y
		return left.x < right.x
	)
	return result


func resume(worker: Dictionary, slot: Vector2) -> bool:
	if Vector2(worker.get("pos", Vector2.ZERO)).distance_squared_to(slot) <= 0.0144:
		world.set_entity_field(worker, "destination", slot)
		world.set_entity_field(worker, "target", slot)
		world.set_entity_field(worker, "path", [])
		world.set_entity_field(worker, "path_index", 0)
		return true
	if Vector2(worker.get("destination", worker.get("pos", Vector2.ZERO))).distance_squared_to(slot) <= 0.0001 and not worker.get("path", []).is_empty():
		return true
	var simulation_world = world
	# The grid may resolve an inaccessible subcell goal to a neighbouring cell.
	# Such a route cannot service this exact work slot and must not be reserved.
	var domain := String(worker.get("movement_domain", "land"))
	var restriction := int(worker.get("terrain_restriction", -1))
	var radius := float(worker.get("footprint_radius", 0.3))
	var planner = simulation_world.movement_system.knowledge.planner(simulation_world, int(worker.get("team", 0)))
	var route: Array[Vector2] = planner.find_path(Vector2(worker["pos"]), slot, domain, restriction, radius)
	if route.is_empty() or route.back().distance_squared_to(slot) > 0.0144:
		return false
	var purpose := "replan" if not worker.get("path", []).is_empty() else String(worker.get("task", "move"))
	var prepared: Dictionary = simulation_world.navigation_service.register_resolved_path(int(worker["id"]), worker["pos"], slot, route, domain, restriction, purpose, radius)
	if not simulation_world.movement_system.assign_unit_destination(worker, slot, false, false, prepared):
		return false
	return not worker["path"].is_empty() and Vector2(worker["path"].back()).distance_squared_to(slot) <= 0.0144


func resource_slot_occupied(worker: Dictionary, candidate: Vector2, minimum_clearance: float = -1.0) -> bool:
	# Resource types keep separate reservation tables. Inspect adjacent cells as
	# well so neighbouring trees or bushes cannot reserve overlapping positions.
	return _resource_slot_occupied(worker, candidate, world,minimum_clearance)


func _resource_slot_occupied(worker: Dictionary, candidate: Vector2, simulation_world, minimum_clearance: float = -1.0) -> bool:
	if native_slot_checks_enabled and slot_kernel != null and slot_kernel.has_method("occupied_resource_slots"):
		var points: Array[Vector2] = [candidate]
		var native := _native_occupied_slots(worker, points, simulation_world, minimum_clearance)
		if native.size() == 1: return native[0] != 0
	var map_width: int = simulation_world.map_size.x
	var map_height: int = simulation_world.map_size.y
	var resources_by_cell: Dictionary = simulation_world.resource_nodes_by_cell
	var reservations_by_resource: Dictionary = simulation_world.resource_approach_slots
	var units_by_id: Dictionary = simulation_world.units_by_id
	var cell := Vector2i(candidate)
	for y in range(maxi(0, cell.y - 3), mini(map_height - 1, cell.y + 3) + 1):
		for x in range(maxi(0, cell.x - 3), mini(map_width - 1, cell.x + 3) + 1):
			for resource_value in resources_by_cell.get(y * map_width + x, []):
				var resource: Dictionary = resource_value
				var slots: Dictionary = reservations_by_resource.get(int(resource["id"]), {})
				for other_id in slots:
					if int(other_id) == int(worker["id"]):
						continue
					var other: Variant = units_by_id.get(int(other_id))
					var separation := Footprint.separation_distance(worker, other) if other != null else float(worker.get("footprint_radius", 0.3)) * 2.0 + Footprint.DEFAULT_CLEARANCE
					if minimum_clearance>=0.0: separation=float(worker.get("footprint_radius",0.3))+float(other.get("footprint_radius",0.3) if other!=null else worker.get("footprint_radius",0.3))+minimum_clearance
					if Vector2(slots[other_id]).distance_squared_to(candidate) < separation * separation:
						return true
	return false


func _native_occupied_slots(worker: Dictionary, candidates: Array[Vector2], simulation_world, minimum_clearance: float = -1.0) -> PackedByteArray:
	if native_slot_checks_enabled and slot_kernel != null and slot_kernel.has_method("occupied_resource_slots"):
		return slot_kernel.occupied_resource_slots(worker, candidates, simulation_world.map_size, simulation_world.resource_nodes_by_cell, simulation_world.resource_approach_slots, simulation_world.units_by_id, minimum_clearance, Footprint.DEFAULT_CLEARANCE)
	return PackedByteArray()


func _native_idle_occupied_slots(worker: Dictionary, candidates: Array[Vector2], simulation_world) -> PackedByteArray:
	if not native_slot_checks_enabled or slot_kernel == null or not slot_kernel.has_method("occupied_idle_unit_slots") or candidates.is_empty() or candidates.size() > 128: return PackedByteArray()
	var center := candidates[0]
	var extent := 0.0
	for point in candidates: extent = maxf(extent, center.distance_to(point))
	if extent > 32.0: return PackedByteArray()
	# Keep the broad phase conservative across Vector2 rounding. Native still
	# applies each candidate's original exact query radius and body clearance.
	var nearby: Array = simulation_world.query_units_near(center, extent + float(worker.get("footprint_radius", 0.3)) + 2.001)
	var spatial = simulation_world.spatial_index
	return slot_kernel.occupied_idle_unit_slots(worker, candidates, nearby, spatial.unit_index_by_id, spatial.unit_positions, spatial.unit_radii, Footprint.DEFAULT_CLEARANCE)
