class_name RoRSimulationFoundationSystem
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const Footprint := preload("res://scripts/footprint.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

var pending_clearance: Dictionary = {}
var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func place_foundation(team: int, kind: String, position: Vector2, workers: Array = [], placement_options: Dictionary = {}) -> Variant:
	position = Coordinates.clamp_world(position, world.map_size)
	placement_options = placement_options.duplicate()
	placement_options["_planned_exits"] = {}
	if not world.can_place_foundation(team, kind, position, placement_options):
		return null
	return _commit_foundation(team, kind, position, workers, placement_options)


# The wall command has just validated the whole ordered plan on this thread.
# Its virtual footprints and resource budget already include preceding cells.
func reserve_planned_wall(team: int, position: Vector2) -> Variant:
	var cells: Array = Footprint.building(world.building_placement_stats("wall"), position)["occupied_cells"]
	var slots: Variant = plan_clearance(team, cells, _units_near(position, 3.0), position)
	if slots == null:
		return null
	return _commit_foundation(team, "wall", position, [], {"_planned_exits": slots})


func _commit_foundation(team: int, kind: String, position: Vector2, workers: Array, placement_options: Dictionary) -> Dictionary:
	var cost: Dictionary = world.building_cost(kind, team)
	world.spend_resource_cost(team, cost,"construction")
	if kind == "gate":
		var replaced_walls: Dictionary = world.gate_system.replacement_wall_ids(team, position, int(placement_options.get("gate_axis", 0)))
		world.gate_system.replace_wall_segments(replaced_walls)
	var slots: Dictionary = placement_options.get("_planned_exits", {})
	if not slots.is_empty():
		placement_options["clearance_slots"] = slots
	var building: Dictionary = world.add_building(world.entity_id_sequence.next(), kind, position, team, false, placement_options)
	if world.is_bulk_loading():
		world.sync_building_navigation_occupancy(building)
	world.set_entity_field(building, "reserved_cost", cost.duplicate(true))
	if not slots.is_empty():
		pending_clearance[int(building["id"])] = building
		_sync_shared_slots(slots)
		for unit_id in slots:
			var unit: Variant = world.find_unit(unit_id)
			if unit != null and unit not in workers and unit.get("task") not in ["build", "repair"]:
				world.assign_command_move([unit], slots[unit_id])
	world.assign_workers_to_building(workers, building, "build")
	world.emit_domain_event("foundation_placed", {
		"building_id": int(building.get("id", -1)),
		"kind": kind,
		"team": team,
		"position": position,
		"reserved_cost": cost.duplicate(true),
	})
	return building


func _units_near(position: Vector2, radius: float) -> Array:
	if world.spatial_sync_system.roster_dirty:
		return world.get_units()
	return world.query_units_near(position, radius)


func _overlaps(unit: Dictionary, cells: Array) -> bool:
	return float(unit.get("hp", 0)) > 0 and not bool(unit.get("removed", false)) and world.building_placement_system.mobile_footprint_overlaps_cells(unit, cells)


# Preview and commit use the same geometry. A preview only computes endpoints.
func plan_clearance(team: int, cells: Array, nearby: Array, center: Vector2) -> Variant:
	var blockers: Array = []
	for unit in nearby:
		if _overlaps(unit, cells):
			if not world.are_teams_allied(team, int(unit.get("team", 0))) or float(unit.get("speed", 0.0)) <= 0.0:
				return null
			blockers.append(unit)
	# An adjacent site may close the only exit of an earlier accepted site
	# even when its own tiles are empty. Reserve passage for those bodies too.
	if not pending_clearance.is_empty():
		var vicinity := Rect2i(cells[0], Vector2i.ONE)
		for cell in cells:
			vicinity = vicinity.merge(Rect2i(cell, Vector2i.ONE))
		vicinity = vicinity.grow(1)
		for pending in pending_clearance.values():
			var adjacent: Array = Footprint.foundation_solid_cells(pending["kind"], pending["pos"], pending["occupied_cells"])
			if not adjacent.any(func(cell): return vicinity.has_point(cell)):
				continue
			for id in pending.get("clearance_slots", {}):
				var unit: Variant = world.find_unit(id)
				if unit == null or unit in blockers or not world.are_teams_allied(team, int(unit.get("team", 0))):
					continue
				var nearby_limit := Vector2(vicinity.size).length() + 2.0
				if Vector2(unit["pos"]).distance_squared_to(center) <= nearby_limit * nearby_limit and exit_for_worker(unit) != null:
					blockers.append(unit)
	if blockers.is_empty():
		return {}
	blockers.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	var unavailable := cells.duplicate()
	var reserved: Array = []
	var existing_slots := {}
	var blocker_ids := {}
	for unit in blockers:
		blocker_ids[int(unit["id"])] = true
	for building in pending_clearance.values():
		if center.distance_squared_to(building["pos"]) > 225.0:
			continue
		for cell in Footprint.foundation_solid_cells(building["kind"], building["pos"], building["occupied_cells"]):
			if cell not in unavailable:
				unavailable.append(cell)
		for id in building.get("clearance_slots", {}):
			var slot: Vector2 = building["clearance_slots"][id]
			if blocker_ids.has(id):
				existing_slots[id] = slot
			else:
				var other: Variant = world.find_unit(id)
				if other != null:
					reserved.append({"pos":slot, "footprint_radius": other.get("footprint_radius", 0.3)})
	var bounds := Rect2i(cells[0], Vector2i.ONE)
	for cell in cells:
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	# Include space for the group when the first ring is already occupied.
	var search := bounds.grow(3 + ceili(sqrt(blockers.size())))
	var neighbors := _units_near(center, Vector2(search.size).length() + 2.0)
	var slots := {}
	for unit in blockers:
		var origin := Vector2(unit["pos"])
		var candidates: Array[Vector2] = []
		for y in range(search.position.y, search.end.y):
			for x in range(search.position.x, search.end.x):
				var cell := Vector2i(x, y)
				if world.navigation_grid.contains(cell) and cell not in unavailable:
					candidates.append(Vector2(cell) + Vector2(0.5, 0.5))
		candidates.sort_custom(func(a, b): return origin.distance_squared_to(a) < origin.distance_squared_to(b))
		var previous: Variant = existing_slots.get(int(unit["id"]))
		if previous != null and previous in candidates:
			candidates.erase(previous)
			candidates.push_front(previous)
		var slot: Variant = _find_exit(unit, candidates, unavailable, neighbors, reserved)
		if slot == null:
			return null
		slots[int(unit["id"])] = slot
		reserved.append({"pos": slot, "footprint_radius":unit.get("footprint_radius", 0.3)})
	return slots


func _find_exit(unit: Dictionary, candidates: Array[Vector2], cells: Array, neighbors: Array, reserved: Array) -> Variant:
	var origin := Vector2(unit["pos"])
	var radius := float(unit.get("footprint_radius", 0.3))
	var domain := String(unit.get("movement_domain", "land"))
	var restriction := int(unit.get("terrain_restriction", -1))
	var possible_detours: Array[Vector2] = []
	for candidate in candidates:
		# Leave additional clearance for the movement controller's arrival tolerance.
		var body := {"pos":candidate, "footprint_radius":radius + 0.2}
		if world.building_placement_system.mobile_footprint_overlaps_cells(body, cells) or not world.pathfinder.is_position_walkable(candidate, radius, domain, restriction):
			continue
		if not _exit_has_space(unit, candidate, neighbors) or not _exit_has_space(unit, candidate, reserved):
			continue
		var has_outlet := false
		for direction in [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN]:
			var next: Vector2 = candidate + direction
			body["pos"] = next
			if not world.building_placement_system.mobile_footprint_overlaps_cells(body, cells) and world.pathfinder.is_segment_walkable(candidate, next, radius, domain, restriction):
				has_outlet = true
				break
		if not has_outlet:
			continue
		if world.pathfinder.is_segment_walkable(origin, candidate, radius, domain, restriction):
			return candidate
		possible_detours.append(candidate)
	for candidate in possible_detours:
		var path: Array = world.pathfinder.find_path(origin, candidate, domain, restriction, radius)
		if not path.is_empty() and Vector2(path.back()).distance_squared_to(candidate) < 0.01:
			return candidate
	return null


func _exit_has_space(unit: Dictionary, slot: Vector2, others: Array) -> bool:
	for other in others:
		if int(other.get("id", -1)) == int(unit["id"]) or float(other.get("hp", 1.0)) <= 0.0 or bool(other.get("removed", false)):
			continue
		var separation := Footprint.separation_distance(unit, other)
		if slot.distance_squared_to(other["pos"]) < separation * separation:
			return false
	return true


func exit_for_worker(worker: Dictionary) -> Variant:
	for building in pending_clearance.values():
		var slot: Variant = building.get("clearance_slots", {}).get(int(worker["id"]))
		if slot != null:
			var cells := Footprint.foundation_solid_cells(building["kind"], building["pos"], building["occupied_cells"])
			if _overlaps(worker, cells):
				return slot
	return null


func _exit_reserved_by_foundation(unit: Dictionary, slot: Vector2) -> bool:
	var body := {"pos":slot, "footprint_radius":float(unit.get("footprint_radius", 0.3)) + 0.2}
	for other in pending_clearance.values():
		var cells := Footprint.foundation_solid_cells(other["kind"], other["pos"], other["occupied_cells"])
		if world.building_placement_system.mobile_footprint_overlaps_cells(body, cells):
			return true
	return false


func _sync_shared_slots(slots: Dictionary) -> void:
	for building in pending_clearance.values():
		var other_slots: Dictionary = building.get("clearance_slots", {})
		for id in slots:
			if other_slots.has(id):
				other_slots[id] = slots[id]


func advance_clearance() -> void:
	for id in pending_clearance.keys():
		var building: Dictionary = pending_clearance[id]
		if float(building.get("hp", 0)) <= 0 or not building.has("clearance_slots"):
			pending_clearance.erase(id)
			continue
		var center := Vector2(building["pos"])
		var cells := Footprint.foundation_solid_cells(building["kind"], center, building["occupied_cells"])
		var nearby := _units_near(center, Vector2(building["footprint"]["half_size"]).length() + 2.0)
		var blockers := nearby.filter(func(unit): return _overlaps(unit, cells))
		if blockers.is_empty():
			# Linked sites close after their shared evacuees are outside the
			# whole obstruction, including a neighboring segment used as an exit.
			var still_leaving := false
			for unit_id in building["clearance_slots"]:
				var unit: Variant = world.find_unit(unit_id)
				if unit != null and exit_for_worker(unit) != null:
					still_leaving = true
					break
			if still_leaving:
				continue
			world.erase_entity_field(building, "clearance_slots")
			pending_clearance.erase(id)
			world.sync_building_navigation_occupancy(building)
			continue
		# Hostiles can enter while allies are leaving. They keep the site open,
		# but must never receive an order or prevent allies from escaping.
		blockers = blockers.filter(func(unit): return world.are_teams_allied(int(building["team"]), int(unit["team"])))
		var slots: Dictionary = building["clearance_slots"]
		var needs_plan := false
		for unit in blockers:
			var slot: Variant = slots.get(int(unit["id"]))
			if slot == null or _exit_reserved_by_foundation(unit, slot) or not world.pathfinder.is_position_walkable(slot, float(unit.get("footprint_radius", 0.3)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
				needs_plan = true
				break
		if needs_plan:
			var replacement: Variant = plan_clearance(int(building["team"]), cells, blockers, center)
			if replacement == null:
				continue
			slots = replacement
			world.set_entity_field(building, "clearance_slots", slots)
			_sync_shared_slots(slots)
		for unit in blockers:
			if unit.get("task") in ["build", "repair"]:
				continue
			var goal := Vector2(slots[int(unit["id"])])
			if unit.get("task") != "move" or Vector2(unit.get("destination", unit["pos"])).distance_squared_to(goal) > 0.25:
				world.assign_command_move([unit], goal)


func cancel_foundation(building_id: int) -> bool:
	var building: Variant = world.find_building(building_id)
	if building == null or String(building.get("state", "complete")) != "foundation":
		return false
	pending_clearance.erase(building_id)
	var cost: Dictionary = building.get("reserved_cost", {})
	world.refund_resource_cost(int(building.get("team", 0)), cost)
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if int(unit.get("target_building_id", -1)) == building_id:
			world.finish_building_order(unit, "foundation_cancelled")
	var was_reseed := bool(building.get("reseed_from_depleted", false))
	if was_reseed:
		world.set_entity_field(building, "state", "complete")
		world.set_entity_field(building, "construction_progress", 1.0)
		world.set_entity_field(building, "construction_stage", 3)
		world.set_entity_field(building, "hp", building["max_hp"])
		world.set_entity_field(building, "amount", 0)
		world.set_entity_field(building, "max_amount", maxi(0, int(building.get("reseed_previous_max_amount", building.get("max_amount", 0)))))
		world.set_entity_field(building, "resource_state", "depleted")
		world.set_entity_field(building, "resource_depletion_stage", 2)
		world.set_entity_field(building, "reserved_cost", {})
		world.set_entity_field(building, "builders", {})
		world.erase_entity_field(building, "reseed_from_depleted")
		world.erase_entity_field(building, "reseed_previous_max_amount")
		EntityComponents.sync_dynamic(building)
	else:
		world.deactivate_building_victory_objective(building)
		for index in range(world.buildings.size() - 1, -1, -1):
			if int(world.buildings[index].get("id", -1)) == building_id:
				world.production_system.unregister_building(building_id)
				world.entity_changes.remove(building_id)
				world.render_entity_projection_cache.erase(building_id)
				world.buildings_by_id.erase(building_id)
				world.buildings.remove_at(index)
				world.spatial_sync_system.mark_roster_dirty()
				world.mark_combat_roster_dirty()
				break
	world.building_approach_slots.erase(building_id)
	world.refresh_building_connectivity()
	world.release_building_navigation_occupancy(building)
	world.refresh_changed_fog_of_war()
	world.emit_domain_event("foundation_cancelled", {
		"building_id": building_id,
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
		"refunded_cost": cost.duplicate(true),
		"reseed": was_reseed,
	})
	return true


func assign_command_build(selected: Array, kind: String, position: Vector2, placement_options: Dictionary = {}) -> Variant:
	var foundation: Variant = null
	var team := int(selected[0].get("team", 0)) if not selected.is_empty() else 0
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if int(building.get("team", 0)) != team or String(building.get("kind", "")) != kind or Vector2(building["pos"]).distance_squared_to(position) >= 0.01:
			continue
		if String(building.get("state", "complete")) == "foundation":
			foundation = building
			break
		if bool(building.get("harvestable", false)) and String(building.get("resource_state", "")) == "depleted":
			return reseed_harvestable_building(building, selected)
	if foundation == null:
		return place_foundation(team, kind, position, selected, placement_options)
	if foundation != null:
		world.assign_workers_to_building(selected, foundation, "build")
	return foundation


func reseed_harvestable_building(building: Dictionary, workers: Array = [], prepaid_cost: Variant = null) -> Variant:
	world.last_build_failure = ""
	if building == null or not bool(building.get("harvestable", false)) or String(building.get("state", "complete")) != "complete" or String(building.get("resource_state", "")) != "depleted" or float(building.get("hp", 0.0)) <= 0.0:
		world.last_build_failure = "reseed_unavailable"
		return null
	var team := int(building.get("team", 0))
	var required_technology_id := int(world.data_repository.runtime_metadata(String(building.get("kind", ""))).get("required_technology_id", -1))
	if required_technology_id >= 0 and not world.technology_system.is_researched(team, required_technology_id):
		world.last_build_failure = "building_unavailable"
		return null
	var cost: Dictionary = prepaid_cost.duplicate(true) if prepaid_cost is Dictionary else world.building_cost(String(building.get("kind", "")), team)
	if prepaid_cost == null and not world.can_afford_resource_cost(team, cost):
		world.last_build_failure = "insufficient_resources"
		return null
	if prepaid_cost == null:
		world.spend_resource_cost(team, cost,"reseed")
	world.resource_approach_slots.erase(int(building.get("id", -1)))
	world.set_entity_field(building, "reseed_from_depleted", true)
	world.set_entity_field(building, "reseed_previous_max_amount", int(building.get("max_amount", 0)))
	world.set_entity_field(building, "state", "foundation")
	world.set_entity_field(building, "construction_progress", 0.0)
	world.set_entity_field(building, "construction_stage", 0)
	world.set_entity_field(building, "hp", maxf(1.0, float(building.get("max_hp", 1.0)) * 0.1))
	world.set_entity_field(building, "amount", 0)
	world.set_entity_field(building, "resource_state", "planting")
	world.set_entity_field(building, "resource_depletion_stage", 0)
	world.set_entity_field(building, "reserved_cost", cost.duplicate(true))
	world.set_entity_field(building, "builders", {})
	EntityComponents.sync_dynamic(building)
	world.assign_workers_to_building(workers, building, "build")
	world.sync_building_navigation_occupancy(building)
	world.emit_domain_event("foundation_placed", {
		"building_id": int(building.get("id", -1)),
		"kind": String(building.get("kind", "")),
		"team": team,
		"position": building.get("pos", Vector2.ZERO),
		"reserved_cost": cost.duplicate(true),
		"reseed": true,
	})
	return building


func complete_foundation(building: Dictionary) -> void:
	var completing_builder_ids: Array = []
	for worker in world.get_units():
		if int(worker.get("target_building_id", -1)) == int(building["id"]) and String(worker.get("task", "")) == "build":
			completing_builder_ids.append(int(worker["id"]))
	completing_builder_ids.sort()
	world.set_entity_field(building, "state", "complete")
	world.set_entity_field(building, "construction_progress", 1.0)
	world.set_entity_field(building, "construction_stage", 3)
	world.set_entity_field(building, "hp", building["max_hp"])
	world.set_entity_field(building, "reserved_cost", {})
	world.set_entity_field(building, "builders", {})
	world.erase_entity_field(building, "reseed_from_depleted")
	world.erase_entity_field(building, "reseed_previous_max_amount")
	activate_harvestable_building(building)
	EntityComponents.sync_dynamic(building)
	activate_building_completion(building)
	if building.get("kind") == "gate":
		# The planner can use the completed passage before the leaves open.
		world.gate_system.policy_revision += 1
	world.sync_building_victory_objective(building)
	world.refresh_building_connectivity()
	var building_id := int(building["id"])
	for unit_value in world.get_units():
		var unit: Dictionary = unit_value
		if int(unit.get("target_building_id", -1)) == building_id and String(unit.get("task", "")) == "build":
			world.finish_building_order(unit, "construction_complete")
	var runtime_metadata: Dictionary = world.data_repository.runtime_metadata(String(building.get("kind", "")))
	if bool(runtime_metadata.get("auto_gather_on_complete", false)) and int(building.get("amount", 0)) > 0:
		var gatherers: Array = []
		for builder_id in completing_builder_ids:
			var builder: Variant = world.find_unit(int(builder_id))
			if builder != null and float(builder.get("hp", 0.0)) > 0.0 and world.entity_is_worker(builder) and OrderPipeline.queued(builder).is_empty():
				gatherers.append(builder)
		if not gatherers.is_empty():
			world.assign_command_gather(gatherers, building_id)
	else:
		world.assign_builders_to_next_visible_foundation(completing_builder_ids, building_id)
	world.building_approach_slots.erase(building_id)
	world.sync_building_navigation_occupancy(building)
	world.refresh_changed_fog_of_war()
	world.emit_domain_event("build_complete", {
		"building_id": building_id,
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
	})


func assign_builders_to_next_visible_foundation(builder_ids: Array, completed_building_id: int) -> void:
	for builder_id_value in builder_ids:
		var worker: Variant = world.find_unit(int(builder_id_value))
		if worker == null or float(worker.get("hp", 0.0)) <= 0.0 or not world.entity_is_worker(worker) or not OrderPipeline.queued(worker).is_empty():
			continue
		var team := int(worker.get("team", 0))
		var vision_range := maxf(0.0, float(worker.get("components", {}).get("vision", {}).get("range", 0.0)))
		var worker_position := Vector2(worker.get("pos", Vector2.ZERO))
		var nearest_foundation: Variant = null
		var nearest_distance_squared := INF
		for candidate_value in world.buildings:
			var candidate: Dictionary = candidate_value
			if int(candidate.get("id", -1)) == completed_building_id or int(candidate.get("team", 0)) != team or String(candidate.get("state", "complete")) != "foundation" or float(candidate.get("hp", 0.0)) <= 0.0:
				continue
			var candidate_position := Vector2(candidate.get("pos", Vector2.ZERO))
			var distance_squared := worker_position.distance_squared_to(candidate_position)
			var half_size := Vector2(candidate.get("footprint", {}).get("half_size", Vector2(0.5, 0.5)))
			var outside := (candidate_position - worker_position).abs() - half_size
			outside = Vector2(maxf(0.0, outside.x), maxf(0.0, outside.y))
			if outside.length_squared() > vision_range * vision_range:
				continue
			var visible: bool = world.visibility_system.state_at_world(team, candidate_position) == FogOfWar.VISIBLE
			for cell in candidate.get("occupied_cells", []):
				visible = visible or world.visibility_system.state_at_world(team, Vector2(cell) + Vector2(0.5, 0.5)) == FogOfWar.VISIBLE
			if not visible:
				continue
			if not world.worker_can_reach_foundation(worker, String(candidate["kind"]), candidate_position):
				continue
			if nearest_foundation == null or distance_squared < nearest_distance_squared or (is_equal_approx(distance_squared, nearest_distance_squared) and int(candidate.get("id", -1)) < int(nearest_foundation.get("id", -1))):
				nearest_foundation = candidate
				nearest_distance_squared = distance_squared
		if nearest_foundation != null:
			world.assign_workers_to_building([worker], nearest_foundation, "build")


func activate_building_completion(building: Dictionary) -> void:
	var kind := String(building.get("kind", ""))
	if not world.data_repository.has_archetype(kind):
		return
	var team := int(building.get("team", 0))
	activate_population_support(building)
	if team <= 0:
		return
	var civilization_id := int(world.civilization_by_team.get(team, 13))
	var technology_id: int = world.data_repository.completion_technology_id(kind, civilization_id)
	if technology_id < 0 or world.technology_system.technology(technology_id).is_empty() or world.technology_system.is_researched(team, technology_id):
		return
	world.apply_technology_commands(team, world.technology_system.complete_research(team, technology_id))
	world.emit_domain_event("building_technology_unlocked", {
		"building_id": int(building.get("id", -1)),
		"building_kind": kind,
		"team": team,
		"technology_id": technology_id,
	})


func configure_harvestable_building(building: Dictionary, completed: bool) -> void:
	if not bool(building.get("harvestable", false)):
		return
	var runtime_metadata: Dictionary = world.data_repository.runtime_metadata(String(building.get("kind", "")))
	var maximum := harvestable_amount_for(String(building.get("kind", "")), int(building.get("team", 0)))
	world.set_entity_field(building, "resource_type_id", int(runtime_metadata.get("resource_type_id", -1)))
	world.set_entity_field(building, "resource_amount_id", int(runtime_metadata.get("resource_amount_id", -1)))
	world.set_entity_field(building, "max_amount", maximum)
	world.set_entity_field(building, "amount", maximum if completed else 0)
	world.set_entity_field(building, "resource_state", "available" if completed and maximum > 0 else "depleted" if completed else "planting")
	world.set_entity_field(building, "resource_depletion_stage", 0 if maximum > 0 else 2)
	var carrier: Dictionary = building.get("components", {}).get("resource_carrier", {})
	carrier["capacity"] = float(maximum)
	carrier["amount"] = float(building["amount"])
	carrier["resource_type_id"] = int(building["resource_type_id"])


func activate_harvestable_building(building: Dictionary) -> void:
	if not bool(building.get("harvestable", false)):
		return
	configure_harvestable_building(building, true)
	world.emit_domain_event("harvestable_activated", {
		"building_id": int(building.get("id", -1)),
		"resource_type_id": int(building.get("resource_type_id", -1)),
		"amount": int(building.get("amount", 0)),
	})


func harvestable_amount_for(kind: String, team: int) -> int:
	var amount_resource_id := int(world.data_repository.runtime_metadata(kind).get("resource_amount_id", -1))
	if amount_resource_id < 0:
		return 0
	return maxi(0, roundi(world.technology_system.rule_resource_value(team, amount_resource_id)))


func population_support_for(kind: String, team: int) -> int:
	var source: Dictionary = world.object_record_for(kind, team)
	for storage_value in source.get("resources", {}).get("storage", []):
		var storage: Dictionary = storage_value
		if int(storage.get("type", -1)) == 4 and float(storage.get("amount", 0.0)) > 0.0:
			return maxi(0, roundi(float(storage.get("amount", 0.0))))
	return 0


func activate_population_support(building: Dictionary) -> void:
	if bool(building.get("population_support_applied", false)):
		return
	var support := maxi(0, int(building.get("population_support", 0)))
	if support <= 0:
		return
	var team := int(building.get("team", 0))
	world.economy_system.add_population_housing(team, support)
	world.set_entity_field(building, "population_support_applied", true)
	world.emit_domain_event("population_cap_changed", {
		"building_id": int(building.get("id", -1)),
		"team": team,
		"delta": support,
		"housing": world.economy_system.get_population_housing(team),
		"cap": world.economy_system.get_population_cap(team),
	})


func deactivate_population_support(building: Dictionary) -> void:
	if not bool(building.get("population_support_applied", false)):
		return
	var support := maxi(0, int(building.get("population_support", 0)))
	var team := int(building.get("team", 0))
	world.economy_system.add_population_housing(team, -support)
	world.set_entity_field(building, "population_support_applied", false)
	world.emit_domain_event("population_cap_changed", {
		"building_id": int(building.get("id", -1)),
		"team": team,
		"delta": -support,
		"housing": world.economy_system.get_population_housing(team),
		"cap": world.economy_system.get_population_cap(team),
	})
