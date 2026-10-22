class_name RoRSimulationMovementSystem
extends RefCounted

const NavigationKnowledge := preload("res://scripts/navigation_knowledge.gd")

const Coordinates := preload("res://scripts/coordinates.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const MobileCollision := preload("res://scripts/mobile_collision.gd")
const LocalMovement := preload("res://scripts/local_movement.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const StuckRecovery := preload("res://scripts/stuck_recovery.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")

var knowledge := NavigationKnowledge.new()
var native_integration_enabled := true
var integration_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
var collision_cursor := -1
var collision_epoch := -1
var overlap_pending: Dictionary = {}

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func settle_mobile_overlaps(active_units: Array, delta: float) -> void:
	if delta <= 0.0: return
	# Steering reads an immutable start-of-tick snapshot. Resolve residual
	# simultaneous contacts using actual positions, including idle actors from
	# old saves. Subsequent ticks visit only changed actors and unsettled pairs.
	var simulation_world = world
	var changes: Dictionary = simulation_world.entity_changes.changes_since(collision_cursor if collision_epoch == simulation_world.entity_changes.epoch else -1)
	var candidates := overlap_pending.duplicate()
	overlap_pending.clear()
	if bool(changes["full"]):
		for unit in simulation_world.units: candidates[int(unit["id"])] = unit
	else:
		for unit in active_units:
			if not bool(unit.get("formation_shared_isolated", false)): candidates[int(unit["id"])] = unit
		for id in changes["ids"]:
			if int(changes["masks"][id]) & (Journal.LIFECYCLE | Journal.POSITION):
				var unit: Variant = simulation_world.find_unit(int(id))
				if unit != null and not bool(unit.get("formation_shared_isolated", false)): candidates[int(id)] = unit
	var ids := candidates.keys()
	ids.sort()
	var pairs: Dictionary = {}
	var neighbors: Array = []
	for id in ids:
		var unit: Dictionary = candidates[id]
		if float(unit.get("hp", 0.0)) <= 0.0 or simulation_world.find_unit(id) == null: continue
		simulation_world.spatial_index.query_neighbors_into(unit, float(unit["footprint_radius"]) + 0.25, "unit", neighbors)
		for other in neighbors:
			var other_id := int(other["id"])
			if float(other.get("hp", 0.0)) <= 0.0 or String(other.get("movement_domain", "land")) != String(unit.get("movement_domain", "land")): continue
			var gap: Vector2 = unit["pos"] - other["pos"]
			var radius := float(unit["footprint_radius"]) + float(other["footprint_radius"])
			if gap.length_squared() >= (radius - 0.001) * (radius - 0.001): continue
			var pair := Vector2i(mini(id, other_id), maxi(id, other_id))
			if pairs.has(pair): continue
			pairs[pair] = true
			var distance := gap.length()
			overlap_pending[id] = unit
			overlap_pending[other_id] = other
			var normal := gap / distance if distance > 0.0001 else Vector2(0, -1 if id < other_id else 1)
			var correction := minf(radius - distance + 0.002, maxf(0.01, delta * 2.0))
			var first := _separate_mobile(unit, normal * correction * 0.5)
			var second := _separate_mobile(other, -normal * (correction - first))
			if second < correction * 0.5: _separate_mobile(unit, normal * (correction * 0.5 - second))
	collision_cursor = int(changes["revision"])
	collision_epoch = simulation_world.entity_changes.epoch


func _separate_mobile(unit: Dictionary, offset: Vector2) -> float:
	if offset.length_squared() <= 0.000001: return 0.0
	var simulation_world = world
	# A radial push can be blocked at an L-shaped forest corridor even though
	# sliding along either cell edge frees the contact. Every alternative has
	# a nonnegative projection away from the other body and still obeys terrain.
	var directions := [offset, Vector2(offset.x, 0), Vector2(0, offset.y), offset.rotated(PI/4), offset.rotated(-PI/4), offset.orthogonal(), -offset.orthogonal()]
	for direction in directions:
		if Vector2(direction).length_squared() <= 0.000001: continue
		var displacement: Vector2 = Vector2(direction).normalized() * offset.length()
		var position: Vector2 = unit["pos"] + displacement
		if position.x < 0.5 or position.y < 0.5 or position.x > simulation_world.map_size.x - 0.5 or position.y > simulation_world.map_size.y - 0.5: continue
		if not simulation_world.navigation_grid.is_position_walkable_for(position, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])): continue
		simulation_world.set_entity_field(unit, "pos", position)
		if simulation_world.terrain_elevation.nonzero_vertex_count > 0: simulation_world.set_entity_field(unit, "elevation", simulation_world.elevation_at(position))
		if String(unit["task"]) == "idle" and unit.get("path", []).is_empty():
			simulation_world.set_entity_field(unit, "target", position)
			simulation_world.set_entity_field(unit, "destination", position)
		return displacement.length()
	return 0.0


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
		simulation_world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
	_advance_formation_corner(unit, planner)
	var difference: Vector2 = unit["target"] - unit["pos"]
	if difference.length_squared() < 0.001225:
		var arrival_displacement := difference
		simulation_world.set_entity_field(unit, "pos", unit["target"])
		if simulation_world.terrain_elevation.nonzero_vertex_count > 0:
			simulation_world.set_entity_field(unit, "elevation", simulation_world.elevation_at(unit["pos"]))
		elif float(unit["elevation"]) != 0.0:
			simulation_world.set_entity_field(unit, "elevation", 0.0)
		simulation_world.set_entity_field(unit, "actual_velocity", arrival_displacement / delta if delta > 0.0 else Vector2.ZERO)
		if arrival_displacement.length_squared() > 0.000001:
			var arrival_facing := facing_for_vector(arrival_displacement)
			simulation_world.set_entity_field(unit, "movement_facing", arrival_facing)
			simulation_world.set_entity_field(unit, "desired_facing", arrival_facing)
			simulation_world.set_entity_field(unit, "facing", arrival_facing)
		var path: Array = unit.get("path", [])
		var next_index := int(unit.get("path_index", 0)) + 1
		if next_index < path.size():
			StuckRecovery.reset(unit)
			simulation_world.set_entity_field(unit, "path_index", next_index)
			simulation_world.set_entity_field(unit, "target", path[next_index])
			simulation_world.set_entity_field(unit, "path_knowledge_revision", -1)
			simulation_world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
			if probe != null:
				simulation_world.movement_arrival_microseconds += Time.get_ticks_usec() - movement_phase_started
			return true
		simulation_world.set_entity_field(unit, "path", [])
		simulation_world.set_entity_field(unit, "path_index", 0)
		StuckRecovery.reset(unit)
		if unit["task"] in ["move", "attack_move"]:
			if simulation_world.destination_reservations.is_occupied(unit):
				simulation_world.set_entity_field(unit, "task", "idle")
				simulation_world.complete_entity_order(unit, "destination_reached")
				restore_formation_facing(unit)
			else:
				assign_unit_destination(unit, unit["reserved_destination"], false)
		elif unit["task"] in ["attack", "gather"]:
			simulation_world.transition_entity_order(unit, OrderPipeline.FACE_TARGET)
		if probe != null:
			simulation_world.movement_arrival_microseconds += Time.get_ticks_usec() - movement_phase_started
		return false

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
		simulation_world.set_entity_field(unit, "desired_velocity", native_difference.normalized() * native_speed if native_difference.length_squared() > 0.000001 else Vector2.ZERO)
		simulation_world.set_entity_field(unit, "actual_velocity", Vector2(native_result.x, native_result.y))
		if native_state == 1:
			movement_reason = "local_obstacle"
		elif native_state == 2:
			movement_reason = "local_blocked"
		simulation_world.movement_native_unit_updates += 1
		simulation_world.movement_native_neighbor_candidates += maxi(0, roundi(native_result.w))
	else:
		movement_reason = LocalMovement.calculate_runtime_unit_into(unit, steering_target, simulation_world.movement_neighbor_buffer, simulation_world.navigation_grid, delta, open_envelope)
	var formation_yielding := false
	if int(unit["formation_group_id"]) >= 0 and int(unit["stuck_ticks"]) >= 4:
		if native_movement:
			simulation_world.spatial_index.query_neighbors_into(unit, simulation_world.spatial_index.movement_neighbor_radius(unit), "unit", simulation_world.movement_neighbor_buffer)
		var yielding: Variant = _formation_yield_velocity(unit, simulation_world.movement_neighbor_buffer, delta)
		if yielding is Vector2:
			simulation_world.set_entity_field(unit, "actual_velocity", yielding)
			formation_yielding = true
	if movement_reason == "local_blocked":
		var escape_velocity := _escape_invalid_footprint(unit, delta)
		if escape_velocity.length_squared() > 0.000001:
			simulation_world.set_entity_field(unit, "actual_velocity", escape_velocity)
			movement_reason = "escaping_invalid_footprint"
	if probe != null:
		simulation_world.movement_local_calculation_microseconds += Time.get_ticks_usec() - movement_phase_started
		movement_phase_started = Time.get_ticks_usec()
	if shared_motion and not bool(unit["formation_shared_isolated"]):
		simulation_world.set_entity_field(unit, "actual_velocity", MobileCollision.constrain(unit, unit["actual_velocity"], simulation_world.movement_neighbor_buffer, delta))
		if not simulation_world.navigation_grid.is_position_walkable_for(Vector2(unit["pos"]) + Vector2(unit["actual_velocity"]) * delta, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])):
			simulation_world.set_entity_field(unit, "actual_velocity", Vector2.ZERO)
	if native_integration_enabled and integration_kernel != null and integration_kernel.has_method("integrate_unit_motion"):
		assert(simulation_world.read_generation_pins == 0, "Pinned observation generation is immutable")
		var vertices: Dictionary = simulation_world.terrain_elevation.vertex_levels if simulation_world.terrain_elevation.nonzero_vertex_count > 0 else {}
		var changed_mask: int = integration_kernel.integrate_unit_motion(unit, delta, simulation_world.map_size, vertices, movement_reason)
		if changed_mask != 0: simulation_world.notify_entity_changed(unit, changed_mask)
	else:
		_integrate_unit_motion(unit, delta, movement_reason, simulation_world)
	var stop_tick := StuckRecovery.STOP_TICK
	if String(unit["task"]) == "gather" and int(unit["stuck_ticks"]) >= StuckRecovery.STOP_TICK - 1:
		# Harvesting takes longer than the ordinary 1.5-second stall window.
		# Give traffic at a shared resource/drop site time to clear, retaining
		# the same bounded local/global replans and a terminal deadlock limit.
		for neighbor in simulation_world.query_units_near(unit["pos"], float(unit["footprint_radius"]) + 2.0):
			if int(neighbor["id"]) == int(unit["id"]): continue
			if String(neighbor.get("task", "")) == "gather" and int(neighbor.get("team", 0)) == int(unit["team"]):
				stop_tick = 600
				break
	var group = simulation_world.formation_groups_view.get(int(unit["formation_group_id"]))
	if group != null:
		# Waiting in a convoy can outlast the ordinary 1.5-second stall window.
		# Initial local/global retries and later deployment checks stay bounded. Columns
		# and final deployment receive a finite size-dependent waiting budget.
		stop_tick += mini(1200, group.member_ids.size() * 20)
	var recovery_action := "" if formation_yielding else StuckRecovery.update_route_progress(unit, stop_tick)
	match recovery_action:
		"local_repath":
			if _try_formation_slot_exchange(unit, planner): pass
			elif not _try_work_traffic_detour(unit, planner):
				assign_unit_destination(unit, unit["destination"], false)
		"global_repath":
			planner.clear_route_cache()
			if _try_formation_slot_exchange(unit, planner): pass
			elif not _try_work_traffic_detour(unit, planner):
				if String(unit["task"]) != "gather" or not simulation_world.gathering_system.replan_work_approach(unit):
					assign_unit_destination(unit, unit["destination"], false)
		"stop":
			# Release work and formation reservations as well as movement slots;
			# an abandoned approach must not block every following worker.
			if String(unit["task"]) == "board":
				simulation_world.set_entity_field(unit, "task", "idle")
				stop_unit_motion(unit, false)
				simulation_world.complete_entity_order(unit, "stuck")
			else:
				simulation_world.halt_unit(unit, "stuck_stopped_nearest_valid")
				simulation_world.set_entity_field(unit, "diagnostic_reason", "stuck_stopped_nearest_valid")
			simulation_world.set_entity_field(unit, "formation_shared_motion", false)
			simulation_world.set_entity_field(unit, "formation_slot_mode", "released")
			simulation_world.set_entity_field(unit, "formation_group_id", -1)
			simulation_world.set_entity_field(unit, "formation_home", null)
			if probe != null:
				simulation_world.movement_integration_microseconds += Time.get_ticks_usec() - movement_phase_started
			return false
	if group != null and recovery_action.is_empty() and int(unit["stuck_ticks"]) in [60, 180, 360, 720]:
		# Deployment changes as earlier ranks take their homes. Retry the local
		# body detour at a bounded set of later checkpoints, not every fixed tick.
		_try_work_traffic_detour(unit, planner)
	if probe != null:
		simulation_world.movement_integration_microseconds += Time.get_ticks_usec() - movement_phase_started
	return true


