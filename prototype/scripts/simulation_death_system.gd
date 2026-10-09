class_name RoRSimulationDeathSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const SimulationEconomySystem := preload("res://scripts/simulation_economy_system.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func death_animation_duration(kind: String) -> float:
	var spec: Dictionary = world.unit_stats(kind).get("animations", {}).get("death", {})
	return maxf(0.05, float(spec.get("frames_per_angle", 1)) * float(spec.get("frame_rate", 0.1)))


func building_death_animation_duration(source: Dictionary) -> float:
	var graphic_id := int(source.get("graphics", {}).get("death", -1))
	var graphic: Dictionary = world.graphics_catalog_data.get("graphics", {}).get(str(graphic_id), {})
	return maxf(0.05, float(graphic.get("frames_per_angle", 1)) * float(graphic.get("frame_rate", 0.1)))


func corpse_animation_duration(source: Dictionary, team: int) -> float:
	var corpse_id := int(source.get("links", {}).get("dead_unit_id", -1))
	if corpse_id < 0:
		return 0.0
	var corpse_source: Dictionary = world.object_record_by_id(corpse_id, team)
	var corpse_graphic_id := int(corpse_source.get("graphics", {}).get("idle", -1))
	var graphic: Dictionary = world.graphics_catalog_data.get("graphics", {}).get(str(corpse_graphic_id), {})
	if graphic.is_empty():
		return maxf(0.0, float(corpse_source.get("resources", {}).get("decay", 0.0)))
	return maxf(0.0, float(graphic.get("frames_per_angle", 1)) * float(graphic.get("frame_rate", 0.0)))


func begin_death(unit: Dictionary) -> void:
	if String(unit.get("death_phase", "alive")) != "alive":
		return
	world.dying_units.append(unit)
	world.transport_system.destroy_cargo(unit)
	world.conversion_system.cancel(unit, "unit_died")
	world.healing_system.cancel(unit, "unit_died")
	world.emit_domain_event("death", {
		"entity_id": int(unit.get("id", -1)),
		"entity_category": "unit",
		"kind": String(unit.get("kind", "")),
		"team": int(unit.get("team", 0)),
	})
	unit["hp"] = minf(0.0, float(unit.get("hp", 0.0)))
	world.spatial_sync_system.mark_roster_dirty()
	world.track_conquest_entity(unit)
	world.sync_unit_victory_objective(unit)
	unit["selected"] = false
	unit["task"] = "die"
	unit["target_id"] = -1
	world.release_resource_approach_slot(unit)
	world.release_building_approach_slot(unit)
	unit["resource_id"] = -1
	unit["target_building_id"] = -1
	unit["death_phase"] = "dying"
	unit["death_elapsed"] = 0.0
	unit["death_complete"] = false
	world.release_unit_destination(unit)
	OrderPipeline.clear_queued(unit)
	OrderPipeline.complete(unit, "unit_died")
	unit["formation_group_id"] = -1
	unit["formation_slot_id"] = -1
	unit["formation_slot_capacity"] = 0.0
	unit["formation_home"] = null
	unit["formation_slot_mode"] = "none"
	unit["formation_shared_motion"] = false
	unit["formation_shared_isolated"] = false
	unit["cohesion_speed_scale"] = 1.0
	unit["combat_destination"] = null
	if not bool(unit.get("population_released", false)):
		var team := int(unit.get("team", 0))
		world.economy_system.add_population_points(team, -int(unit.get("population_points_cost", int(unit.get("population_cost", 0)) * SimulationEconomySystem.POPULATION_POINT_SCALE)))
		unit["population_released"] = true
	AnimationController.update(unit, AnimationController.DIE, 0.0)
	EntityComponents.sync_dynamic(unit)


func begin_entity_death(entity: Dictionary, source_context: Dictionary = {}) -> void:
	if world.find_unit(int(entity.get("id", -1))) != null:
		if String(entity.get("death_phase", "alive")) == "alive" and world.entity_has_behavior_tag(entity, "huntable"):
			entity["killed_by_worker"] = bool(source_context.get("is_worker", false))
			entity["killer_entity_id"] = int(source_context.get("entity_id", -1))
			entity["killer_team"] = int(source_context.get("team", 0))
		begin_death(entity)
		return
	begin_building_destruction(entity)


func begin_building_destruction(building: Dictionary) -> void:
	if building == null or String(building.get("death_phase", "alive")) != "alive":
		return
	world.dying_buildings.append(building)
	world.emit_domain_event("death", {
		"entity_id": int(building.get("id", -1)),
		"entity_category": "building",
		"kind": String(building.get("kind", "")),
		"team": int(building.get("team", 0)),
	})
	world.production_system.abort_for_building_loss(int(building.get("id", -1)))
	world.deactivate_population_support(building)
	world.deactivate_building_victory_objective(building)
	if bool(building.get("harvestable", false)):
		var building_id := int(building.get("id", -1))
		world.resource_approach_slots.erase(building_id)
		for unit_value in world.get_units():
			var unit: Dictionary = unit_value
			if int(unit.get("resource_id", -1)) == building_id:
				world.finish_gather_order(unit, "resource_destroyed")
		building["resource_state"] = "destroyed"
	building["hp"] = 0.0
	world.spatial_sync_system.mark_roster_dirty()
	world.track_conquest_entity(building)
	building["state"] = "destroyed"
	building["builders"] = {}
	building["production_progress"] = 0.0
	building["death_phase"] = "dying"
	building["death_elapsed"] = 0.0
	building["removed"] = false
	EntityComponents.sync_dynamic(building)
	world.refresh_building_connectivity()
	world.sync_building_navigation_occupancy(building)


func advance_death(unit: Dictionary, delta: float) -> void:
	match String(unit.get("death_phase", "alive")):
		"dying":
			AnimationController.update(unit, AnimationController.DIE, delta)
			unit["death_elapsed"] = float(unit.get("anim", 0.0))
			if float(unit["death_elapsed"]) + 0.000001 >= float(unit.get("death_duration", 0.1)):
				unit["death_phase"] = "corpse"
				unit["death_complete"] = true
				unit["animation_events_fired"]["death_complete_frame"] = true
				unit["anim_state"] = AnimationController.DECAY
				unit["anim"] = 0.0
		"corpse":
			unit["corpse_elapsed"] = float(unit.get("corpse_elapsed", 0.0)) + maxf(0.0, delta)
			unit["anim"] = unit["corpse_elapsed"]
			if float(unit["corpse_elapsed"]) + 0.000001 >= float(unit.get("corpse_duration", 0.0)):
				unit["death_phase"] = "removed"
				unit["removed"] = true
				world.unit_removal_pending = true
	if String(unit.get("death_phase", "")) == "corpse" and world.entity_has_behavior_tag(unit, "huntable"):
		_complete_huntable_death(unit)
	EntityComponents.sync_dynamic(unit)


func _complete_huntable_death(huntable: Dictionary) -> void:
	if bool(huntable.get("huntable_death_resolved", false)):
		return
	huntable["huntable_death_resolved"] = true
	if not bool(huntable.get("killed_by_worker", false)):
		for candidate_value in world.get_units():
			var candidate: Dictionary = candidate_value
			if int(candidate.get("pending_hunt_target_id", -1)) == int(huntable.get("id", -1)):
				candidate["pending_hunt_target_id"] = -1
				if String(candidate.get("task", "idle")) == "idle":
					world.worker_role_system.clear(candidate)
		return
	var metadata: Dictionary = world.data_repository.runtime_metadata(String(huntable.get("kind", "")))
	var carcass_alias := String(metadata.get("carcass_alias", ""))
	var harvest_amount := maxi(0, int(metadata.get("harvest_amount", 0)))
	if carcass_alias.is_empty() or harvest_amount <= 0:
		return
	huntable["huntable_carcass_spawned"] = true
	var carcass: Dictionary = world.add_resource(carcass_alias, Vector2(huntable.get("pos", Vector2.ZERO)), harvest_amount)
	carcass["facing"] = int(huntable.get("facing", 0))
	carcass["decay_elapsed"] = 0.0
	world.mark_known_resource_dirty(carcass)
	carcass["origin_entity_id"] = int(huntable.get("id", -1))
	carcass["origin_source_unit_id"] = int(huntable.get("source_unit_id", -1))
	huntable["death_phase"] = "removed"
	huntable["removed"] = true
	world.unit_removal_pending = true
	var hunters: Array = []
	for candidate_value in world.get_units():
		var candidate: Dictionary = candidate_value
		if float(candidate.get("hp", 0.0)) > 0.0 and world.entity_is_worker(candidate) and int(candidate.get("pending_hunt_target_id", -1)) == int(huntable.get("id", -1)):
			hunters.append(candidate)
	if not hunters.is_empty():
		world.assign_command_gather(hunters, int(carcass["id"]))
	world.emit_domain_event("huntable_became_resource", {
		"huntable_id": int(huntable.get("id", -1)),
		"carcass_id": int(carcass["id"]),
		"carcass_kind": carcass_alias,
		"amount": harvest_amount,
	})


func advance_death_only(delta: float) -> void:
	for unit in world.dying_units:
		advance_death(unit, delta)
	for building in world.dying_buildings:
		building["death_elapsed"] = float(building.get("death_elapsed", 0.0)) + maxf(0.0, delta)
		var death_duration := float(building.get("death_duration", 0.05))
		if float(building["death_elapsed"]) + 0.000001 >= death_duration + 8.0:
			building["death_phase"] = "removed"
			building["removed"] = true
			world.building_removal_pending = true
		elif float(building["death_elapsed"]) + 0.000001 >= death_duration:
			building["death_phase"] = "ruin"
		EntityComponents.sync_dynamic(building)


func purge_removed_units() -> void:
	if world.unit_removal_pending:
		var removed_combat_unit := false
		for index in range(world.units.size() - 1, -1, -1):
			if bool(world.units[index].get("removed", false)):
				removed_combat_unit = removed_combat_unit or bool(world.units[index].get("combat_enabled", false))
				if world.entity_has_behavior_tag(world.units[index], "capturable"):
					world.capturable_units.erase(world.units[index])
				var removed_id := int(world.units[index].get("id", -1))
				world.unit_activity_registry.forget(removed_id)
				world.render_entity_projection_cache.erase(removed_id)
				world.units_by_id.erase(removed_id)
				world.units.remove_at(index)
		for index in range(world.dying_units.size() - 1, -1, -1):
			if bool(world.dying_units[index].get("removed", false)):
				world.dying_units.remove_at(index)
		world.unit_removal_pending = false
		if removed_combat_unit:
			world.mark_combat_roster_dirty()
	if world.building_removal_pending:
		var removed_combat_building := false
		for index in range(world.buildings.size() - 1, -1, -1):
			if bool(world.buildings[index].get("removed", false)):
				removed_combat_building = removed_combat_building or bool(world.buildings[index].get("combat_enabled", false))
				world.production_system.unregister_building(int(world.buildings[index].get("id", -1)))
				world.render_entity_projection_cache.erase(int(world.buildings[index].get("id", -1)))
				world.buildings_by_id.erase(int(world.buildings[index].get("id", -1)))
				world.buildings.remove_at(index)
		for index in range(world.dying_buildings.size() - 1, -1, -1):
			if bool(world.dying_buildings[index].get("removed", false)):
				world.dying_buildings.remove_at(index)
		world.building_removal_pending = false
		if removed_combat_building:
			world.mark_combat_roster_dirty()
