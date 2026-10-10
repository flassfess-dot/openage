class_name RoRSimulationFoundationSystem
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func place_foundation(team: int, kind: String, position: Vector2, workers: Array = []) -> Variant:
	position = Coordinates.clamp_world(position, world.map_size)
	if not world.can_place_foundation(team, kind, position):
		return null
	var cost: Dictionary = world.building_cost(kind, team)
	world.spend_resource_cost(team, cost)
	var building: Dictionary = world.add_building(world.entity_id_sequence.next(), kind, position, team, false)
	world.set_entity_field(building, "reserved_cost", cost.duplicate(true))
	world.assign_workers_to_building(workers, building, "build")
	world.emit_domain_event("foundation_placed", {
		"building_id": int(building.get("id", -1)),
		"kind": kind,
		"team": team,
		"position": position,
		"reserved_cost": cost.duplicate(true),
	})
	return building


func cancel_foundation(building_id: int) -> bool:
	var building: Variant = world.find_building(building_id)
	if building == null or String(building.get("state", "complete")) != "foundation":
		return false
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
	world.update_fog_of_war()
	world.emit_domain_event("foundation_cancelled", {
		"building_id": building_id,
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
		"refunded_cost": cost.duplicate(true),
		"reseed": was_reseed,
	})
	return true


func assign_command_build(selected: Array, kind: String, position: Vector2) -> Variant:
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
		foundation = place_foundation(team, kind, position)
	if foundation != null:
		world.assign_workers_to_building(selected, foundation, "build")
	return foundation


func reseed_harvestable_building(building: Dictionary, workers: Array = []) -> Variant:
	world.last_build_failure = ""
	if building == null or not bool(building.get("harvestable", false)) or String(building.get("state", "complete")) != "complete" or String(building.get("resource_state", "")) != "depleted" or float(building.get("hp", 0.0)) <= 0.0:
		world.last_build_failure = "reseed_unavailable"
		return null
	var team := int(building.get("team", 0))
	var required_technology_id := int(world.data_repository.runtime_metadata(String(building.get("kind", ""))).get("required_technology_id", -1))
	if required_technology_id >= 0 and not world.technology_system.is_researched(team, required_technology_id):
		world.last_build_failure = "building_unavailable"
		return null
	var cost: Dictionary = world.building_cost(String(building.get("kind", "")), team)
	if not world.can_afford_resource_cost(team, cost):
		world.last_build_failure = "insufficient_resources"
		return null
	world.spend_resource_cost(team, cost)
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
	world.update_fog_of_war()
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