func _try_work_traffic_detour(unit: Dictionary, planner) -> bool:
	if String(unit["task"]) != "gather" and not (int(unit["formation_group_id"]) >= 0 and String(unit["task"]) in ["move", "attack_move"] and Vector2(unit["pos"]).distance_squared_to(unit["destination"]) < 64.0): return false
	var simulation_world = world
	var origin := Vector2(unit["pos"])
	var destination := Vector2(unit["destination"])
	var radius := float(unit["footprint_radius"])
	var domain := String(unit["movement_domain"])
	var restriction := int(unit["terrain_restriction"])
	var neighbors: Array = simulation_world.query_units_near(origin, maxf(4.0, radius * 6.0)).filter(func(other): return int(other["id"]) != int(unit["id"]) and String(other.get("movement_domain", "land")) == domain and float(other.get("hp", 0.0)) > 0.0)
	if neighbors.is_empty(): return false
	# Static A* cannot see working units. Repeating the same route through them
	# strands loaded boats and workers. Try a bounded local detour whose whole
	# route clears the nearby bodies, without changing the gather/deposit goal.
	var candidates: Array[Vector2] = []
	var forward := (destination - origin).normalized()
	for distance in ([1.0, 2.0, 3.0, 4.0, 6.0] if int(unit["formation_group_id"]) >= 0 else [1.0, 2.0, 3.0]):
		for angle in range(8):
			candidates.append(origin + forward.rotated(TAU * float(angle) / 8.0) * float(distance) * maxf(1.0, radius * 2.0))
	candidates.sort_custom(func(a, b): return origin.distance_to(a) + a.distance_to(destination) < origin.distance_to(b) + b.distance_to(destination))
	for point in candidates:
		if not planner.is_segment_walkable(origin, point, radius, domain, restriction) or not _work_segment_clear(unit, origin, point, neighbors): continue
		var route: Array[Vector2] = planner.find_path(point, destination, domain, restriction, radius)
		if route.is_empty() or route.back().distance_squared_to(destination) > 0.0144: continue
		var cursor := point
		var clear := true
		for waypoint in route:
			if not _work_segment_clear(unit, cursor, waypoint, neighbors):
				clear = false
				break
			cursor = waypoint
		if not clear: continue
		route.push_front(point)
		var prepared: Dictionary = simulation_world.navigation_service.register_resolved_path(int(unit["id"]), origin, destination, route, domain, restriction, "work_traffic_detour", radius)
		if assign_unit_destination(unit, destination, false, false, prepared):
			StuckRecovery.reset(unit)
			simulation_world.set_entity_field(unit, "diagnostic_reason", "work_traffic_detour")
			return true
	return false


