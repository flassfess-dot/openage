class_name RoRSimulationGatheringSystem
extends RefCounted

const Coordinates := preload("res://scripts/coordinates.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

const GATHER_UPDATE_IDLE := 0
const GATHER_UPDATE_MOVE := 1
const GATHER_UPDATE_ACTION := 2
const GATHER_UPDATE_CARRY_IDLE := 3
const GATHER_UPDATE_CARRY_MOVE := 4
const GATHER_UPDATE_MOVE_IDLE := 5

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func assign_command(selected: Array, target_id: int) -> void:
	var simulation_world = world
	for unit in selected:
		if not simulation_world.entity_is_worker(unit):
			continue
		var worker_component: Dictionary = unit.get("components", {}).get("worker", {})
		if not bool(worker_component.get("enabled", false)):
			# Compatibility workers are normalized once at the command boundary so
			# the fixed-tick path can use the canonical component without fallbacks.
			worker_component["enabled"] = true
		simulation_world.conversion_system.cancel(unit, "new_order")
		simulation_world.healing_system.cancel(unit, "new_order")
		release_resource_approach_slot(unit)
		simulation_world.release_building_approach_slot(unit)
		unit["target_building_id"] = -1
		simulation_world.destination_reservations.release(int(unit["id"]))
		unit["reserved_destination"] = null
		unit["task"] = "gather"
		unit["resource_id"] = target_id
		var resource: Variant = simulation_world.find_resource(target_id)
		if resource != null and int(resource.get("amount", 0)) > 0 and simulation_world.resource_accessible_to_team(resource, int(unit.get("team", 0))) and simulation_world.resource_allows_worker(resource, unit):
			simulation_world.worker_role_system.apply(unit, simulation_world.worker_role_system.profile_for_resource(unit, resource), false)
			unit["pending_hunt_target_id"] = -1
			OrderPipeline.begin(unit, "gather", target_id, resource["pos"], true)
			var carried_type := int(unit.get("carried_resource_type_id", -1))
			var target_type := int(resource.get("resource_type_id", -1))
			if float(unit.get("carried_amount", 0.0)) > 0.0 and carried_type != target_type:
				if not begin_resource_return(unit):
					finish_gather_order(unit, "no_dropoff")
			elif not prepare_group_gather_approach(unit, resource):
				finish_gather_order(unit, "no_approach_slot")
		else:
			finish_gather_order(unit, "incompatible_gatherer" if resource != null and not simulation_world.resource_allows_worker(resource, unit) else "resource_unavailable")


func update_gather_order(worker: Dictionary, delta: float) -> int:
	# Active units own the complete runtime schema. Compatibility fallbacks stay
	# at load and command boundaries instead of repeating catalog checks here.
	var simulation_world = world
	if not bool(worker["components"]["worker"]["enabled"]):
		finish_gather_order(worker, "not_a_worker")
		return GATHER_UPDATE_IDLE
	if String(worker["gather_stage"]) == "returning":
		return update_dropoff_order(worker, delta)

	var resource: Variant = simulation_world.find_resource(int(worker["resource_id"]))
	if resource == null or int(resource["amount"]) <= 0:
		release_resource_approach_slot(worker)
		if float(worker["carried_amount"]) > 0.0:
			begin_resource_return(worker)
			return GATHER_UPDATE_CARRY_IDLE
		if resource != null and prepare_group_gather_approach(worker, resource):
			return GATHER_UPDATE_IDLE
		finish_gather_order(worker, "resource_unavailable")
		return GATHER_UPDATE_IDLE

	var capacity := maxf(0.0, float(worker["carry_capacity"]))
	if capacity > 0.0 and float(worker["carried_amount"]) >= capacity - 0.0001:
		begin_resource_return(worker)
		return GATHER_UPDATE_CARRY_IDLE

	# A lone worker can begin as soon as the deposit is in reach. Shared work
	# uses reserved positions so workers do not harvest inside one another.
	var in_work_range: bool = _worker_in_resource_range(worker, resource)
	if not in_work_range and not worker["resource_approach_slot"] is Vector2:
		if not prepare_group_gather_approach(worker, resource):
			finish_gather_order(worker, "no_approach_slot")
			return GATHER_UPDATE_IDLE
		resource = simulation_world.find_resource(int(worker["resource_id"]))
	var slot: Variant = worker["resource_approach_slot"]
	if slot is Vector2:
		var at_slot: bool = Vector2(worker["pos"]).distance_squared_to(slot) <= 0.0144
		var reservations: Dictionary = simulation_world.resource_approach_slots.get(int(worker["resource_id"]), {})
		in_work_range = at_slot if reservations.size() > 1 else in_work_range or at_slot
	if not in_work_range:
		var approach: Vector2 = worker["resource_approach_slot"]
		worker["gather_stage"] = "approaching"
		simulation_world.ensure_navigation_destination(worker, approach)
		return GATHER_UPDATE_MOVE if simulation_world.movement_system.move_unit(worker, delta) else GATHER_UPDATE_MOVE_IDLE

	worker["gather_stage"] = "harvesting"
	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	simulation_world.movement_system.face_unit_toward(worker, resource["pos"])
	if float(worker["work"]) > 0.0:
		OrderPipeline.transition(worker, OrderPipeline.RECOVER)
		return GATHER_UPDATE_ACTION

	OrderPipeline.restart(worker)
	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	OrderPipeline.transition(worker, OrderPipeline.PERFORM_ACTION)
	gather(int(resource["id"]), worker)
	worker["work"] = maxf(0.05, float(worker["gather_interval"]))
	worker["gather_cycles"] = int(worker["gather_cycles"]) + 1
	OrderPipeline.transition(worker, OrderPipeline.RECOVER)
	if int(resource.get("amount", 0)) <= 0 or (capacity > 0.0 and float(worker.get("carried_amount", 0.0)) >= capacity - 0.0001):
		begin_resource_return(worker)
	return GATHER_UPDATE_ACTION


func _worker_in_resource_range(worker: Dictionary, resource: Dictionary) -> bool:
	# A unit can be hand-placed inside a resource's blocked navigation cell in
	# scenarios and imported maps. It must step onto a free neighbouring cell
	# before harvesting or its first loaded return trip can become trapped.
	var position: Vector2 = worker["pos"]
	var cell := Vector2i(position)
	var cell_offset := position - Vector2(cell)
	if cell == Vector2i(Vector2(resource["pos"])) or cell_offset.x < 0.12 or cell_offset.x > 0.88 or cell_offset.y < 0.12 or cell_offset.y > 0.88:
		return false
	var reach := maxf(0.5, float(resource.get("footprint_radius", 0.2))) + float(worker.get("footprint_radius", 0.3)) + 0.32
	return position.distance_squared_to(Vector2(resource["pos"])) <= reach * reach


func update_dropoff_order(worker: Dictionary, delta: float) -> int:
	var simulation_world = world
	if float(worker["carried_amount"]) <= 0.0:
		var empty_resource: Variant = simulation_world.find_resource(int(worker["resource_id"]))
		if empty_resource != null and prepare_group_gather_approach(worker, empty_resource):
			OrderPipeline.restart(worker)
			return GATHER_UPDATE_IDLE
		finish_gather_order(worker, "cycle_complete")
		return GATHER_UPDATE_IDLE

	var dropoff: Variant = simulation_world.find_building(int(worker["dropoff_id"]))
	if dropoff == null or float(dropoff["hp"]) <= 0.0:
		if not begin_resource_return(worker):
			finish_gather_order(worker, "no_dropoff")
			return GATHER_UPDATE_IDLE
		dropoff = simulation_world.find_building(int(worker["dropoff_id"]))
	var destination: Variant = worker["dropoff_position"]
	if not destination is Vector2:
		destination = dropoff_approach_position(worker, dropoff)
		worker["dropoff_position"] = destination
	if worker["pos"].distance_squared_to(destination) > 0.0144:
		simulation_world.ensure_navigation_destination(worker, destination)
		return GATHER_UPDATE_CARRY_MOVE if simulation_world.movement_system.move_unit(worker, delta) else GATHER_UPDATE_CARRY_IDLE

	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	simulation_world.movement_system.face_unit_toward(worker, dropoff["pos"])
	OrderPipeline.transition(worker, OrderPipeline.PERFORM_ACTION)
	deposit_carried_resources(worker)
	worker["deposit_cycles"] = int(worker["deposit_cycles"]) + 1
	OrderPipeline.transition(worker, OrderPipeline.RECOVER)
	var resource: Variant = simulation_world.find_resource(int(worker["resource_id"]))
	if resource != null and prepare_group_gather_approach(worker, resource):
		OrderPipeline.restart(worker)
		return GATHER_UPDATE_IDLE
	finish_gather_order(worker, "resource_depleted")
	return GATHER_UPDATE_IDLE


func gather(resource_id: int, worker: Dictionary) -> float:
	var simulation_world = world
	var resource: Variant = simulation_world.find_resource(resource_id)
	if resource == null or int(resource["amount"]) <= 0:
		return 0.0
	var capacity := maxf(0.0, float(worker["carry_capacity"]))
	var remaining_capacity := maxf(0.0, capacity - float(worker["carried_amount"]))
	if remaining_capacity <= 0.0:
		return 0.0
	var amount := minf(1.0, minf(float(resource["amount"]), remaining_capacity))
	var resource_type_id: int
	if resource.has("resource_type_id"):
		resource_type_id = int(resource["resource_type_id"])
	else:
		# Compatibility for old saves and narrow hand-written fixtures only.
		var resource_kind := String(resource.get("kind", ""))
		resource_type_id = simulation_world.resource_type_for(resource_kind, simulation_world.resource_stats(resource_kind))
	var carried_type := int(worker["carried_resource_type_id"])
	if carried_type >= 0 and carried_type != resource_type_id and float(worker["carried_amount"]) > 0.0:
		return 0.0
	var amount_before := int(resource["amount"])
	resource["amount"] = maxi(0, amount_before - int(amount))
	worker["carried_amount"] = float(worker["carried_amount"]) + amount
	worker["carried_resource_type_id"] = resource_type_id
	if simulation_world.capture_domain_events:
		simulation_world.emit_domain_event("resource_gathered", {
			"worker_id": int(worker["id"]),
			"resource_id": int(resource["id"]),
			"resource_type_id": resource_type_id,
			"amount": amount,
			"remaining": int(resource["amount"]),
			"carried": float(worker["carried_amount"]),
		})
	simulation_world.update_resource_state(resource)
	EntityComponents.sync_resource_carrier(worker)
	return amount


func deposit_carried_resources(worker: Dictionary) -> int:
	var amount := maxi(0, roundi(float(worker["carried_amount"])))
	var team := int(worker["team"])
	var resource_type_id := int(worker["carried_resource_type_id"])
	if resource_type_id >= 0:
		world.economy_system.change_resource_amount(team, resource_type_id, amount)
	if amount > 0 and world.capture_domain_events:
		world.emit_domain_event("resources_deposited", {
			"worker_id": int(worker["id"]),
			"team": team,
			"resource_type_id": resource_type_id,
			"amount": amount,
			"stockpile": world.economy_system.get_resource_amount(team, resource_type_id),
		})
	worker["carried_amount"] = 0.0
	worker["carried_resource_type_id"] = -1
	worker["dropoff_id"] = -1
	worker["dropoff_position"] = null
	EntityComponents.sync_resource_carrier(worker)
	return amount


func prepare_resource_approach(worker: Dictionary, resource: Dictionary) -> bool:
	var simulation_world = world
	worker["gather_stage"] = "approaching"
	worker["dropoff_id"] = -1
	worker["dropoff_position"] = null
	if worker.get("resource_approach_slot") is Vector2:
		return simulation_world.approach_system.resume(worker, worker["resource_approach_slot"])
	var resource_id := int(resource["id"])
	var reservations: Dictionary = simulation_world.resource_approach_slots.get(resource_id, {})
	var runtime_metadata: Dictionary = simulation_world.data_repository.runtime_metadata(String(resource.get("kind", "")))
	var maximum_gatherers := maxi(0, int(runtime_metadata.get("max_gatherers", 0)))
	if maximum_gatherers > 0 and reservations.size() >= maximum_gatherers:
		return false
	var slot: Variant = simulation_world.approach_system.assign_reachable_slot(worker, resource_approach_candidates(worker, resource, runtime_metadata), reservations, true)
	if not slot is Vector2:
		return false
	reservations[int(worker["id"])] = slot
	simulation_world.resource_approach_slots[resource_id] = reservations
	worker["resource_approach_slot"] = slot
	return true


func prepare_group_gather_approach(worker: Dictionary, requested_resource: Dictionary) -> bool:
	if int(requested_resource.get("amount", 0)) > 0 and prepare_resource_approach(worker, requested_resource):
		return true
	var neighbors: Array = []
	var requested_position := Vector2(requested_resource["pos"])
	for candidate_value in world.get_resources():
		var candidate: Dictionary = candidate_value
		if int(candidate.get("id", -1)) == int(requested_resource["id"]) or String(candidate.get("kind", "")) != String(requested_resource.get("kind", "")):
			continue
		if int(candidate.get("amount", 0)) <= 0 or requested_position.distance_squared_to(Vector2(candidate["pos"])) > 36.0:
			continue
		if not world.resource_accessible_to_team(candidate, int(worker.get("team", 0))) or not world.resource_allows_worker(candidate, worker):
			continue
		neighbors.append(candidate)
	neighbors.sort_custom(func(left: Dictionary, right: Dictionary):
		var left_distance := Vector2(worker["pos"]).distance_squared_to(Vector2(left["pos"]))
		var right_distance := Vector2(worker["pos"]).distance_squared_to(Vector2(right["pos"]))
		if not is_equal_approx(left_distance, right_distance):
			return left_distance < right_distance
		return int(left["id"]) < int(right["id"])
	)
	for candidate in neighbors:
		if not prepare_resource_approach(worker, candidate):
			continue
		worker["resource_id"] = int(candidate["id"])
		world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource(worker, candidate), false)
		OrderPipeline.begin(worker, "gather", int(candidate["id"]), candidate["pos"], true)
		return true
	return false


