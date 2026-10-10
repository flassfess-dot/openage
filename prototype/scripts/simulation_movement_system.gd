class_name RoRSimulationMovementSystem
extends RefCounted

const NavigationKnowledge := preload("res://scripts/navigation_knowledge.gd")

const Coordinates := preload("res://scripts/coordinates.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const MobileCollision := preload("res://scripts/mobile_collision.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const StuckRecovery := preload("res://scripts/stuck_recovery.gd")

var knowledge := NavigationKnowledge.new()

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func move_unit(unit: Dictionary, delta: float) -> bool:
	# Resolve the weak owner once for the complete hot-path update. Going through
	# the property for every movement query performs dozens of WeakRef lookups per
	# unit and becomes measurable for large formations.
	var simulation_world = world
	var probe: Variant = simulation_world.tick_pipeline.performance_probe
	var movement_phase_started := Time.get_ticks_usec() if probe != null else 0
	var planner = knowledge.planner(simulation_world, int(unit.get("team", 0)))
	var old_revision := int(unit.get("path_knowledge_revision", planner.grid.revision))
	if old_revision != planner.grid.revision and not unit.get("path", []).is_empty():
		var changed_region: Variant = planner.grid.change_region_since(old_revision)
		var segment_bounds := Rect2(Vector2(unit["pos"]), Vector2.ZERO).expand(Vector2(unit["target"])).grow(float(unit["footprint_radius"]) + 1.0)
		if changed_region == null or segment_bounds.intersects(changed_region):
			if planner.direct_cell_path(Vector2i(Vector2(unit["pos"]).floor()), Vector2i(Vector2(unit["target"]).floor()), String(unit["movement_domain"]), int(unit["terrain_restriction"]), float(unit["footprint_radius"])).is_empty():
				assign_unit_destination(unit, unit["destination"], false)
		world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
	var difference: Vector2 = unit["target"] - unit["pos"]
	if difference.length_squared() < 0.001225:
		var arrival_displacement := difference
		world.set_entity_field(unit, "pos", unit["target"])
		if simulation_world.terrain_elevation.nonzero_vertex_count > 0:
			world.set_entity_field(unit, "elevation", simulation_world.elevation_at(unit["pos"]))
		elif float(unit["elevation"]) != 0.0:
			world.set_entity_field(unit, "elevation", 0.0)
		world.set_entity_field(unit, "actual_velocity", arrival_displacement / delta if delta > 0.0 else Vector2.ZERO)
		if arrival_displacement.length_squared() > 0.000001:
			var arrival_facing := facing_for_vector(arrival_displacement)
			world.set_entity_field(unit, "movement_facing", arrival_facing)
			world.set_entity_field(unit, "desired_facing", arrival_facing)
			world.set_entity_field(unit, "facing", arrival_facing)
		var path: Array = unit.get("path", [])
		var next_index := int(unit.get("path_index", 0)) + 1
		if next_index < path.size():
			StuckRecovery.reset(unit)
			world.set_entity_field(unit, "path_index", next_index)
			world.set_entity_field(unit, "target", path[next_index])
			world.set_entity_field(unit, "path_knowledge_revision", -1)
			world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
			if probe != null:
				simulation_world.movement_arrival_microseconds += Time.get_ticks_usec() - movement_phase_started
			return true
		world.set_entity_field(unit, "path", [])
		world.set_entity_field(unit, "path_index", 0)
		StuckRecovery.reset(unit)
		if unit["task"] in ["move", "attack_move"]:
			if simulation_world.destination_reservations.is_occupied(unit):
				world.set_entity_field(unit, "task", "idle")
				world.complete_entity_order(unit, "destination_reached")
				restore_formation_facing(unit)
			else:
				assign_unit_destination(unit, unit["reserved_destination"], false)
		elif unit["task"] in ["attack", "gather"]:
			world.transition_entity_order(unit, OrderPipeline.FACE_TARGET)
		if probe != null:
			simulation_world.movement_arrival_microseconds += Time.get_ticks_usec() - movement_phase_started
		return false

	var start_position: Vector2 = unit["pos"]
	var unit_id := int(unit["id"])
	var shared_motion_requested := bool(unit["formation_shared_motion"])
	var open_envelope: Variant = null
	if shared_motion_requested or not simulation_world.open_movement_envelopes_by_id.is_empty():
		open_envelope = simulation_world.open_movement_envelopes_by_id.get(unit_id)
	if open_envelope != null and int(open_envelope.get("grid_revision", -1)) != simulation_world.navigation_grid.revision:
		if not _envelope_survives_grid_change(open_envelope):
			simulation_world.open_movement_envelopes_by_id.erase(unit_id)
			open_envelope = null
	var shared_motion := shared_motion_requested and open_envelope != null
	var native_movement: bool = not shared_motion and open_envelope == null and simulation_world.pathfinder.has_native_movement_for(unit_id)
	if shared_motion and bool(unit["formation_shared_isolated"]):
		simulation_world.movement_neighbor_buffer.clear()
		if probe != null:
			probe.increment("movement.shared_formation_units")
			probe.increment("movement.isolated_shared_formation_units")
	elif shared_motion:
		var search_radius: float = simulation_world.spatial_index.movement_neighbor_radius(unit)
		simulation_world.spatial_index.query_external_neighbors_into(unit, search_radius, int(unit["formation_group_id"]), simulation_world.movement_neighbor_buffer)
		if probe != null:
			probe.increment("movement.shared_formation_units")
	elif native_movement:
		pass
	else:
		var search_radius: float = simulation_world.spatial_index.movement_neighbor_radius(unit)
		simulation_world.spatial_index.query_neighbors_into(unit, search_radius, "unit", simulation_world.movement_neighbor_buffer)
	if probe != null:
		simulation_world.movement_neighbor_query_microseconds += Time.get_ticks_usec() - movement_phase_started
		movement_phase_started = Time.get_ticks_usec()
	var steering_target: Vector2 = unit.get("formation_steering_target", unit["target"]) if open_envelope != null else unit["target"]
	var movement_reason := ""
	if shared_motion and bool(unit["formation_shared_isolated"]):
		LocalMovement.calculate_shared_translation_into(unit, steering_target)
	elif native_movement:
		var native_result: Vector4 = simulation_world.pathfinder.calculate_native_movement(unit, unit["target"], delta)
		var native_state := roundi(native_result.z)
		var native_difference: Vector2 = unit["target"] - unit["pos"]
		var native_speed := maxf(0.0, float(unit["speed"]) * float(unit["cohesion_speed_scale"]))
		world.set_entity_field(unit, "desired_velocity", native_difference.normalized() * native_speed if native_difference.length_squared() > 0.000001 else Vector2.ZERO)
		world.set_entity_field(unit, "actual_velocity", Vector2(native_result.x, native_result.y))
		if native_state == 1:
			movement_reason = "local_obstacle"
		elif native_state == 2:
			movement_reason = "local_blocked"
		simulation_world.movement_native_unit_updates += 1
		simulation_world.movement_native_neighbor_candidates += maxi(0, roundi(native_result.w))
	else:
		movement_reason = LocalMovement.calculate_runtime_unit_into(unit, steering_target, simulation_world.movement_neighbor_buffer, simulation_world.navigation_grid, delta, open_envelope)
	if movement_reason == "local_blocked":
		var escape_velocity := _escape_invalid_footprint(unit, delta)
		if escape_velocity.length_squared() > 0.000001:
			world.set_entity_field(unit, "actual_velocity", escape_velocity)
			movement_reason = "escaping_invalid_footprint"
	if probe != null:
		simulation_world.movement_local_calculation_microseconds += Time.get_ticks_usec() - movement_phase_started
		movement_phase_started = Time.get_ticks_usec()
	if shared_motion and not bool(unit["formation_shared_isolated"]):
		world.set_entity_field(unit, "actual_velocity", MobileCollision.constrain(unit, unit["actual_velocity"], simulation_world.movement_neighbor_buffer, delta))
		if not simulation_world.navigation_grid.is_position_walkable_for(Vector2(unit["pos"]) + Vector2(unit["actual_velocity"]) * delta, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])):
			world.set_entity_field(unit, "actual_velocity", Vector2.ZERO)
	if Vector2(unit["desired_velocity"]).length_squared() > 0.000001:
		world.set_entity_field(unit, "desired_facing", facing_for_vector(unit["desired_velocity"]))
	if movement_reason != "":
		world.set_entity_field(unit, "diagnostic_reason", movement_reason)
	var step: Vector2 = unit["actual_velocity"] * delta
	if step.length_squared() >= difference.length_squared() and step.dot(difference) > 0.0:
		world.set_entity_field(unit, "pos", unit["target"])
	else:
		world.set_entity_field(unit, "pos", unit["pos"] + (step))
	var position: Vector2 = unit["pos"]
	if position.x < 0.5 or position.y < 0.5 or position.x > float(simulation_world.map_size.x) - 0.5 or position.y > float(simulation_world.map_size.y) - 0.5:
		world.set_entity_field(unit, "pos", Coordinates.clamp_world(position, simulation_world.map_size))
	if simulation_world.terrain_elevation.nonzero_vertex_count > 0:
		world.set_entity_field(unit, "elevation", simulation_world.elevation_at(unit["pos"]))
	elif float(unit["elevation"]) != 0.0:
		world.set_entity_field(unit, "elevation", 0.0)
	var actual_displacement: Vector2 = unit["pos"] - start_position
	world.set_entity_field(unit, "actual_velocity", actual_displacement / delta if delta > 0.0 else Vector2.ZERO)
	var actual_displacement_squared := actual_displacement.length_squared()
	if actual_displacement_squared > 0.000001:
		var movement_facing := facing_for_vector(actual_displacement)
		world.set_entity_field(unit, "movement_facing", movement_facing)
		world.set_entity_field(unit, "facing", movement_facing)
	var recovery_action := StuckRecovery.update_route_progress(unit)
	match recovery_action:
		"local_repath":
			assign_unit_destination(unit, unit["destination"], false)
		"global_repath":
			simulation_world.pathfinder.clear_route_cache()
			assign_unit_destination(unit, unit["destination"], false)
		"stop":
			# Release work and formation reservations as well as movement slots;
			# an abandoned approach must not block every following worker.
			if String(unit["task"]) == "board":
				world.set_entity_field(unit, "task", "idle")
				stop_unit_motion(unit, false)
				world.complete_entity_order(unit, "stuck")
			else:
				simulation_world.halt_unit(unit, "stuck_stopped_nearest_valid")
			world.set_entity_field(unit, "diagnostic_reason", "stuck_stopped_nearest_valid")
			world.set_entity_field(unit, "formation_shared_motion", false)
			world.set_entity_field(unit, "formation_slot_mode", "released")
			world.set_entity_field(unit, "formation_group_id", -1)
			world.set_entity_field(unit, "formation_home", null)
			if probe != null:
				simulation_world.movement_integration_microseconds += Time.get_ticks_usec() - movement_phase_started
			return false
	if probe != null:
		simulation_world.movement_integration_microseconds += Time.get_ticks_usec() - movement_phase_started
	return true