func _work_segment_clear(unit: Dictionary, start: Vector2, finish: Vector2, neighbors: Array) -> bool:
	for other in neighbors:
		var center := Vector2(other["pos"])
		var separation := float(unit["footprint_radius"]) + float(other["footprint_radius"]) + 0.03
		# A previously touching body may retreat, but must not penetrate farther.
		var minimum := minf(separation * separation, start.distance_squared_to(center))
		if center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center, start, finish)) < minimum - 0.0001: return false
	return true


func _integrate_unit_motion(unit: Dictionary, delta: float, movement_reason: String, simulation_world) -> void:
	var start_position: Vector2 = unit["pos"]
	var difference: Vector2 = unit["target"] - start_position
	if Vector2(unit["desired_velocity"]).length_squared() > 0.000001:
		simulation_world.set_entity_field(unit, "desired_facing", facing_for_vector(unit["desired_velocity"]))
	if movement_reason != "":
		simulation_world.set_entity_field(unit, "diagnostic_reason", movement_reason)
	var step: Vector2 = unit["actual_velocity"] * delta
	if step.length_squared() >= difference.length_squared() and step.dot(difference) > 0.0:
		simulation_world.set_entity_field(unit, "pos", unit["target"])
	else:
		simulation_world.set_entity_field(unit, "pos", unit["pos"] + (step))
	var position: Vector2 = unit["pos"]
	if position.x < 0.5 or position.y < 0.5 or position.x > float(simulation_world.map_size.x) - 0.5 or position.y > float(simulation_world.map_size.y) - 0.5:
		simulation_world.set_entity_field(unit, "pos", Coordinates.clamp_world(position, simulation_world.map_size))
	if simulation_world.terrain_elevation.nonzero_vertex_count > 0:
		simulation_world.set_entity_field(unit, "elevation", simulation_world.elevation_at(unit["pos"]))
	elif float(unit["elevation"]) != 0.0:
		simulation_world.set_entity_field(unit, "elevation", 0.0)
	var actual_displacement: Vector2 = unit["pos"] - start_position
	simulation_world.set_entity_field(unit, "actual_velocity", actual_displacement / delta if delta > 0.0 else Vector2.ZERO)
	var actual_displacement_squared := actual_displacement.length_squared()
	if actual_displacement_squared > 0.000001:
		var movement_facing := facing_for_vector(actual_displacement)
		simulation_world.set_entity_field(unit, "movement_facing", movement_facing)
		simulation_world.set_entity_field(unit, "facing", movement_facing)