func resource_approach_candidates(worker: Dictionary, resource: Dictionary, runtime_metadata: Dictionary = {}) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var world_size: Vector2i = world.map_size
	if String(runtime_metadata.get("approach_mode", "perimeter")) == "interior":
		var half_size: Vector2 = resource.get("footprint", {}).get("half_size", Vector2(0.5, 0.5))
		var margin := float(worker.get("footprint_radius", 0.3)) + 0.08
		var extent := Vector2(maxf(0.0, half_size.x - margin), maxf(0.0, half_size.y - margin))
		for offset in [Vector2.ZERO, Vector2(-0.65, -0.65), Vector2(0.65, -0.65), Vector2(0.65, 0.65), Vector2(-0.65, 0.65), Vector2(0.0, -0.75), Vector2(0.75, 0.0), Vector2(0.0, 0.75), Vector2(-0.75, 0.0)]:
			result.append(Coordinates.clamp_world(Vector2(resource["pos"]) + offset * extent, world_size))
		return result
	# Navigation blocks the whole resource cell, so sprite-radius clearance alone
	# is not sufficient for a usable perimeter slot.
	var worker_radius := float(worker.get("footprint_radius", 0.3))
	var distance := maxf(float(resource.get("footprint_radius", 0.2)) + worker_radius + 0.12, 0.5 + worker_radius + 0.1)
	for slot_index in range(16):
		var angle := PI + TAU * float(slot_index) / 16.0
		result.append(Coordinates.clamp_world(Vector2(resource["pos"]) + Vector2(cos(angle), sin(angle)) * distance, world_size))
	return result


