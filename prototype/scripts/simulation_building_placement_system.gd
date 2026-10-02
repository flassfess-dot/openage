class_name RoRSimulationBuildingPlacementSystem
extends RefCounted

const FogOfWar := preload("res://scripts/fog_of_war.gd")
const Footprint := preload("res://scripts/footprint.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func foundation_preserves_structure_gap(team: int, kind: String, position: Vector2, minimum_gap: float) -> bool:
	if minimum_gap <= 0.0:
		return true
	var footprint := Footprint.building(world.unit_stats(kind), position)
	var new_radius := maxf(0.5, maxf(float(footprint.get("half_size", Vector2.ONE).x), float(footprint.get("half_size", Vector2.ONE).y)))
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if int(building.get("team", 0)) != team or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var existing_radius := maxf(0.5, float(building.get("footprint_radius", 1.0)))
		var clearance := new_radius + existing_radius + minimum_gap
		if position.distance_squared_to(Vector2(building.get("pos", Vector2.ZERO))) < clearance * clearance:
			return false
	return true


func can_place_foundation(team: int, kind: String, position: Vector2, mobile_occupied_cells: Variant = null) -> bool:
	world.last_build_failure = ""
	if world.data_repository.is_configured() and (not world.data_repository.has_archetype(kind) or world.data_repository.category(kind) != "building"):
		world.last_build_failure = "unknown_building_type"
		return false
	var required_technology_id := int(world.data_repository.runtime_metadata(kind).get("required_technology_id", -1))
	if required_technology_id >= 0 and not world.technology_system.is_researched(team, required_technology_id):
		world.last_build_failure = "building_unavailable"
		return false
	var footprint := Footprint.building(world.unit_stats(kind), position)
	var placement: Dictionary = world.data_repository.runtime_metadata(kind).get("placement", {})
	var placement_restriction := int(placement.get("terrain_restriction_id", -1))
	var placement_domain := String(placement.get("domain", "land"))
	if not world.navigation_grid.can_build_for(footprint.get("occupied_cells", []), placement_domain, placement_restriction):
		world.last_build_failure = "blocked_or_sloped"
		return false
	if not foundation_has_required_domain_access(footprint, placement):
		world.last_build_failure = "missing_domain_access"
		return false
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if float(building.get("hp", 0.0)) <= 0.0:
			continue
		var existing_half_size := Vector2(building.get("footprint", {}).get("obstruction_half_size", building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))))
		var candidate_half_size := Vector2(footprint.get("obstruction_half_size", footprint.get("half_size", Vector2(0.5, 0.5))))
		var delta := (Vector2(building.get("pos", Vector2.ZERO)) - position).abs()
		if delta.x < existing_half_size.x + candidate_half_size.x - 0.001 and delta.y < existing_half_size.y + candidate_half_size.y - 0.001:
			world.last_build_failure = "blocked_or_sloped"
			return false
		for cell in footprint.get("occupied_cells", []):
			if cell in building.get("occupied_cells", []):
				world.last_build_failure = "blocked_or_sloped"
				return false
	var occupied_cells: Array = footprint.get("occupied_cells", [])
	if mobile_occupied_cells != null:
		for cell in occupied_cells:
			if mobile_occupied_cells.has(cell):
				world.last_build_failure = "occupied_by_unit"
				return false
	else:
		var occupied_bounds := Rect2()
		for cell_value in occupied_cells:
			var cell: Vector2i = cell_value
			var cell_bounds := Rect2(Vector2(cell), Vector2.ONE)
			occupied_bounds = cell_bounds if not occupied_bounds.has_area() else occupied_bounds.merge(cell_bounds)
		for unit_value in world.get_units():
			var unit: Dictionary = unit_value
			if float(unit.get("hp", 0.0)) <= 0.0 or bool(unit.get("removed", false)):
				continue
			var unit_position: Vector2 = unit.get("pos", Vector2.ZERO)
			var unit_radius := maxf(0.0, float(unit.get("footprint_radius", 0.3)))
			# Use Vector2 arithmetic like the narrow phase: scalar double precision
			# can disagree with rounded Vector2 edges (e.g. 11.7 + 0.3).
			var extent := Vector2(unit_radius, unit_radius)
			var unit_min := unit_position - extent
			var unit_max := unit_position + extent
			if (
				occupied_cells.is_empty()
				or unit_max.x < occupied_bounds.position.x
				or unit_max.y < occupied_bounds.position.y
				or unit_min.x >= occupied_bounds.end.x
				or unit_min.y >= occupied_bounds.end.y
			):
				continue
			if mobile_footprint_overlaps_cells(unit, occupied_cells):
				world.last_build_failure = "occupied_by_unit"
				return false
	if world.visibility_system.state_at_world(team, position) == FogOfWar.UNKNOWN:
		world.last_build_failure = "unexplored"
		return false
	var new_radius: float = Vector2(footprint.get("half_size", Vector2.ONE)).length()
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if int(building.get("team", 0)) == team or float(building.get("hp", 0.0)) <= 0.0:
			continue
		var existing_radius: float = Vector2(building.get("footprint", {}).get("half_size", Vector2.ONE)).length()
		if Vector2(building["pos"]).distance_to(position) < new_radius + existing_radius + 1.0:
			world.last_build_failure = "enemy_territory"
			return false
	var cost: Dictionary = world.building_cost(kind, team)
	if not world.can_afford_resource_cost(team, cost):
		world.last_build_failure = "insufficient_resources"
		return false
	return true