func _advance_formation_corner(unit: Dictionary, planner) -> void:
	if int(unit["formation_group_id"]) < 0 or String(unit["task"]) not in ["move", "attack_move"]: return
	var path: Array = unit["path"]
	var next_index := int(unit["path_index"]) + 1
	if next_index >= path.size() or Vector2(unit["pos"]).distance_squared_to(unit["target"]) > 2.0 * 2.0: return
	# Intermediate gates must not require every rank to touch the same exact
	# point. Advance only when the entire swept footprint to the next leg is
	# clear; the final reserved destination still uses the precise arrival rule.
	if not planner.is_segment_walkable(unit["pos"], path[next_index], float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])): return
	if next_index == path.size() - 1 and Vector2(unit["pos"]).distance_squared_to(unit["destination"]) < 64.0:
		# Preserve an actual detour around members already standing at home.
		# Terrain visibility alone would cut the corner back through their bodies.
		var neighbors: Array = world.query_units_near(unit["pos"], 8.0 + float(unit["footprint_radius"]))
		neighbors = neighbors.filter(func(other): return int(other["id"]) != int(unit["id"]) and String(other["movement_domain"]) == String(unit["movement_domain"]))
		if not _work_segment_clear(unit, unit["pos"], path[next_index], neighbors): return
	world.set_entity_field(unit, "path_index", next_index)
	world.set_entity_field(unit, "target", path[next_index])


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
	var difference := Vector2(unit["target"]) - origin
	var velocity := difference.normalized() * minf(float(unit["speed"]), difference.length() / maxf(0.0001, delta))
	var neighbors: Array = world.query_units_near(origin, radius + 2.0).filter(func(other): return int(other["id"]) != int(unit["id"]))
	velocity = MobileCollision.constrain(unit, velocity, neighbors, delta)
	var next := origin + velocity * delta
	if not grid.is_footprint_escape_walkable_for(origin, next, radius, domain, restriction): return Vector2.ZERO
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
		# Newly explored obstacles can invalidate one optimistic work slot while
		# other positions around the known resource remain reachable.
		if String(unit["task"]) == "gather" and String(unit.get("gather_stage", "")) == "approaching" and prepared_result.is_empty():
			var resource: Variant = world.find_resource(int(unit.get("resource_id", -1)))
			if resource != null:
				world.release_resource_approach_slot(unit)
				if world.gathering_system.prepare_group_gather_approach(unit, resource):
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
	var simulation_world = world
	simulation_world.open_movement_envelopes_by_id.erase(int(unit["id"]))
	if not OrderPipeline.is_active(unit, "move"):
		simulation_world.begin_entity_order(unit, "move", -1, destination, false)
	simulation_world.transition_entity_order(unit, OrderPipeline.PLAN_PATH)
	var planner = knowledge.planner(simulation_world, int(unit.get("team", 0)))
	var requested_destination := Coordinates.clamp_world(destination, simulation_world.map_size)
	var reserved_destination: Vector2 = simulation_world.destination_reservations.reserve(int(unit["id"]), requested_destination, float(unit.get("footprint_radius", 0.3)), planner.grid, int(unit.get("formation_group_id", -1)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)))
	var direct_segments_allowed: bool = prevalidated_direct and reserved_destination.is_equal_approx(requested_destination)
	simulation_world.set_entity_field(unit, "reserved_destination", reserved_destination)
	simulation_world.set_entity_field(unit, "destination", reserved_destination)
	var targets := waypoints.duplicate()
	if targets.is_empty() or targets[targets.size() - 1].distance_squared_to(reserved_destination) > 0.0001:
		targets.append(reserved_destination)
	else:
		targets[targets.size() - 1] = reserved_destination
	var combined: Array[Vector2] = []
	var cursor: Vector2 = unit["pos"]
	for target in targets:
		var clamped_target := Coordinates.clamp_world(target, simulation_world.map_size)
		# A duplicate waypoint needs no query. An empty zero-length query would
		# otherwise overwrite the last successful segment's navigation status.
		if cursor.distance_squared_to(clamped_target) <= 0.0001:
			continue
		var path_result: Dictionary
		if direct_segments_allowed:
			path_result = simulation_world.navigation_service.register_prevalidated_direct_path(int(unit["id"]), cursor, clamped_target, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment", float(unit.get("footprint_radius", 0.3)))
		else:
			path_result = simulation_world.navigation_service.request_path(int(unit["id"]), cursor, clamped_target, String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1)), "formation_segment", float(unit.get("footprint_radius", 0.3)), planner)
		simulation_world.set_entity_field(unit, "path_knowledge_revision", planner.grid.revision)
		simulation_world.set_entity_field(unit, "path_request_id", int(path_result["request_id"]))
		simulation_world.set_entity_field(unit, "path_status", String(path_result["status"]))
		simulation_world.set_entity_field(unit, "path_grid_revision", int(path_result["grid_revision"]))
		var segment: Array[Vector2] = path_result["path"]
		if segment.is_empty():
			return _fail_group_route(unit)
		for waypoint in segment:
			if combined.is_empty() or combined[combined.size() - 1].distance_squared_to(waypoint) > 0.0001:
				combined.append(waypoint)
		# Endpoint resolution may move a blocked intermediate target. The next
		# segment must start at the actual endpoint to keep the route continuous.
		cursor = segment.back()
	# Publish only complete routes. A reachable prefix or a substituted final
	# endpoint cannot fulfil the member's reserved formation destination.
	if cursor.distance_squared_to(reserved_destination) > 0.001225:
		return _fail_group_route(unit)
	simulation_world.set_entity_field(unit, "path", combined)
	simulation_world.set_entity_field(unit, "path_index", 0)
	if combined.is_empty():
		simulation_world.set_entity_field(unit, "target", unit["pos"])
		simulation_world.set_entity_field(unit, "task", "idle")
		simulation_world.set_entity_field(unit, "path_status", "arrived")
		simulation_world.set_entity_field(unit, "diagnostic_reason", "")
		simulation_world.complete_entity_order(unit, "destination_reached")
		restore_formation_facing(unit)
		return true
	if direct_segments_allowed and bool(open_envelope.get("open", false)):
		simulation_world.open_movement_envelopes_by_id[int(unit["id"])] = open_envelope
	simulation_world.set_entity_field(unit, "target", combined[0])
	simulation_world.set_entity_field(unit, "diagnostic_reason", "group_corridor" if waypoints.size() > 1 else "")
	simulation_world.transition_entity_order(unit, OrderPipeline.MOVE_INTO_RANGE)
	return true


