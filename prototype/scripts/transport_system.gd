class_name RoRTransportSystem
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const BoardingDetour := preload("res://scripts/boarding_detour.gd")
const StuckRecovery := preload("res://scripts/stuck_recovery.gd")

const BOARDING_MARGIN: float = 1.25
const MAX_UNLOAD_DISTANCE: float = 4.5
const MAX_BOARDING_RETRIES: int = 6

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null
var embarked_units: Dictionary = {}
var last_failure: String = ""


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func reset() -> void:
	embarked_units.clear()
	last_failure = ""


func is_transport(entity: Dictionary) -> bool:
	return bool(entity.get("components", {}).get("cargo", {}).get("enabled", false))


func clear_pending_order(unit: Dictionary) -> void:
	for field in ["boarding_position", "boarding_transport_position", "boarding_navigation_revision", "boarding_failed_positions", "boarding_detour_attempts", "unload_target", "unload_approach", "unload_passenger_ids", "unload_retries", "unload_retry_ticks"]:
		unit.erase(field)


func passenger_count(transport: Dictionary) -> int:
	return transport.get("components", {}).get("cargo", {}).get("passenger_ids", []).size()


func all_embarked_units() -> Array:
	var ids: Array = embarked_units.keys()
	ids.sort_custom(func(left, right): return int(left) < int(right))
	var result: Array = []
	for id_value in ids:
		result.append(embarked_units[id_value])
	return result


func board(passengers: Array, transport: Dictionary) -> String:
	last_failure = validate_board(passengers, transport)
	if not last_failure.is_empty():
		return last_failure
	var cargo: Dictionary = transport["components"]["cargo"]
	var passenger_ids: Array = cargo.get("passenger_ids", []).duplicate()
	var ordered: Array = passengers.duplicate()
	ordered.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	for passenger_value in ordered:
		var passenger: Dictionary = passenger_value
		world.halt_unit(passenger, "board_transport")
		world.set_entity_field(passenger, "selected", false)
		world.set_entity_field(passenger, "transported_by_id", int(transport.get("id", -1)))
		world.set_entity_field(passenger, "cargo_state", "embarked")
		world.sync_unit_victory_objective(passenger)
		var passenger_id := int(passenger.get("id", -1))
		embarked_units[passenger_id] = passenger
		passenger_ids.append(passenger_id)
		_remove_active_unit(passenger_id)
		world.emit_domain_event("unit_boarded", {
			"passenger_id": passenger_id,
			"transport_id": int(transport.get("id", -1)),
			"passenger_team": int(passenger.get("team", 0)),
		})
	cargo["passenger_ids"] = passenger_ids
	cargo["count"] = passenger_ids.size()
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	return ""


func validate_board(passengers: Array, transport: Variant, require_range: bool = true) -> String:
	if transport == null or float(transport.get("hp", 0.0)) <= 0.0 or not is_transport(transport):
		return "invalid_transport"
	if passengers.is_empty():
		return "no_eligible_passengers"
	var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
	var existing: Array = cargo.get("passenger_ids", [])
	if require_range and existing.size() + passengers.size() > int(cargo.get("capacity", 0)):
		return "transport_full"
	var seen: Dictionary = {}
	for passenger_value in passengers:
		var passenger: Dictionary = passenger_value
		var passenger_id := int(passenger.get("id", -1))
		if passenger_id < 0 or seen.has(passenger_id) or embarked_units.has(passenger_id):
			return "invalid_passenger"
		seen[passenger_id] = true
		if float(passenger.get("hp", 0.0)) <= 0.0 or String(passenger.get("death_phase", "alive")) != "alive":
			return "invalid_passenger"
		var passenger_team := int(passenger.get("team", 0))
		var transport_team := int(transport.get("team", 0))
		var allied_passenger: bool = passenger_team > 0 and world.are_teams_allied(transport_team, passenger_team) and world.are_teams_allied(passenger_team, transport_team)
		var artifact: bool = passenger_team == 0 and world.entity_has_behavior_tag(passenger, "capturable")
		if passenger_team != transport_team and not (allied_passenger and bool(cargo.get("allow_allied", true))) and not (artifact and bool(cargo.get("allow_artifacts", true))):
			return "passenger_not_owned"
		var allowed_domains: Array = cargo.get("allowed_domains", ["land"])
		if String(passenger.get("movement_domain", "land")) not in allowed_domains:
			return "passenger_domain_forbidden"
		if require_range and not is_in_boarding_range(passenger, transport):
			return "passenger_not_in_range"
	return ""