func mobile_foundation_obstructions() -> Dictionary:
	var occupied: Dictionary = {}
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0 or bool(unit.get("removed", false)):
			continue
		var position: Vector2 = unit.get("pos", Vector2.ZERO)
		var radius := maxf(0.0, float(unit.get("footprint_radius", 0.3)))
		# Match mobile_footprint_overlaps_cells, including Vector2 rounding.
		for probe in [position, position + Vector2(radius, 0.0), position + Vector2(-radius, 0.0), position + Vector2(0.0, radius), position + Vector2(0.0, -radius)]:
			occupied[Vector2i(floori(probe.x), floori(probe.y))] = true
	return occupied


func mobile_footprint_overlaps_cells(unit: Dictionary, occupied_cells: Array) -> bool:
	var position: Vector2 = unit.get("pos", Vector2.ZERO)
	var radius := maxf(0.0, float(unit.get("footprint_radius", 0.3)))
	for probe in [position, position + Vector2(radius, 0.0), position + Vector2(-radius, 0.0), position + Vector2(0.0, radius), position + Vector2(0.0, -radius)]:
		if Vector2i(floori(probe.x), floori(probe.y)) in occupied_cells:
			return true
	return false


func map_supports_foundation(kind: String, position: Vector2) -> bool:
	if world.data_repository.is_configured() and (not world.data_repository.has_archetype(kind) or world.data_repository.category(kind) != "building"):
		return false
	var footprint := Footprint.building(world.unit_stats(kind), position)
	var placement: Dictionary = world.data_repository.runtime_metadata(kind).get("placement", {})
	var placement_restriction := int(placement.get("terrain_restriction_id", -1))
	var placement_domain := String(placement.get("domain", "land"))
	return world.navigation_grid.can_build_for(footprint.get("occupied_cells", []), placement_domain, placement_restriction) and foundation_has_required_domain_access(footprint, placement)