func release_resource_approach_slot(worker: Dictionary) -> void:
	var simulation_world = world
	var resource_id := int(worker.get("resource_id", -1))
	if simulation_world.resource_approach_slots.has(resource_id):
		var reservations: Dictionary = simulation_world.resource_approach_slots[resource_id]
		reservations.erase(int(worker.get("id", -1)))
		if reservations.is_empty():
			simulation_world.resource_approach_slots.erase(resource_id)
		else:
			simulation_world.resource_approach_slots[resource_id] = reservations
	worker["resource_approach_slot"] = null


func begin_resource_return(worker: Dictionary) -> bool:
	release_resource_approach_slot(worker)
	var dropoff: Variant = nearest_dropoff(worker)
	if dropoff == null:
		return false
	worker["gather_stage"] = "returning"
	worker["dropoff_id"] = int(dropoff["id"])
	worker["dropoff_position"] = dropoff_approach_position(worker, dropoff)
	world.assign_unit_destination(worker, worker["dropoff_position"], false)
	return true


func nearest_dropoff(worker: Dictionary) -> Variant:
	var drop_site_ids: Array = worker.get("components", {}).get("worker", {}).get("drop_site_ids", [])
	var carried_resource_type := int(worker.get("carried_resource_type_id", -1))
	var allowed: Dictionary = {}
	for value in drop_site_ids:
		if int(value) >= 0:
			allowed[int(value)] = true
	var nearest: Variant = null
	var nearest_distance := INF
	var nearest_id := 2147483647
	for building_value in world.get_buildings():
		var building: Dictionary = building_value
		if int(building.get("team", 0)) != int(worker.get("team", 0)) or float(building.get("hp", 0.0)) <= 0.0:
			continue
		if not dropoff_accepts_resource(building, carried_resource_type, allowed):
			continue
		var distance: float = worker["pos"].distance_squared_to(building["pos"])
		var building_id := int(building["id"])
		if (distance < nearest_distance and not is_equal_approx(distance, nearest_distance)) or (is_equal_approx(distance, nearest_distance) and building_id < nearest_id):
			nearest = building
			nearest_distance = distance
			nearest_id = building_id
	return nearest


