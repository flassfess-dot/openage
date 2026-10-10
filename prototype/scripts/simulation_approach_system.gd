class_name RoRSimulationApproachSystem
extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func assign_reachable_slot(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Variant:
	for candidate in available_slots(worker, candidates, reservations, respect_footprints):
		if resume(worker, candidate):
			return candidate
	return null


func available_slots(worker: Dictionary, candidates: Array[Vector2], reservations: Dictionary, respect_footprints: bool = false) -> Array[Vector2]:
	var simulation_world = world
	var result: Array[Vector2] = []
	var radius := float(worker.get("footprint_radius", 0.3))
	var domain := String(worker.get("movement_domain", "land"))
	var restriction := int(worker.get("terrain_restriction", -1))
	for candidate in candidates:
		if not simulation_world.navigation_grid.is_position_walkable_for(candidate, radius, domain, restriction):
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
			too_close = _resource_slot_occupied(worker, candidate, simulation_world)
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
	var route: Array[Vector2] = simulation_world.pathfinder.find_path(Vector2(worker["pos"]), slot, String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1)), float(worker.get("footprint_radius", 0.3)))
	if route.is_empty() or route.back().distance_squared_to(slot) > 0.0144:
		return false
	if not simulation_world.movement_system.assign_unit_destination(worker, slot, false):
		return false
	return not worker["path"].is_empty() and Vector2(worker["path"].back()).distance_squared_to(slot) <= 0.0144


func resource_slot_occupied(worker: Dictionary, candidate: Vector2) -> bool:
	# Resource types keep separate reservation tables. Inspect adjacent cells as
	# well so neighbouring trees or bushes cannot reserve overlapping positions.
	return _resource_slot_occupied(worker, candidate, world)


func _resource_slot_occupied(worker: Dictionary, candidate: Vector2, simulation_world) -> bool:
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
					if Vector2(slots[other_id]).distance_squared_to(candidate) < separation * separation:
						return true
	return false