func assign_board_order(passengers: Array, transport: Dictionary) -> String:
	var rejection := validate_board(passengers, transport, false)
	if not rejection.is_empty():
		return rejection
	var transport_id := int(transport["id"])
	var ordered := passengers.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	var plans: Array = []
	var ready: Array = []
	for passenger in ordered:
		if is_in_boarding_range(passenger, transport):
			ready.append(passenger)
			continue
		var approach: Variant = _boarding_approach(passenger, transport)
		if not approach is Vector2:
			return "boarding_shore_unreachable"
		plans.append({"passenger": passenger, "position": approach})
	# Resolve the whole selection before replacing any existing order.
	for passenger in ordered:
		world.halt_unit(passenger, "new_board_order")
		world.set_entity_field(passenger, "task", "board")
		world.set_entity_field(passenger, "target_id", transport_id)
		world.begin_entity_order(passenger, "board", transport_id, transport["pos"])
	for plan in plans:
		_set_boarding_approach(plan["passenger"], transport, plan["position"])
	if not ready.is_empty():
		finish_boarding_tick(ready)
	return ""


func is_in_boarding_range(passenger: Dictionary, transport: Dictionary) -> bool:
	var distance := float(passenger.get("footprint_radius", 0.3)) + float(transport.get("footprint_radius", 0.75)) + BOARDING_MARGIN
	return Vector2(passenger["pos"]).distance_squared_to(Vector2(transport["pos"])) <= (distance + 0.0001) * (distance + 0.0001)


func advance_board_order(passenger: Dictionary, delta: float, ready: Array) -> bool:
	var transport: Variant = world.find_unit(int(passenger.get("target_id", -1)))
	var rejection := validate_board([passenger], transport, false)
	if not rejection.is_empty():
		world.halt_unit(passenger, rejection)
		return false
	if is_in_boarding_range(passenger, transport):
		world.transition_entity_order(passenger, OrderPipeline.PERFORM_ACTION)
		ready.append(passenger)
		return false
	var approach: Variant = passenger.get("boarding_position")
	var ship_moved := Vector2(passenger.get("boarding_transport_position", transport["pos"])).distance_squared_to(Vector2(transport["pos"])) > 0.0625
	var approach_blocked := not approach is Vector2
	if not approach_blocked and int(passenger.get("boarding_navigation_revision", -1)) != world.navigation_grid.revision:
		approach_blocked = not world.navigation_grid.is_position_walkable_for(approach, float(passenger["footprint_radius"]), String(passenger["movement_domain"]), int(passenger["terrain_restriction"]))
		world.set_entity_field(passenger, "boarding_navigation_revision", world.navigation_grid.revision)
	var reached_old_approach: bool = approach is Vector2 and passenger.get("path", []).is_empty()
	if ship_moved or approach_blocked or reached_old_approach:
		if ship_moved:
			passenger.erase("boarding_failed_positions")
		approach = _boarding_approach(passenger, transport)
		if not approach is Vector2 or not _set_boarding_approach(passenger, transport, approach):
			world.halt_unit(passenger, "boarding_shore_unreachable")
			return false
	var moving: bool = world.movement_system.move_unit(passenger, delta)
	if is_in_boarding_range(passenger, transport):
		world.transition_entity_order(passenger, OrderPipeline.PERFORM_ACTION)
		ready.append(passenger)
	elif int(passenger["stuck_ticks"]) >= StuckRecovery.STOP_TICK:
		var attempts := int(passenger.get("boarding_detour_attempts", 0)) + 1
		world.set_entity_field(passenger, "boarding_detour_attempts", attempts)
		var goal: Variant = _boarding_approach(passenger, transport, false)
		var detour: Array[Vector2] = BoardingDetour.find(world, passenger, goal) if goal is Vector2 and attempts <= MAX_BOARDING_RETRIES else []
		if not detour.is_empty() and world.assign_unit_waypoints(passenger, detour, detour.back(), true):
			world.set_entity_field(passenger, "task", "board")
			world.set_entity_field(passenger, "boarding_position", goal)
			world.begin_entity_order(passenger, "board", int(transport["id"]), transport["pos"])
			world.transition_entity_order(passenger, OrderPipeline.MOVE_INTO_RANGE)
			StuckRecovery.reset(passenger)
			return moving
		var failed: Array = passenger.get("boarding_failed_positions", [])
		failed.append(passenger["boarding_position"])
		world.set_entity_field(passenger, "boarding_failed_positions", failed)
		var alternate: Variant = _boarding_approach(passenger, transport) if failed.size() < MAX_BOARDING_RETRIES else null
		if alternate is Vector2:
			world.set_entity_field(passenger, "task", "board")
			world.begin_entity_order(passenger, "board", int(transport["id"]), transport["pos"])
			if not _set_boarding_approach(passenger, transport, alternate):
				world.halt_unit(passenger, "boarding_shore_unreachable")
		else:
			world.halt_unit(passenger, "boarding_shore_unreachable")
	return moving