func dropoff_accepts_resource(building: Dictionary, resource_type_id: int, worker_allowed_source_ids: Dictionary = {}) -> bool:
	if building == null or String(building.get("state", "complete")) != "complete" or float(building.get("hp", 0.0)) <= 0.0:
		return false
	var source_id := int(building.get("components", {}).get("identity", {}).get("source_unit_id", -1))
	# A task form's original drop-site list is more specific than the building's
	# generic stockpile categories (Hunter food is delivered to Storage Pit).
	if not worker_allowed_source_ids.is_empty():
		var lineage: Array = building.get("unit_lineage", [source_id])
		return lineage.any(func(value): return worker_allowed_source_ids.has(int(value)))
	var accepted_resource_ids: Array = world.data_repository.runtime_metadata(String(building.get("kind", ""))).get("accepted_resource_type_ids", [])
	if not accepted_resource_ids.is_empty():
		return accepted_resource_ids.any(func(value): return int(value) == resource_type_id)
	return world.entity_has_behavior_tag(building, "drop_site")


func assign_command_return_resources(selected: Array, target_building_id: int = -1) -> bool:
	var assigned := 0
	for worker in selected:
		if not world.entity_is_worker(worker) or float(worker.get("carried_amount", 0.0)) <= 0.0:
			continue
		if int(worker.get("worker_role_source_unit_id", -1)) < 0:
			world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, int(worker.get("carried_resource_type_id", -1))), false)
		var drop_site_ids: Array = worker.get("components", {}).get("worker", {}).get("drop_site_ids", [])
		var allowed: Dictionary = {}
		for value in drop_site_ids:
			if int(value) >= 0:
				allowed[int(value)] = true
		var dropoff: Variant = world.find_building(target_building_id) if target_building_id >= 0 else nearest_dropoff(worker)
		if dropoff == null or int(dropoff.get("team", 0)) != int(worker.get("team", 0)) or not dropoff_accepts_resource(dropoff, int(worker.get("carried_resource_type_id", -1)), allowed):
			continue
		release_resource_approach_slot(worker)
		world.release_building_approach_slot(worker)
		world.release_unit_destination(worker)
		worker["task"] = "gather"
		worker["gather_stage"] = "returning"
		worker["dropoff_id"] = int(dropoff["id"])
		worker["dropoff_position"] = dropoff_approach_position(worker, dropoff)
		OrderPipeline.begin(worker, "return_resources", int(dropoff["id"]), worker["dropoff_position"], false)
		world.assign_unit_destination(worker, worker["dropoff_position"], false)
		assigned += 1
	return assigned > 0