# Legacy saves can contain a ship whose centre is legal but whose hull
# overlaps the shore. Permit a gradual retreat only through already-overlapped
# cells; this cannot cross a new wall, terrain boundary or mobile obstacle.
func _escape_invalid_footprint(unit: Dictionary, delta: float) -> Vector2:
	var grid = world.navigation_grid
	var origin := Vector2(unit["pos"])
	var radius := float(unit["footprint_radius"])
	var domain := String(unit["movement_domain"])
	var restriction := int(unit["terrain_restriction"])
	if not grid.is_position_walkable_for(origin, 0.0, domain, restriction) or grid.is_position_walkable_for(origin, radius, domain, restriction):
		return Vector2.ZERO
	var offsets := [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]
	var existing: Dictionary = {}
	for offset in offsets:
		var cell := Vector2i((origin + offset).floor())
		if not grid.is_walkable_for(cell, domain, restriction): existing[cell] = true
	var difference := Vector2(unit["target"]) - origin
	var velocity := difference.normalized() * minf(float(unit["speed"]), difference.length() / maxf(0.0001, delta))
	var neighbors: Array = world.query_units_near(origin, radius + 2.0).filter(func(other): return int(other["id"]) != int(unit["id"]))
	velocity = MobileCollision.constrain(unit, velocity, neighbors, delta)
	var next := origin + velocity * delta
	if not grid.is_position_walkable_for(next, 0.0, domain, restriction): return Vector2.ZERO
	for offset in offsets:
		var cell := Vector2i((next + offset).floor())
		if not grid.is_walkable_for(cell, domain, restriction) and not existing.has(cell): return Vector2.ZERO
	return velocity