func _fail_group_route(unit: Dictionary) -> bool:
	world.halt_unit(unit, "no_group_route")
	world.set_entity_field(unit, "path_status", "unreachable")
	world.set_entity_field(unit, "diagnostic_reason", "no_group_route")
	return false


func ensure_navigation_destination(unit: Dictionary, destination: Vector2) -> void:
	var previous_destination: Vector2 = unit.get("destination", unit["pos"])
	if previous_destination.distance_squared_to(destination) <= 0.25 and not unit.get("path", []).is_empty():
		return
	var path: Array = unit.get("path", [])
	var path_index := int(unit.get("path_index", 0))
	if not path.is_empty() and path_index >= 0 and path_index < path.size() and int(unit.get("formation_group_id", -1)) < 0 and not bool(unit.get("formation_shared_motion", false)) and Vector2i(previous_destination.floor()) == Vector2i(destination.floor()) and Vector2i(Vector2(path.back()).floor()) == Vector2i(destination.floor()):
		var planner = knowledge.planner(world, int(unit.get("team", 0)))
		var final_segment_origin: Vector2 = unit["pos"] if path_index == path.size() - 1 else path[-2]
		if int(unit.get("path_knowledge_revision", -1)) == int(planner.grid.revision) and planner.is_segment_walkable(final_segment_origin, destination, float(unit.get("footprint_radius", 0.3)), String(unit.get("movement_domain", "land")), int(unit.get("terrain_restriction", -1))):
			# A same-cell endpoint adjustment can still cut an obstacle corner.
			# Reuse the route only when its new incoming segment remains clear.
			var updated: Array = path.duplicate()
			updated[updated.size() - 1] = destination
			world.set_entity_field(unit, "path", updated)
			world.set_entity_field(unit, "destination", destination)
			if path_index == updated.size() - 1:
				world.set_entity_field(unit, "target", destination)
			world.open_movement_envelopes_by_id.erase(int(unit["id"]))
			unit.erase("_formation_path_cache")
			return
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