func dropoff_approach_position(worker: Dictionary, building: Dictionary) -> Vector2:
	var candidates: Array[Vector2] = world.building_perimeter_candidates(worker, building)
	for offset in range(candidates.size()):
		# Stable entity-derived starting slots prevent a crowd of carriers from
		# converging on the same point and deadlocking around a drop site.
		var candidate: Vector2 = candidates[posmod(int(worker.get("id", 0)) + offset, candidates.size())]
		if world.navigation_grid.is_position_walkable_for(candidate, float(worker.get("footprint_radius", 0.3)), String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1))):
			return candidate
	return Vector2(building["pos"])


func finish_gather_order(worker: Dictionary, reason: String) -> void:
	release_resource_approach_slot(worker)
	world.release_unit_destination(worker)
	worker["task"] = "idle"
	worker["resource_id"] = -1
	worker["gather_stage"] = "none"
	worker["dropoff_id"] = -1
	worker["dropoff_position"] = null
	worker["pending_hunt_target_id"] = -1
	world.worker_role_system.clear(worker)
	OrderPipeline.complete(worker, reason)
	EntityComponents.sync_dynamic(worker)


func update_resource_state(resource: Dictionary) -> void:
	var amount := int(resource.get("amount", 0))
	var maximum := maxi(1, int(resource.get("max_amount", amount)))
	var harvestable_building := bool(resource.get("harvestable", false))
	var state_key := "resource_state" if harvestable_building else "state"
	var stage_key := "resource_depletion_stage" if harvestable_building else "depletion_stage"
	var previous_state := String(resource.get(state_key, ""))
	if amount <= 0:
		resource[state_key] = "depleted"
		resource[stage_key] = 2
	elif float(amount) / float(maximum) <= 0.5:
		resource[state_key] = "low"
		resource[stage_key] = 1
	else:
		resource[state_key] = "available"
		resource[stage_key] = 0
	EntityComponents.sync_resource_amount(resource)
	if world.resource_nodes_by_id.has(int(resource.get("id", -1))):
		world.mark_known_resource_dirty(resource)
	if previous_state != "depleted" and String(resource.get(state_key, "")) == "depleted":
		if not harvestable_building:
			world.unregister_forest_resource(resource)
			world.navigation_grid.release_occupant(resource.get("footprint", {}).get("occupied_cells", []), "resource", int(resource.get("id", -1)))
		world.emit_domain_event("resource_depleted", {
			"resource_id": int(resource.get("id", -1)),
			"kind": String(resource.get("kind", "")),
			"building": harvestable_building,
		})