func face_unit_toward(unit: Dictionary, target: Vector2) -> void:
	var difference: Vector2 = target - unit["pos"]
	if difference.length_squared() > 0.0001:
		var action_facing := facing_for_vector(difference)
		world.set_entity_field(unit, "desired_facing", action_facing)
		world.set_entity_field(unit, "action_facing", action_facing)
		world.set_entity_field(unit, "facing", action_facing)


func restore_formation_facing(unit: Dictionary) -> void:
	var forward: Vector2 = unit.get("formation_forward", Vector2.ZERO)
	if forward.length_squared() > 0.0001:
		var formation_front := int(unit.get("formation_facing", facing_for_vector(forward)))
		world.set_entity_field(unit, "desired_facing", formation_front)
		world.set_entity_field(unit, "action_facing", formation_front)
		world.set_entity_field(unit, "facing", formation_front)


func facing_for_vector(direction: Vector2) -> int:
	return FacingConvention.logical_for_world(direction)


func assign_command_move(selected: Array, target: Vector2) -> bool:
	var resolved_count := 0
	for unit in selected:
		world.conversion_system.cancel(unit, "new_order")
		world.healing_system.cancel(unit, "new_order")
		if world.entity_is_worker(unit):
			world.worker_role_system.clear(unit)
			world.set_entity_field(unit, "pending_hunt_target_id", -1)
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		world.set_entity_field(unit, "gather_stage", "none")
		world.set_entity_field(unit, "resource_id", -1)
		world.set_entity_field(unit, "target_building_id", -1)
		world.set_entity_field(unit, "task", "move")
		world.set_entity_field(unit, "target_id", -1)
		world.clear_combat_intent(unit)
		world.begin_entity_order(unit, "move", -1, target, false)
	# Release the complete selection before assigning new endpoints so obsolete
	# slots cannot fragment a mass command.
	for unit in selected:
		world.destination_reservations.release(int(unit["id"]))
	var reserved_by_id: Dictionary = {}
	for unit in selected:
		var requested := Coordinates.clamp_world(target, world.map_size)
		var reserved: Vector2 = world.destination_reservations.reserve(int(unit["id"]), requested, float(unit.get("footprint_radius", 0.3)), knowledge.planner(world, int(unit.get("team", 0))).grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
		world.set_entity_field(unit, "reserved_destination", reserved)
		reserved_by_id[int(unit["id"])] = reserved
	var prevalidated_direct := _group_move_envelope_is_open(selected, reserved_by_id)
	var prepared: Array = []
	if not prevalidated_direct and selected.size() >= 4 and world.task_coordinator.is_enabled("navigation_paths"):
		var planner = knowledge.planner(world, int(selected[0].get("team", 0)))
		var same_planner := true
		var requests: Array = []
		for unit in selected:
			if knowledge.planner(world, int(unit.get("team", 0))) != planner:
				same_planner = false
				break
			requests.append({"entity_id": int(unit["id"]), "start": unit["pos"], "goal": Vector2(reserved_by_id[int(unit["id"])]), "domain": String(unit.get("movement_domain", "land")), "restriction": int(unit.get("terrain_restriction", -1)), "clearance": float(unit.get("footprint_radius", 0.3)), "purpose": "replan" if not unit.get("path", []).is_empty() else String(unit.get("task", "move"))})
		if same_planner:
			prepared = world.navigation_service.request_paths(requests, planner, world.task_coordinator)
	var selected_index := 0
	for unit in selected:
		var prepared_result: Dictionary = prepared[selected_index] if not prepared.is_empty() else {}
		selected_index += 1
		if not assign_unit_destination(unit, Vector2(reserved_by_id[int(unit["id"])]), false, prevalidated_direct, prepared_result):
			world.complete_entity_order(unit, "no_path")
		else:
			resolved_count += 1
	return resolved_count > 0


func _group_move_envelope_is_open(selected: Array, reserved_by_id: Dictionary) -> bool:
	if selected.size() < 2 or reserved_by_id.size() != selected.size():
		return false
	var movement_domain := String(selected[0].get("movement_domain", "land"))
	var restriction_id := int(selected[0].get("terrain_restriction", -1))
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var maximum_radius := 0.0
	for unit in selected:
		if String(unit.get("movement_domain", "land")) != movement_domain or int(unit.get("terrain_restriction", -1)) != restriction_id:
			return false
		var destination: Vector2 = reserved_by_id[int(unit["id"])]
		for position in [Vector2(unit["pos"]), destination]:
			minimum = Vector2(minf(minimum.x, position.x), minf(minimum.y, position.y))
			maximum = Vector2(maxf(maximum.x, position.x), maxf(maximum.y, position.y))
		maximum_radius = maxf(maximum_radius, float(unit.get("footprint_radius", 0.3)))
	return world.navigation_grid.is_world_rect_walkable_for(minimum, maximum, maximum_radius, movement_domain, restriction_id)


func _envelope_survives_grid_change(open_envelope: Dictionary) -> bool:
	var envelope_revision := int(open_envelope.get("grid_revision", -1))
	var region: Variant = world.navigation_grid.change_region_since(envelope_revision)
	if region == null:
		return false
	var changed_region: Rect2 = region
	if changed_region.has_area():
		var margin := 3.0
		var minimum := Vector2(open_envelope.get("minimum", Vector2.ZERO))
		var maximum := Vector2(open_envelope.get("maximum", Vector2.ZERO))
		var envelope_rect := Rect2(minimum - Vector2.ONE * margin, (maximum - minimum) + Vector2.ONE * 2.0 * margin)
		if envelope_rect.intersects(changed_region):
			return false
	open_envelope["grid_revision"] = world.navigation_grid.revision
	return true


func assign_command_attack_move(selected: Array, target: Vector2) -> bool:
	var resolved_count := 0
	for unit in selected:
		world.conversion_system.cancel(unit, "new_order")
		world.healing_system.cancel(unit, "new_order")
		if world.entity_is_worker(unit):
			world.worker_role_system.clear(unit)
			world.set_entity_field(unit, "pending_hunt_target_id", -1)
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		world.set_entity_field(unit, "gather_stage", "none")
		world.set_entity_field(unit, "resource_id", -1)
		world.set_entity_field(unit, "target_building_id", -1)
		world.set_entity_field(unit, "task", "attack_move")
		world.set_entity_field(unit, "target_id", -1)
		world.clear_combat_intent(unit)
		world.set_entity_field(unit, "attack_move_destination", target)
		world.begin_entity_order(unit, "attack_move", -1, target, false)
		if not assign_unit_destination(unit, target):
			world.set_entity_field(unit, "task", "idle")
			world.complete_entity_order(unit, "no_path")
		else:
			resolved_count += 1
	return resolved_count > 0


func assign_unit_destination(unit: Dictionary, destination: Vector2, reserve_destination: bool = true, prevalidated_direct: bool = false, prepared_result: Dictionary = {}) -> bool:
	world.erase_entity_field(unit, "formation_steering_target")
	unit.erase("_formation_path_cache")
	world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	if not OrderPipeline.is_active(unit):
		world.begin_entity_order(unit, String(unit.get("task", "move")), int(unit.get("target_id", -1)), destination, String(unit.get("task", "")) in ["attack", "gather"])
	world.transition_entity_order(unit, OrderPipeline.PLAN_PATH)
	var planner = knowledge.planner(world, int(unit.get("team", 0)))
	var clamped_destination := Coordinates.clamp_world(destination, world.map_size)
	if reserve_destination:
		clamped_destination = world.destination_reservations.reserve(int(unit["id"]), clamped_destination, float(unit.get("footprint_radius", 0.3)), planner.grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
		world.set_entity_field(unit, "reserved_destination", clamped_destination)
	world.set_entity_field(unit, "destination", clamped_destination)
	var path_purpose := "replan" if not unit.get("path", []).is_empty() else String(unit.get("task", "move"))
	var path_result: Dictionary
	if not prepared_result.is_empty():
		path_result = prepared_result
	elif prevalidated_direct:
		path_result = world.navigation_service.register_prevalidated_direct_path(int(unit["id"]), unit["pos"], unit["destination"], String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), path_purpose, float(unit.get("footprint_radius", 0.3)))
	else:
		path_result = world.navigation_service.request_path(int(unit["id"]), unit["pos"], unit["destination"], String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), path_purpose, float(unit.get("footprint_radius", 0.3)), planner)
	world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
	world.set_entity_field(unit, "path_request_id", int(path_result["request_id"]))
	world.set_entity_field(unit, "path_status", String(path_result["status"]))
	world.set_entity_field(unit, "path_grid_revision", int(path_result["grid_revision"]))
	world.set_entity_field(unit, "path", path_result["path"])
	world.set_entity_field(unit, "path_index", 0)
	if unit["path"].is_empty():
		world.set_entity_field(unit, "target", unit["pos"])
		if Vector2(unit["pos"]).distance_squared_to(clamped_destination) <= 0.001225:
			world.set_entity_field(unit, "path_status", "arrived")
			if String(unit["task"]) in ["move", "attack_move"]:
				world.set_entity_field(unit, "task", "idle")
				release_unit_destination(unit)
				world.complete_entity_order(unit, "destination_reached")
				restore_formation_facing(unit)
			else:
				world.transition_entity_order(unit, OrderPipeline.FACE_TARGET)
			return true
		# Work orders need the same terminal failure as movement orders. Leaving
		# a failed gather/build active retries A* every tick and holds its slot.
		world.halt_unit(unit, "no_path")
		world.set_entity_field(unit, "path_status", "unreachable")
		world.set_entity_field(unit, "diagnostic_reason", "no_path")
		return false
	world.set_entity_field(unit, "target", unit["path"][0])
	world.set_entity_field(unit, "diagnostic_reason", "")
	world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true