func finish_boarding_tick(ready: Array) -> void:
	if ready.is_empty():
		return
	# Removing units mutates the activity registry. Embark only after its update loop.
	var by_transport: Dictionary = {}
	for passenger in ready:
		var transport_id := int(passenger["target_id"])
		if not by_transport.has(transport_id):
			by_transport[transport_id] = []
		by_transport[transport_id].append(passenger)
	var transport_ids := by_transport.keys()
	transport_ids.sort()
	for transport_id in transport_ids:
		var passengers: Array = by_transport[transport_id]
		var transport: Variant = world.find_unit(int(transport_id))
		var rejection := validate_board(passengers, transport, false)
		if rejection.is_empty():
			passengers.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
			var free_seats := maxi(0, int(transport["components"]["cargo"]["capacity"]) - passenger_count(transport))
			var entering := passengers.slice(0, free_seats)
			for passenger in passengers.slice(free_seats):
				world.stop_unit_motion(passenger)
				world.set_entity_field(passenger, "diagnostic_reason", "waiting_for_transport_space")
			if not entering.is_empty():
				board(entering, transport)
		else:
			for passenger in passengers:
				world.halt_unit(passenger, rejection)


func _set_boarding_approach(passenger: Dictionary, transport: Dictionary, approach: Vector2) -> bool:
	world.set_entity_field(passenger, "boarding_position", approach)
	world.set_entity_field(passenger, "boarding_transport_position", Vector2(transport["pos"]))
	world.set_entity_field(passenger, "boarding_navigation_revision", world.navigation_grid.revision)
	StuckRecovery.reset(passenger)
	return world.assign_unit_destination(passenger, approach, false)


func _boarding_approach(passenger: Dictionary, transport: Dictionary, avoid_failed: bool = true) -> Variant:
	var radius := float(passenger["footprint_radius"])
	var distance := radius + float(transport["footprint_radius"]) + BOARDING_MARGIN - 0.1
	var center := Vector2(transport["pos"])
	var origin := Vector2(passenger["pos"])
	var domain := String(passenger["movement_domain"])
	var restriction := int(passenger["terrain_restriction"])
	var grid = world.navigation_grid
	var component: int = grid.surface_component_id(Vector2i(origin), domain, restriction)
	var candidates: Array[Vector2] = []
	for y in range(maxi(0, floori(center.y - distance)), mini(world.map_size.y - 1, floori(center.y + distance)) + 1):
		for x in range(maxi(0, floori(center.x - distance)), mini(world.map_size.x - 1, floori(center.x + distance)) + 1):
			var cell := Vector2i(x, y)
			if grid.surface_component_id(cell, domain, restriction) != component:
				continue
			var positions: Array[Vector2] = [Vector2(cell) + Vector2(0.5, 0.5)]
			# Diagonal beaches may have a usable cell edge just inside boarding range.
			var inset := minf(0.49, radius + 0.02)
			positions.append(Vector2(clampf(center.x, x + inset, x + 1.0 - inset), clampf(center.y, y + inset, y + 1.0 - inset)))
			for position in positions:
				if position.distance_squared_to(center) <= distance * distance and grid.is_position_walkable_for(position, radius, domain, restriction):
					candidates.append(position)
	candidates.sort_custom(func(left, right):
		var left_distance := origin.distance_squared_to(left)
		var right_distance := origin.distance_squared_to(right)
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left.y < right.y or (is_equal_approx(left.y, right.y) and left.x < right.x)))
	)
	var planner = world.movement_system.knowledge.planner(world, int(passenger["team"]))
	for candidate in candidates:
		if avoid_failed and passenger.get("boarding_failed_positions", []).any(func(position): return candidate.distance_squared_to(Vector2(position)) < 0.01):
			continue
		var route: Array[Vector2] = planner.find_path(origin, candidate, domain, restriction, radius)
		if not route.is_empty() and route.back().distance_squared_to(candidate) <= 0.0144:
			return candidate
	return null