func advance_resource_lifecycle(delta: float) -> void:
	var expired_count := 0
	for resource in world.decaying_resource_nodes:
		if int(resource.get("amount", 0)) <= 0:
			expired_count += 1
			continue
		var decay_rate := maxf(0.0, float(resource.get("decay_rate", 0.0)))
		if decay_rate <= 0.0:
			continue
		var accumulator := float(resource.get("decay_accumulator", 0.0)) + decay_rate * maxf(0.0, delta)
		var lost := mini(int(resource.get("amount", 0)), floori(accumulator))
		resource["decay_accumulator"] = accumulator - float(lost)
		if lost <= 0:
			continue
		var amount_before := int(resource["amount"])
		resource["amount"] = maxi(0, amount_before - lost)
		# update_resource_state releases the depleted footprint incrementally.
		update_resource_state(resource)
		if world.capture_domain_events:
			world.emit_domain_event("resource_decayed", {
				"resource_id": int(resource.get("id", -1)),
				"amount": lost,
				"remaining": int(resource.get("amount", 0)),
			})
		if int(resource.get("amount", 0)) <= 0:
			expired_count += 1
	if expired_count <= 0:
		return
	var active: Array = []
	var retired_ids: Dictionary = {}
	for resource in world.decaying_resource_nodes:
		if int(resource.get("amount", 0)) > 0:
			active.append(resource)
		elif not bool(resource.get("visible_when_depleted", false)):
			retired_ids[int(resource.get("id", -1))] = resource
	world.decaying_resource_nodes = active
	if retired_ids.is_empty():
		return
	# Carcasses are invisible after depletion. Keeping every old corpse in the
	# authoritative roster makes every resource snapshot grow for the match.
	var retained_resources: Array = []
	for resource in world.resource_nodes:
		if not retired_ids.has(int(resource.get("id", -1))):
			retained_resources.append(resource)
	world.resource_nodes = retained_resources
	for resource_id_value in retired_ids.keys():
		var resource_id := int(resource_id_value)
		var retired: Dictionary = retired_ids[resource_id]
		world.mark_known_resource_dirty(retired)
		world.render_entity_projection_cache.erase(resource_id)
		world.resource_nodes_by_id.erase(resource_id)
		var position: Vector2 = retired.get("pos", Vector2.ZERO)
		var cell_index: int = floori(position.y) * world.map_size.x + floori(position.x)
		var cell_resources: Array = world.resource_nodes_by_cell.get(cell_index, [])
		cell_resources.erase(retired)
		if cell_resources.is_empty():
			world.resource_nodes_by_cell.erase(cell_index)