func foundation_map_audit(kind: String, position: Vector2) -> Dictionary:
	if world.data_repository.is_configured() and (not world.data_repository.has_archetype(kind) or world.data_repository.category(kind) != "building"):
		return {"valid": false, "reason": "unknown_building_type"}
	var footprint := Footprint.building(world.unit_stats(kind), position)
	var placement: Dictionary = world.data_repository.runtime_metadata(kind).get("placement", {})
	var placement_restriction := int(placement.get("terrain_restriction_id", -1))
	var placement_domain := String(placement.get("domain", "land"))
	var cell_audit: Array = []
	for cell_value in footprint.get("occupied_cells", []):
		var cell: Vector2i = cell_value
		cell_audit.append({
			"cell": cell,
			"terrain_id": world.navigation_grid.terrain_id(cell),
			"terrain": world.navigation_grid.terrain(cell),
			"surface": world.navigation_grid.surface_accessible(cell, placement_domain, placement_restriction),
			"occupied": world.navigation_grid.occupied_cells.has(cell),
			"occupants": world.navigation_grid.occupants(cell),
			"slope": world.navigation_grid.is_slope(cell),
		})
	var domain_access := foundation_has_required_domain_access(footprint, placement)
	return {
		"valid": world.navigation_grid.can_build_for(footprint.get("occupied_cells", []), placement_domain, placement_restriction) and domain_access,
		"cells": cell_audit,
		"domain_access": domain_access,
	}


func foundation_has_required_domain_access(footprint: Dictionary, placement: Dictionary) -> bool:
	var required_domains: Array = placement.get("required_adjacent_domains", [])
	if required_domains.is_empty():
		return true
	var occupied: Array = footprint.get("occupied_cells", [])
	var occupied_lookup: Dictionary = {}
	for cell_value in occupied:
		occupied_lookup[cell_value] = true
	var found: Dictionary = {}
	for cell_value in occupied:
		var cell: Vector2i = cell_value
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor: Vector2i = cell + offset
			if occupied_lookup.has(neighbor) or not world.navigation_grid.contains(neighbor):
				continue
			for domain_value in required_domains:
				var domain := String(domain_value)
				if world.navigation_grid.surface_accessible(neighbor, domain):
					found[domain] = true
	for domain_value in required_domains:
		if not found.has(String(domain_value)):
			return false
	return true


func worker_can_reach_foundation(worker: Dictionary, kind: String, position: Vector2) -> bool:
	var footprint := Footprint.building(world.unit_stats(kind), position)
	var occupied: Array = footprint.get("occupied_cells", [])
	var preview := {"pos": position, "footprint": footprint}
	var domain := String(worker.get("movement_domain", "land"))
	var restriction := int(worker.get("terrain_restriction", -1))
	for candidate in world.building_perimeter_candidates(worker, preview):
		if not world.navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), domain, restriction):
			continue
		var path: Array[Vector2] = world.pathfinder.find_path(Vector2(worker.get("pos", Vector2.ZERO)), candidate, domain, restriction)
		if path.is_empty():
			continue
		var crosses_future_footprint := path.any(func(point): return Vector2i(floori(point.x), floori(point.y)) in occupied)
		if not crosses_future_footprint:
			return true
	return false


func reachable_builder_ids(building: Dictionary) -> Array[int]:
	var result: Array[int] = []
	if String(building.get("state", "complete")) != "foundation" or float(building.get("hp", 0.0)) <= 0.0:
		return result
	for worker_value in world.get_units():
		var worker: Dictionary = worker_value
		if int(worker.get("team", 0)) != int(building.get("team", 0)) or float(worker.get("hp", 0.0)) <= 0.0 or not world.entity_is_worker(worker) or String(worker.get("movement_domain", "land")) != "land":
			continue
		var domain := String(worker.get("movement_domain", "land"))
		var restriction := int(worker.get("terrain_restriction", -1))
		for candidate in world.building_perimeter_candidates(worker, building):
			if not world.navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), domain, restriction):
				continue
			if not world.pathfinder.find_path(Vector2(worker.get("pos", Vector2.ZERO)), candidate, domain, restriction).is_empty():
				result.append(int(worker.get("id", -1)))
				break
	result.sort()
	return result