func unload(transports: Array, target: Vector2, requested_passenger_ids: Array = []) -> String:
	last_failure = ""
	if transports.is_empty():
		return "invalid_transport"
	var ordered: Array = transports.duplicate()
	ordered.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	var plans: Array = []
	var reserved: Array = []
	for transport_value in ordered:
		var transport: Dictionary = transport_value
		if float(transport.get("hp", 0.0)) <= 0.0 or not is_transport(transport):
			return "invalid_transport"
		if Vector2(transport.get("pos", Vector2.ZERO)).distance_to(target) > MAX_UNLOAD_DISTANCE + 0.0001:
			return "landing_too_far"
		var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
		var cargo_ids: Array = cargo.get("passenger_ids", [])
		var release_ids: Array = cargo_ids.duplicate()
		if not requested_passenger_ids.is_empty():
			release_ids = cargo_ids.filter(func(id): return int(id) in requested_passenger_ids)
			if release_ids.is_empty():
				return "invalid_cargo_selection"
		if release_ids.is_empty():
			return "transport_empty"
		release_ids.sort_custom(func(left, right): return int(left) < int(right))
		for passenger_id_value in release_ids:
			var passenger_id := int(passenger_id_value)
			if not embarked_units.has(passenger_id):
				return "invalid_cargo_state"
			var passenger: Dictionary = embarked_units[passenger_id]
			var landing: Variant = _landing_position(transport, passenger, target, reserved)
			if not landing is Vector2:
				return "landing_blocked"
			plans.append({"transport": transport, "passenger": passenger, "position": landing})
			reserved.append({"position": landing, "radius": float(passenger.get("footprint_radius", 0.3))})
	for plan_value in plans:
		var plan: Dictionary = plan_value
		_restore_passenger(plan["transport"], plan["passenger"], plan["position"])
	world.rebuild_spatial_index()
	world.update_fog_of_war()
	return ""


func assign_unload_order(transports: Array, target: Vector2, requested_ids: Array = []) -> String:
	# Direct commits remain atomic; orders may travel to a reachable shoreline.
	var immediate := unload(transports, target, requested_ids)
	if immediate != "landing_too_far":
		if immediate.is_empty():
			for transport in transports:
				world.halt_unit(transport, "unloaded")
		return immediate
	var plans: Array = []
	var moorings: Array = []
	var ordered := transports.duplicate()
	ordered.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	for transport in ordered:
		if not is_transport(transport) or float(transport.get("hp", 0.0)) <= 0.0:
			return "invalid_transport"
		var ids: Array = transport["components"]["cargo"]["passenger_ids"]
		if ids.is_empty():
			return "transport_empty"
		if not requested_ids.is_empty() and not ids.any(func(id): return int(id) in requested_ids):
			return "invalid_cargo_selection"
		var approach: Variant = _unload_approach(transport, target, requested_ids, moorings)
		if not approach is Vector2:
			return "landing_shore_unreachable"
		plans.append({"transport": transport, "approach": approach})
		moorings.append({"position": approach, "radius": transport["footprint_radius"]})
	for plan in plans:
		var transport: Dictionary = plan["transport"]
		world.halt_unit(transport, "new_unload_order")
		world.set_entity_field(transport, "task", "unload")
		world.set_entity_field(transport, "unload_target", target)
		world.set_entity_field(transport, "unload_approach", plan["approach"])
		world.set_entity_field(transport, "unload_passenger_ids", requested_ids.duplicate())
		world.set_entity_field(transport, "unload_retries", 0)
		world.set_entity_field(transport, "unload_retry_ticks", 0)
		world.begin_entity_order(transport, "unload", -1, target)
		if not world.assign_unit_destination(transport, plan["approach"]):
			world.halt_unit(transport, "landing_shore_unreachable")
	return ""