func _formation_yield_velocity(unit: Dictionary, neighbors: Array, delta: float) -> Variant:
	var blocker: Variant = null
	for other in neighbors:
		if int(other["formation_group_id"]) != int(unit["formation_group_id"]) or int(other["id"]) >= int(unit["id"]) or int(other["stuck_ticks"]) < 4: continue
		if Vector2(other["pos"]).distance_to(unit["pos"]) > 1.5: continue
		if blocker == null or int(other["id"]) < int(blocker["id"]): blocker = other
	if blocker == null: return null
	var watch: Dictionary = unit.get("navigation_progress", {})
	if watch.is_empty() or int(watch.get("formation_yield_ticks", 0)) >= 1200: return null
	var backwards := (Vector2(unit["pos"]) - Vector2(unit["destination"])).normalized()
	var speed := float(unit["speed"]) * float(unit["cohesion_speed_scale"])
	for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]:
		var velocity := MobileCollision.constrain(unit, backwards.rotated(angle) * speed, neighbors, delta)
		if velocity.length_squared() < speed * speed * 0.1: continue
		var finish := Vector2(unit["pos"]) + velocity * delta
		if world.navigation_grid.is_segment_walkable_for(unit["pos"], finish, float(unit["footprint_radius"]), String(unit["movement_domain"]), int(unit["terrain_restriction"])):
			watch["formation_yield_ticks"] = int(watch.get("formation_yield_ticks", 0)) + 1
			return velocity
	return null