func assign_unit_waypoints(unit: Dictionary, waypoints: Array[Vector2], destination: Vector2, prevalidated_direct: bool = false, open_envelope: Dictionary = {}) -> bool:
	world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	if not OrderPipeline.is_active(unit, "move"):
		world.begin_entity_order(unit, "move", -1, destination, false)
	world.transition_entity_order(unit, OrderPipeline.PLAN_PATH)
	var planner = knowledge.planner(world, int(unit.get("team", 0)))
	var requested_destination := Coordinates.clamp_world(destination, world.map_size)
	var reserved_destination: Vector2 = world.destination_reservations.reserve(int(unit["id"]), requested_destination, float(unit.get("footprint_radius", 0.3)), planner.grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
	var direct_segments_allowed: bool = prevalidated_direct and reserved_destination.is_equal_approx(requested_destination)
	world.set_entity_field(unit, "reserved_destination", reserved_destination)
	world.set_entity_field(unit, "destination", reserved_destination)
	var targets := waypoints.duplicate()
	if targets.is_empty() or targets[targets.size() - 1].distance_squared_to(reserved_destination) > 0.0001:
		targets.append(reserved_destination)
	else:
		targets[targets.size() - 1] = reserved_destination
	var combined: Array[Vector2] = []
	var cursor: Vector2 = unit["pos"]
	for target in targets:
		var clamped_target := Coordinates.clamp_world(target, world.map_size)
		var path_result: Dictionary
		if direct_segments_allowed and cursor.distance_squared_to(clamped_target) > 0.0001:
			path_result = world.navigation_service.register_prevalidated_direct_path(int(unit["id"]), cursor, clamped_target, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment", float(unit.get("footprint_radius", 0.3)))
		else:
			path_result = world.navigation_service.request_path(int(unit["id"]), cursor, clamped_target, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment", float(unit.get("footprint_radius", 0.3)), planner)
		world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
		world.set_entity_field(unit, "path_request_id", int(path_result["request_id"]))
		world.set_entity_field(unit, "path_status", String(path_result["status"]))
		world.set_entity_field(unit, "path_grid_revision", int(path_result["grid_revision"]))
		var segment: Array[Vector2] = path_result["path"]
		if segment.is_empty() and cursor.distance_squared_to(target) > 0.0001:
			continue
		for waypoint in segment:
			if combined.is_empty() or combined[combined.size() - 1].distance_squared_to(waypoint) > 0.0001:
				combined.append(waypoint)
		cursor = target
	world.set_entity_field(unit, "path", combined)
	world.set_entity_field(unit, "path_index", 0)
	if combined.is_empty():
		world.set_entity_field(unit, "target", unit["pos"])
		world.set_entity_field(unit, "task", "idle")
		# A member already on its slot (often the middle rider during a turn)
		# has completed the order; an empty route here is not a path failure.
		if Vector2(unit["pos"]).distance_squared_to(reserved_destination) <= 0.001225:
			world.set_entity_field(unit, "path_status", "arrived")
			world.set_entity_field(unit, "diagnostic_reason", "")
			world.complete_entity_order(unit, "destination_reached")
			restore_formation_facing(unit)
			return true
		world.set_entity_field(unit, "diagnostic_reason", "no_group_route")
		return false
	if direct_segments_allowed and bool(open_envelope.get("open", false)):
		world.open_movement_envelopes_by_id[int(unit["id"])] = open_envelope
	world.set_entity_field(unit, "target", combined[0])
	world.set_entity_field(unit, "diagnostic_reason", "group_corridor" if waypoints.size() > 1 else "")
	world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true


func ensure_navigation_destination(unit: Dictionary, destination: Vector2) -> void:
	var previous_destination: Vector2 = unit.get("destination", unit["pos"])
	if previous_destination.distance_squared_to(destination) > 0.25 or unit.get("path", []).is_empty():
		assign_unit_destination(unit, destination, false)


func stop_unit_motion(unit: Dictionary, reset_progress: bool = true) -> void:
	world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	release_unit_destination(unit)
	world.set_entity_field(unit, "path", [])
	unit.erase("_formation_path_cache")
	world.erase_entity_field(unit, "formation_steering_target")
	world.set_entity_field(unit, "path_index", 0)
	world.set_entity_field(unit, "path_status", "idle")
	world.set_entity_field(unit, "target", unit["pos"])
	world.set_entity_field(unit, "destination", unit["pos"])
	world.set_entity_field(unit, "actual_velocity", Vector2.ZERO)
	world.set_entity_field(unit, "desired_velocity", Vector2.ZERO)
	if reset_progress:
		StuckRecovery.reset(unit)


func release_unit_destination(unit: Dictionary) -> void:
	world.destination_reservations.release(int(unit.get("id", -1)))
	world.open_movement_envelopes_by_id.erase(int(unit.get("id", -1)))
	world.set_entity_field(unit, "reserved_destination", null)