func advance_unload_order(transport: Dictionary, delta: float, ready: Array) -> bool:
	if passenger_count(transport) == 0:
		world.halt_unit(transport, "transport_empty")
		return false
	var target: Vector2 = transport["unload_target"]
	if Vector2(transport["pos"]).distance_squared_to(Vector2(transport.get("unload_approach", transport["destination"]))) <= 0.001225:
		world.stop_unit_motion(transport)
		var wait := int(transport.get("unload_retry_ticks", 0))
		if wait > 0:
			world.set_entity_field(transport, "unload_retry_ticks", wait - 1)
		else:
			ready.append(transport)
		return false
	return world.movement_system.move_unit(transport, delta)


func finish_unloading_tick(ready: Array) -> void:
	# Restoring passengers changes the activity registry, just like boarding.
	for transport in ready:
		var result := unload([transport], transport["unload_target"], transport.get("unload_passenger_ids", []))
		if result.is_empty():
			world.halt_unit(transport, "unloaded")
		elif result == "landing_blocked" and int(transport.get("unload_retries", 0)) < MAX_BOARDING_RETRIES:
			world.set_entity_field(transport, "unload_retries", int(transport.get("unload_retries", 0)) + 1)
			world.set_entity_field(transport, "unload_retry_ticks", 20)
		else:
			world.halt_unit(transport, result)


func _unload_approach(transport: Dictionary, target: Vector2, requested_ids: Array, moorings: Array = []) -> Variant:
	var radius := float(transport["footprint_radius"])
	var domain := String(transport["movement_domain"])
	var restriction := int(transport["terrain_restriction"])
	var origin := Vector2(transport["pos"])
	var planner = world.movement_system.knowledge.planner(world, int(transport["team"]))
	var start_cell := Vector2i(origin.floor())
	if planner.component_id(start_cell, domain, restriction, radius) < 0:
		# A legacy hull may overlap the shore. Resolve its clearance component
		# locally; movement can retreat out of the existing overlap gradually.
		var legal_start := Vector2i(-1, -1)
		var best := INF
		for y in range(start_cell.y - 2, start_cell.y + 3):
			for x in range(start_cell.x - 2, start_cell.x + 3):
				var cell := Vector2i(x, y)
				var distance := origin.distance_squared_to(Vector2(cell) + Vector2(0.5, 0.5))
				if distance < best and planner.grid.is_position_walkable_for(Vector2(cell) + Vector2(0.5, 0.5), radius, domain, restriction):
					best = distance
					legal_start = cell
		if legal_start.x < 0: return null
		start_cell = legal_start
	var candidates: Array[Vector2] = []
	for y in range(maxi(0, floori(target.y - MAX_UNLOAD_DISTANCE)), mini(world.map_size.y - 1, floori(target.y + MAX_UNLOAD_DISTANCE)) + 1):
		for x in range(maxi(0, floori(target.x - MAX_UNLOAD_DISTANCE)), mini(world.map_size.x - 1, floori(target.x + MAX_UNLOAD_DISTANCE)) + 1):
			var point := Vector2(x + 0.5, y + 0.5)
			if point.distance_squared_to(target) > MAX_UNLOAD_DISTANCE * MAX_UNLOAD_DISTANCE:
				continue
			if not world.navigation_grid.is_position_walkable_for(point, radius, domain, restriction):
				continue
			if not world.destination_reservations.can_reserve(int(transport["id"]), point, radius, planner.grid, domain, restriction):
				continue
			if moorings.any(func(record): return point.distance_to(record["position"]) < radius + float(record["radius"]) + 0.02):
				continue
			var neighbors: Array = world.query_units_near(point, radius + world.spatial_index.maximum_unit_radius + 0.02)
			if neighbors.any(func(unit): return int(unit["id"]) != int(transport["id"]) and point.distance_to(unit["pos"]) < radius + float(unit["footprint_radius"]) + 0.02):
				continue
			if not planner.cells_connected(start_cell, Vector2i(point.floor()), domain, restriction, radius):
				continue
			candidates.append(point)
	candidates.sort_custom(func(a, b):
		var da: float = a.distance_squared_to(target)
		var db: float = b.distance_squared_to(target)
		return da < db or (is_equal_approx(da, db) and (a.y < b.y or (is_equal_approx(a.y, b.y) and a.x < b.x)))
	)
	for point in candidates:
		var proxy := {"pos": point}
		var reserved: Array = []
		var valid := true
		for id in transport["components"]["cargo"]["passenger_ids"]:
			if not requested_ids.is_empty() and int(id) not in requested_ids: continue
			var passenger: Variant = embarked_units.get(int(id))
			if passenger == null:
				valid = false
				break
			var landing: Variant = _landing_position(proxy, passenger, target, reserved)
			if not landing is Vector2:
				valid = false
				break
			reserved.append({"position": landing, "radius": passenger["footprint_radius"]})
		if not valid: continue
		var route: Array[Vector2] = planner.find_path(origin, point, domain, restriction, radius)
		if not route.is_empty() and route.back().distance_squared_to(point) < 0.0144:
			return point
	return null


