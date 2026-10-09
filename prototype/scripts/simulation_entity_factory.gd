class_name RoRSimulationEntityFactory
extends RefCounted

const FormationRoles := preload("res://scripts/formation_roles.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const Coordinates := preload("res://scripts/coordinates.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const NavigationGrid := preload("res://scripts/navigation_grid.gd")
const MobileCollision := preload("res://scripts/mobile_collision.gd")
const Footprint := preload("res://scripts/footprint.gd")
const SimulationEconomySystem := preload("res://scripts/simulation_economy_system.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func add_unit(team: int, kind: String, position: Vector2, selected: bool) -> Dictionary:
	if team > 0:
		world.player_registry.ensure(team, int(world.civilization_by_team.get(team, 13)))
	var stats: Dictionary = world.unit_stats(kind)
	var source: Dictionary = world.object_record_for(kind, team)
	var terrain_restriction := int(source.get("links", {}).get("terrain_restriction", stats.get("terrain_restriction", -1)))
	var movement_domain := "water" if terrain_restriction == 3 else "land"
	var footprint: Dictionary = Footprint.mobile(kind, stats)
	var radius := float(footprint["movement_radius"])
	if movement_domain == "water" and not world.navigation_grid.is_position_walkable_for(position, radius, movement_domain, terrain_restriction):
		var placement_cell: Vector2i = world.pathfinder.nearest_walkable(Vector2i(floori(position.x), floori(position.y)), movement_domain, terrain_restriction, radius)
		if placement_cell.x >= 0:
			position = Vector2(placement_cell) + Vector2(0.5, 0.5)
	var initial_facing: int = world.facing_for_vector(Vector2(12.0, 12.0) - position)
	var entity_id: int = world.entity_id_sequence.next()
	var civilization_id := int(world.civilization_by_team.get(team, 13))
	var components: Dictionary = EntityComponents.for_unit(entity_id, team, civilization_id, kind, position, world.elevation_at(position), stats, source, footprint, initial_facing)
	var health: Dictionary = components["health"]
	var combat: Dictionary = components["combat"]
	var production: Dictionary = components["production"]
	var worker_component: Dictionary = components["worker"]
	var carrier_component: Dictionary = components["resource_carrier"]
	var attacks: Array = combat["attacks"]
	var attack_damage := CombatRules.primary_attack_damage(attacks, 3.0)
	var unit := {
		"id": entity_id,
		"team": team,
		"kind": kind,
		"pos": position,
		"previous_pos": position,
		"elevation": world.elevation_at(position),
		"target": position,
		"destination": position,
		"path": [],
		"path_index": 0,
		"path_request_id": 0,
		"path_status": "idle",
		"path_grid_revision": world.navigation_grid.revision,
		"diagnostic_reason": "",
		"reserved_destination": null,
		"desired_velocity": Vector2.ZERO,
		"actual_velocity": Vector2.ZERO,
		"cohesion_speed_scale": 1.0,
		"formation_shared_motion": false,
		"formation_shared_isolated": false,
		"selected": selected,
		"hp": health["current"],
		"max_hp": health["maximum"],
		"task": "idle",
		"target_id": -1,
		"resource_id": -1,
		"cooldown": 0.0,
		"work": 0.0,
		"gather_stage": "none",
		"gather_interval": 1.0 / maxf(0.01, float(worker_component.get("work_rate", 1.0))),
		"resource_approach_slot": null,
		"dropoff_id": -1,
		"dropoff_position": null,
		"carried_amount": 0.0,
		"carried_resource_type_id": -1,
		"worker_role_source_unit_id": -1,
		"worker_role_name": "",
		"worker_role_profile": {},
		"presentation_state_overrides": {},
		"pending_hunt_target_id": -1,
		"carry_capacity": maxf(0.0, float(carrier_component.get("capacity", 0.0))),
		"gather_cycles": 0,
		"deposit_cycles": 0,
		"target_building_id": -1,
		"building_approach_slot": null,
		"speed": components["movement"]["speed"],
		"terrain_restriction": terrain_restriction,
		"movement_domain": movement_domain,
		"footprint_radius": footprint["movement_radius"],
		"footprint": footprint,
		"selection_radius": footprint["selection_radius"],
		"selection_height": footprint["selection_height"],
		"minimum_clearance": footprint["minimum_clearance"],
		"push_priority": footprint["push_priority"],
		"base_push_priority": footprint["push_priority"],
		"stuck_ticks": 0,
		"attack_damage": attack_damage,
		"attack_period": combat["attack_period"],
		"attack_range_min": combat["range_min"],
		"attack_range": combat["range_max"],
		"blast_range": combat["blast_range"],
		"projectile_id": combat["projectile_id"],
		"combat_enabled": false,
		"stance": "passive",
		"acquisition_range": 0.0,
		"chase_range": 0.0,
		"retaliation_target_id": -1,
		"attack_autonomous": false,
		"combat_leash_origin": position,
		"combat_resume": {},
		"attack_move_destination": null,
		"facing": initial_facing,
		"movement_facing": initial_facing,
		"desired_facing": initial_facing,
		"action_facing": initial_facing,
		"formation_forward": Vector2.ZERO,
		"formation_facing": initial_facing,
		"preferred_formation": "RECTANGLE",
		"formation_role": String(stats.get("formation_role", FormationRoles.role_for(kind))),
		"formation_group_id": -1,
		"formation_slot_id": -1,
		"formation_slot_capacity": 0.0,
		"formation_home": null,
		"formation_slot_mode": "none",
		"combat_role": "",
		"combat_slot_index": -1,
		"combat_slot_count": 0,
		"combat_approach": Vector2.ZERO,
		"combat_destination": null,
		"anim": world.simulation_rng.randf(),
		"anim_state": AnimationController.IDLE,
		"animation_events_fired": {},
		"population_cost": int(production.get("population_cost", 0)),
		"population_base_cost": int(production.get("population_cost", 0)),
		"population_points_cost": int(production.get("population_cost", 0)) * SimulationEconomySystem.POPULATION_POINT_SCALE,
		"population_accounted": false,
		"population_released": false,
		"victory_objective_id": -1,
		"source_unit_id": int(source.get("unit_id", stats.get("unit_id", -1))),
		"unit_lineage": [int(source.get("unit_id", stats.get("unit_id", -1)))],
		"display_graphic_id": int(source.get("graphics", {}).get("idle", -1)),
		"death_phase": "alive",
		"death_elapsed": 0.0,
		"death_duration": world.death_animation_duration(kind),
		"corpse_elapsed": 0.0,
		"corpse_duration": world.corpse_animation_duration(source, team),
		"corpse_source_id": int(source.get("links", {}).get("dead_unit_id", -1)),
		"death_complete": false,
		"removed": false,
		"components": components,
	}
	world.apply_archetype_identity(unit, kind)
	if world.entity_has_behavior_tag(unit, "capturable"):
		world.capturable_units.append(unit)
	world.configure_unit_combat_awareness(unit)
	EntityComponents.sync_dynamic(unit)
	unit["solid_animal"] = MobileCollision.is_solid_animal(unit)
	world.units.append(unit)
	world.units_by_id[entity_id] = unit
	world.mark_combat_roster_dirty()
	world.unit_activity_registry.refresh(unit)
	world.track_conquest_entity(unit)
	world.register_unit_victory_objective(unit)
	world.apply_technology_state_to_entity(unit, team)
	if world.conversion_system.is_converter(unit):
		var conversion: Dictionary = unit.get("components", {}).get("conversion", {})
		conversion["recharge_rate"] = world.conversion_system.recharge_rate_for(unit)
	world.economy_system.add_population_points(team, int(unit["population_points_cost"]))
	unit["population_accounted"] = true
	world.spatial_index.insert(unit, position, unit["footprint_radius"], "unit")
	if not world.is_bulk_loading():
		world.update_fog_of_war()
	world.emit_domain_event("entity_created", {
		"entity_id": entity_id,
		"entity_category": "unit",
		"kind": kind,
		"team": team,
	})
	return unit


func add_resource(kind: String, position: Vector2, amount: int, resolve_placement: bool) -> Dictionary:
	var source: Dictionary = world.resource_stats(kind)
	var footprint: Dictionary = Footprint.resource(kind, source)
	var runtime_metadata: Dictionary = world.data_repository.runtime_metadata(kind)
	var behavior_tags: Array = world.data_repository.behavior_tags(kind)
	var blocks_navigation := bool(runtime_metadata.get("blocks_navigation", NavigationGrid.default_resource_blocks_navigation(behavior_tags)))
	var terrain_restriction := int(runtime_metadata.get("placement_terrain_restriction_id", source.get("links", {}).get("terrain_restriction", -1)))
	var placement_domain := String(runtime_metadata.get("placement_domain", "water" if terrain_restriction == 3 else "land"))
	if resolve_placement:
		position = find_resource_placement(position, float(footprint["movement_radius"]), placement_domain, terrain_restriction)
	footprint["occupied_cells"] = [Vector2i(floori(position.x), floori(position.y))]
	var safe_amount := maxi(0, amount)
	var resource_type_id: int = world.resource_type_for(kind, source)
	var entity_id: int = world.entity_id_sequence.next()
	var components: Dictionary = EntityComponents.for_resource(entity_id, kind, position, world.elevation_at(position), safe_amount, source, footprint)
	var resource := {
		"id": entity_id,
		"kind": kind,
		"pos": position,
		"elevation": world.elevation_at(position),
		"hp": float(source.get("health", 1.0)),
		"max_hp": float(source.get("health", 1.0)),
		"amount": safe_amount,
		"max_amount": safe_amount,
		"resource_type_id": resource_type_id,
		"placement_domain": placement_domain,
		"allowed_gatherer_domains": runtime_metadata.get("allowed_gatherer_domains", []).duplicate(),
		"terrain_restriction": terrain_restriction,
		"blocks_navigation": blocks_navigation,
		"state": "available" if safe_amount > 0 else "depleted",
		"depletion_stage": 0 if safe_amount > 0 else 2,
		"visible_when_depleted": bool(runtime_metadata.get("visible_when_depleted", kind == "tree")),
		"decay_rate": maxf(0.0, float(runtime_metadata.get("decay_rate", 0.0))),
		"decay_accumulator": 0.0,
		"footprint": footprint,
		"footprint_radius": footprint["movement_radius"],
		"selection_radius": footprint["selection_radius"],
		"selection_height": footprint["selection_height"],
		"components": components,
	}
	if float(resource["decay_rate"]) > 0.0:
		resource["decay_elapsed"] = 0.0
		resource["facing"] = 0

	if kind == "tree":
		resource["tree_phase"] = "standing" if safe_amount > 0 else "stump"
		resource["tree_fall_elapsed"] = 0.0
		resource["tree_fall_duration"] = 0.65
		resource["source_felled_graphic_id"] = int(source.get("graphics", {}).get("death", 636))
		resource["source_felled_asset_name"] = "graphic_%d" % int(resource["source_felled_graphic_id"])
		if safe_amount <= 0:
			resource["hp"] = 0.0
	world.apply_archetype_identity(resource, kind)
	EntityComponents.sync_dynamic(resource)
	world.resource_nodes.append(resource)
	world.resource_nodes_by_id[entity_id] = resource
	var resource_cell_index: int = floori(position.y) * world.map_size.x + floori(position.x)
	if not world.resource_nodes_by_cell.has(resource_cell_index):
		world.resource_nodes_by_cell[resource_cell_index] = []
	world.resource_nodes_by_cell[resource_cell_index].append(resource)
	world.mark_known_resource_dirty(resource)
	if float(resource.get("decay_rate", 0.0)) > 0.0:
		world.decaying_resource_nodes.append(resource)
	if safe_amount > 0 and kind == "tree":
		world.register_forest_resource(resource)
	if not world.is_bulk_loading() and world.navigation_grid != null and safe_amount > 0 and blocks_navigation:
		world.navigation_grid.occupy(resource.get("footprint", {}).get("occupied_cells", [Vector2i(floori(position.x), floori(position.y))]), "resource", entity_id)
	world.emit_domain_event("entity_created", {
		"entity_id": entity_id,
		"entity_category": "resource",
		"kind": kind,
		"team": 0,
	})
	return resource


func find_resource_placement(desired: Vector2, radius: float, movement_domain: String = "land", restriction_id: int = -1) -> Vector2:
	var candidate := Coordinates.clamp_world(desired, world.map_size)
	if _resource_placement_is_valid(candidate, radius, movement_domain, restriction_id):
		return candidate
	for ring in range(1, maxi(world.map_size.x, world.map_size.y) * 2 + 1):
		var distance := float(ring) * 0.5
		for offset in [Vector2(distance, 0), Vector2(0, distance), Vector2(-distance, 0), Vector2(0, -distance), Vector2(distance, distance), Vector2(-distance, distance), Vector2(-distance, -distance), Vector2(distance, -distance)]:
			candidate = Coordinates.clamp_world(desired + offset, world.map_size)
			if _resource_placement_is_valid(candidate, radius, movement_domain, restriction_id):
				return candidate
	return Coordinates.clamp_world(desired, world.map_size)


func _resource_placement_is_valid(candidate: Vector2, radius: float, movement_domain: String, restriction_id: int) -> bool:
	var cell := Vector2i(floori(candidate.x), floori(candidate.y))
	if world.map_reserved_foundation_cells.has(cell) or not world.navigation_grid.is_walkable_for(cell, movement_domain, restriction_id):
		return false
	for occupant_value in world.navigation_grid.occupants(cell):
		if String(occupant_value.get("category", "")) == "building":
			return false
	for existing in world.resource_nodes:
		if int(existing.get("amount", 0)) <= 0:
			continue
		var minimum_distance := radius + float(existing.get("footprint_radius", 0.2)) + 0.02
		if candidate.distance_squared_to(existing["pos"]) < minimum_distance * minimum_distance:
			return false
	return true


func add_building(id: int, kind: String, position: Vector2, team: int = 1, completed: bool = true) -> Dictionary:
	if team > 0:
		world.player_registry.ensure(team, int(world.civilization_by_team.get(team, 13)))
	var stats: Dictionary = world.unit_stats(kind)
	var source: Dictionary = world.object_record_for(kind, team)
	var footprint: Dictionary = Footprint.building(stats, position)
	var obstruction_type := int(source.get("geometry", {}).get("obstruction_type", stats.get("obstruction_type", 2)))
	var civilization_id := int(world.civilization_by_team.get(team, 13))
	var components: Dictionary = EntityComponents.for_building(id, team, civilization_id, kind, position, world.elevation_at(position), stats, source, footprint)
	var health: Dictionary = components["health"]
	var combat: Dictionary = components["combat"]
	var attacks: Array = combat.get("attacks", [])
	var obstruction_half_size := Vector2(footprint.get("obstruction_half_size", footprint["half_size"]))
	var construction_required := maxf(1.0, float(components.get("production", {}).get("creation_time", 1.0)))
	var starting_health := float(health["maximum"]) if completed else maxf(1.0, float(health["maximum"]) * 0.1)
	var production_queue: Array = []
	var building := {
		"id": id,
		"team": team,
		"kind": kind,
		"pos": position,
		"previous_pos": position,
		"elevation": world.elevation_at(position),
		"selected": false,
		"hp": starting_health,
		"max_hp": health["maximum"],
		"footprint": footprint,
		"footprint_radius": maxf(obstruction_half_size.x, obstruction_half_size.y),
		"occupied_cells": footprint["occupied_cells"],
		"obstruction_type": obstruction_type,
		"passable": obstruction_type == 0 or "passable" in stats.get("behavior_tags", []),
		"harvestable": "harvestable" in stats.get("behavior_tags", []),
		"state": "complete" if completed else "foundation",
		"construction_progress": 1.0 if completed else 0.0,
		"construction_required": construction_required,
		"construction_stage": 3 if completed else 0,
		"reserved_cost": {},
		"builders": {},
		"production_queue": production_queue,
		"production_progress": 0.0,
		"population_support": world.population_support_for(kind, team),
		"population_support_applied": false,
		"task": "idle",
		"target_id": -1,
		"cooldown": 0.0,
		"speed": 0.0,
		"movement_domain": "static",
		"attack_damage": CombatRules.primary_attack_damage(attacks, 0.0),
		"attack_period": float(combat.get("attack_period", 0.0)),
		"attack_range_min": float(combat.get("range_min", 0.0)),
		"attack_range": float(combat.get("range_max", 0.0)),
		"blast_range": float(combat.get("blast_range", 0.0)),
		"projectile_id": int(combat.get("projectile_id", -1)),
		"combat_enabled": false,
		"stance": "passive",
		"acquisition_range": 0.0,
		"chase_range": 0.0,
		"retaliation_target_id": -1,
		"attack_autonomous": false,
		"combat_leash_origin": position,
		"combat_resume": {},
		"combat_destination": null,
		"facing": 0,
		"movement_facing": 0,
		"desired_facing": 0,
		"action_facing": 0,
		"anim": 0.0,
		"anim_state": AnimationController.IDLE,
		"animation_events_fired": {},
		"connection_mask": 0,
		"connection_revision": 0,
		"victory_objective_id": -1,
		"source_unit_id": int(source.get("unit_id", stats.get("unit_id", -1))),
		"unit_lineage": [int(source.get("unit_id", stats.get("unit_id", -1)))],
		"display_graphic_id": int(source.get("graphics", {}).get("idle", -1)),
		"death_phase": "alive",
		"death_elapsed": 0.0,
		"death_duration": world.building_death_animation_duration(source),
		"removed": false,
		"rally_point": position,
		"components": components,
	}
	world.apply_archetype_identity(building, kind)
	world.configure_harvestable_building(building, completed)
	building["components"]["production"]["queue"] = production_queue
	world.apply_technology_state_to_entity(building, team)
	world.sync_building_age_presentation(building)
	world.configure_entity_combat_awareness(building)
	EntityComponents.sync_dynamic(building)
	world.buildings.append(building)
	world.buildings_by_id[id] = building
	world.mark_combat_roster_dirty()
	world.track_conquest_entity(building)
	if kind == "town_center" and completed:
		for observer_team_value in world.player_registry.allied_teams(team):
			var observer_team := int(observer_team_value)
			if observer_team != team:
				world.reveal_allied_town_centers(observer_team, team)
	world.production_system.register_building(id)
	var spatial_half_size: Vector2 = footprint.get("half_size", Vector2.ONE * float(building["footprint_radius"]))
	world.spatial_index.insert(building, position, spatial_half_size.length(), "obstacle")
	world.register_building_victory_objective(building)
	if completed:
		world.activate_building_completion(building)
	if not world.is_bulk_loading():
		world.refresh_building_connectivity()
		world.sync_building_navigation_occupancy(building)
		world.update_fog_of_war()
	world.emit_domain_event("entity_created", {
		"entity_id": int(building["id"]),
		"entity_category": "building",
		"kind": kind,
		"team": team,
		"completed": completed,
	})
	return building