func _try_formation_slot_exchange(unit: Dictionary, planner) -> bool:
	var group = world.formation_groups_view.get(int(unit["formation_group_id"]))
	if group == null or unit.get("formation_home") == null or Vector2(unit["pos"]).distance_squared_to(unit["formation_home"]) > 64.0: return false
	var home := Vector2(unit["formation_home"])
	var candidates: Array = world.query_units_near(home, 8.0)
	candidates.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	for other in candidates:
		if int(other["id"]) == int(unit["id"]) or float(other["hp"]) <= 0.0 or int(other["formation_group_id"]) != group.group_id or String(other["task"]) != "idle" or String(other["kind"]) != String(unit["kind"]): continue
		if other.get("formation_home") == null or Vector2(other["pos"]).distance_squared_to(other["formation_home"]) > 0.0016: continue
		if not is_equal_approx(float(unit["footprint_radius"]), float(other["footprint_radius"])): continue
		var other_home := Vector2(other["formation_home"])
		var before := Vector2(unit["pos"]).distance_squared_to(home)
		var after := Vector2(unit["pos"]).distance_squared_to(other_home) + Vector2(other["pos"]).distance_squared_to(home)
		if after >= before - 0.01: continue
		if not planner.is_segment_walkable(other["pos"], home, float(other["footprint_radius"]), String(other["movement_domain"]), int(other["terrain_restriction"])): continue
		var blockers: Array = candidates.filter(func(actor): return int(actor["id"]) not in [int(unit["id"]), int(other["id"])] and String(actor["movement_domain"]) == String(unit["movement_domain"]))
		if not _work_segment_clear(other, other["pos"], home, blockers): continue
		# A settled outer rank can enclose an empty inner slot. Exchange only
		# identical unit kinds/radii, and only when total travel strictly falls.
		# The formation keeps every slot; both actors walk at their ordinary speed.
		world.destination_reservations.release(int(unit["id"]))
		world.destination_reservations.release(int(other["id"]))
		group.exchange_assignments(int(unit["id"]), int(other["id"]))
		for actor in [other, unit]:
			var slot: Dictionary = group.slot_for(int(actor["id"]))
			var destination := Vector2(slot["world"])
			var reserved: Vector2 = world.destination_reservations.reserve(int(actor["id"]), destination, float(actor["footprint_radius"]), planner.grid, group.group_id, String(actor["movement_domain"]), int(actor["terrain_restriction"]))
			world.set_entity_fields(actor, {"formation_home":destination, "formation_slot_id":slot["slot_id"], "formation_slot_capacity":slot["capacity_radius"], "reserved_destination":reserved, "task":group.order_kind})
			if group.order_kind == "attack_move": world.set_entity_field(actor, "attack_move_destination", destination)
			world.begin_entity_order(actor, group.order_kind, -1, destination, false)
			StuckRecovery.reset(actor)
			assign_unit_destination(actor, reserved, false)
		return true
	return false