func destroy_cargo(transport: Dictionary) -> void:
	if not is_transport(transport):
		return
	var cargo: Dictionary = transport.get("components", {}).get("cargo", {})
	var ids: Array = cargo.get("passenger_ids", []).duplicate()
	ids.sort_custom(func(left, right): return int(left) < int(right))
	for passenger_id_value in ids:
		var passenger_id := int(passenger_id_value)
		var passenger: Variant = embarked_units.get(passenger_id)
		if passenger == null:
			continue
		world.set_entity_field(passenger, "hp", 0.0)
		world.track_conquest_entity(passenger)
		world.set_entity_field(passenger, "death_phase", "removed")
		world.set_entity_field(passenger, "removed", true)
		world.sync_unit_victory_objective(passenger)
		if not bool(passenger.get("population_released", false)):
			world.economy_system.add_population_points(int(passenger.get("team", 0)), -int(passenger.get("population_points_cost", int(passenger.get("population_cost", 0)) * 2)))
			world.set_entity_field(passenger, "population_released", true)
		world.entity_changes.remove(passenger_id)
		embarked_units.erase(passenger_id)
		world.emit_domain_event("cargo_destroyed", {
			"passenger_id": passenger_id,
			"transport_id": int(transport.get("id", -1)),
			"passenger_team": int(passenger.get("team", 0)),
		})
	cargo["passenger_ids"] = []
	cargo["count"] = 0


func reconcile_ownership(transport: Dictionary) -> void:
	if not is_transport(transport):
		return
	var transport_team := int(transport.get("team", 0))
	var ids: Array = transport.get("components", {}).get("cargo", {}).get("passenger_ids", []).duplicate()
	ids.sort_custom(func(left, right): return int(left) < int(right))
	for id_value in ids:
		var passenger: Variant = embarked_units.get(int(id_value))
		if passenger == null:
			continue
		var passenger_team := int(passenger.get("team", 0))
		if passenger_team == 0 or passenger_team == transport_team or (world.are_teams_allied(transport_team, passenger_team) and world.are_teams_allied(passenger_team, transport_team)):
			continue
		# Eject on the nearest valid shore; a blocked shoreline keeps the unit
		# safely embarked until a later explicit unload instead of destroying it.
		var result := unload([transport], Vector2(transport.get("pos", Vector2.ZERO)), [int(id_value)])
		if not result.is_empty():
			world.emit_domain_event("cargo_ownership_conflict", {"transport_id": int(transport.get("id", -1)), "passenger_id": int(id_value), "reason": result})


func canonical_state() -> Array:
	var result: Array = []
	for passenger_value in all_embarked_units():
		var passenger: Dictionary = passenger_value.duplicate(true)
		passenger.erase("selected")
		result.append(passenger)
	return result


func _landing_position(transport: Dictionary, passenger: Dictionary, target: Vector2, reserved: Array) -> Variant:
	var candidates: Array[Vector2] = [Coordinates.clamp_world(target, world.map_size)]
	for ring in range(1, 10):
		var distance := float(ring) * 0.5
		for offset in [Vector2(distance, 0), Vector2(0, distance), Vector2(-distance, 0), Vector2(0, -distance), Vector2(distance, distance), Vector2(-distance, distance), Vector2(-distance, -distance), Vector2(distance, -distance)]:
			candidates.append(Coordinates.clamp_world(target + offset, world.map_size))
	var radius := float(passenger.get("footprint_radius", 0.3))
	var domain := String(passenger.get("movement_domain", "land"))
	var restriction_id := int(passenger.get("terrain_restriction", -1))
	for candidate in candidates:
		if Vector2(transport.get("pos", Vector2.ZERO)).distance_to(candidate) > MAX_UNLOAD_DISTANCE + 0.0001:
			continue
		if not world.navigation_grid.is_position_walkable_for(candidate, radius, domain, restriction_id):
			continue
		if _overlaps_active_unit(candidate, radius) or _overlaps_reserved(candidate, radius, reserved):
			continue
		return candidate
	return null


func _overlaps_active_unit(position: Vector2, radius: float) -> bool:
	for unit_value in world.query_units_near(position, radius + world.spatial_index.maximum_unit_radius + 0.02):
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		var separation := radius + float(unit.get("footprint_radius", 0.3)) + 0.02
		if position.distance_squared_to(Vector2(unit.get("pos", Vector2.ZERO))) < separation * separation:
			return true
	return false


func _overlaps_reserved(position: Vector2, radius: float, reserved: Array) -> bool:
	for item_value in reserved:
		var item: Dictionary = item_value
		var separation := radius + float(item.get("radius", 0.3)) + 0.02
		if position.distance_squared_to(Vector2(item.get("position", Vector2.ZERO))) < separation * separation:
			return true
	return false


func _restore_passenger(transport: Dictionary, passenger: Dictionary, position: Vector2) -> void:
	var passenger_id := int(passenger.get("id", -1))
	var cargo: Dictionary = transport["components"]["cargo"]
	var ids: Array = cargo.get("passenger_ids", []).duplicate()
	ids.erase(passenger_id)
	cargo["passenger_ids"] = ids
	cargo["count"] = ids.size()
	embarked_units.erase(passenger_id)
	world.set_entity_field(passenger, "transported_by_id", -1)
	world.set_entity_field(passenger, "cargo_state", "deployed")
	world.set_entity_field(passenger, "pos", position)
	passenger["previous_pos"] = position
	world.set_entity_field(passenger, "target", position)
	world.set_entity_field(passenger, "destination", position)
	world.set_entity_field(passenger, "path", [])
	world.set_entity_field(passenger, "path_index", 0)
	world.set_entity_field(passenger, "path_status", "idle")
	world.set_entity_field(passenger, "reserved_destination", null)
	world.set_entity_field(passenger, "actual_velocity", Vector2.ZERO)
	world.set_entity_field(passenger, "desired_velocity", Vector2.ZERO)
	world.set_entity_field(passenger, "task", "idle")
	world.set_entity_field(passenger, "selected", false)
	world.set_entity_field(passenger, "elevation", world.elevation_at(position))
	world.restore_unit_from_transport(passenger)
	world.sync_unit_victory_objective(passenger)
	EntityComponents.sync_dynamic(passenger)
	world.emit_domain_event("unit_unloaded", {
		"passenger_id": passenger_id,
		"transport_id": int(transport.get("id", -1)),
		"passenger_team": int(passenger.get("team", 0)),
		"position": position,
	})


func _remove_active_unit(passenger_id: int) -> void:
	world.detach_unit_for_transport(passenger_id)
