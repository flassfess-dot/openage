class_name RoRSimulationConstructionSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const EntityComponents := preload("res://scripts/entity_components.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func assign_command_repair(selected: Array, building_id: int) -> bool:
	var target: Variant = world.find_building(building_id)
	if target == null:
		target = world.find_unit(building_id)
	if target == null or selected.is_empty():
		return false
	for worker_value in selected:
		if not can_worker_repair(worker_value, target):
			return false
	assign_workers_to_building(selected, target, "repair")
	return selected.any(func(worker): return String(worker.get("task", "")) == "repair" and int(worker.get("target_building_id", -1)) == building_id)


func can_worker_repair(worker: Dictionary, target: Dictionary) -> bool:
	if not world.entity_is_worker(worker) or float(worker.get("hp", 0.0)) <= 0.0:
		return false
	if float(target.get("hp", 0.0)) <= 0.0 or float(target.get("hp", 0.0)) >= float(target.get("max_hp", 0.0)) - 0.0001:
		return false
	var target_team := int(target.get("team", 0))
	var worker_team := int(worker.get("team", 0))
	if target_team <= 0 or worker_team <= 0 or not world.are_teams_allied(worker_team, target_team):
		return false
	if world.find_building(int(target.get("id", -1))) != null:
		return String(target.get("state", "complete")) == "complete"
	return world.find_unit(int(target.get("id", -1))) != null and String(target.get("movement_domain", "land")) == "water"


func assign_workers_to_building(selected: Array, building: Dictionary, order_type: String) -> void:
	for worker in selected:
		if not world.entity_is_worker(worker) or (order_type == "build" and int(worker.get("team", 0)) != int(building.get("team", 0))) or (order_type == "repair" and not can_worker_repair(worker, building)):
			continue
		world.worker_role_system.apply(worker, world.worker_role_system.profile_for_task(worker, order_type), false)
		worker["pending_hunt_target_id"] = -1
		world.release_resource_approach_slot(worker)
		release_building_approach_slot(worker)
		world.release_unit_destination(worker)
		worker["resource_id"] = -1
		worker["gather_stage"] = "none"
		worker["task"] = order_type
		worker["target_building_id"] = int(building["id"])
		OrderPipeline.begin(worker, order_type, int(building["id"]), building["pos"], true)
		if not _worker_in_building_range(worker, building) and not prepare_building_approach(worker, building):
			finish_building_order(worker, "no_approach_slot")


func update_building_order(worker: Dictionary, delta: float) -> Dictionary:
	var result := {}
	advance_unit_order(worker, delta, result)
	return result


func advance_unit_order(worker: Dictionary, delta: float, result: Dictionary) -> void:
	result["moving"] = false
	result["animation_state"] = AnimationController.IDLE
	result["attack_target"] = null
	var building: Variant = world.find_building(int(worker.get("target_building_id", -1)))
	if building == null and String(worker.get("task", "")) == "repair":
		building = world.find_unit(int(worker.get("target_building_id", -1)))
	if building == null or float(building.get("hp", 0.0)) <= 0.0:
		finish_building_order(worker, "building_unavailable")
		return
	if worker["task"] == "build" and String(building.get("state", "complete")) != "foundation":
		finish_building_order(worker, "construction_complete")
		return
	if worker["task"] == "repair" and float(building["hp"]) >= float(building["max_hp"]) - 0.0001:
		finish_building_order(worker, "repair_complete")
		return
	if worker["task"] == "repair" and not can_worker_repair(worker, building):
		finish_building_order(worker, "repair_no_longer_allowed")
		return
	var in_work_range := _worker_in_building_range(worker, building)
	if not in_work_range and not worker.get("building_approach_slot") is Vector2:
		if not prepare_building_approach(worker, building):
			finish_building_order(worker, "no_approach_slot")
			return
		in_work_range = _worker_in_building_range(worker, building)
	if not in_work_range:
		var destination: Vector2 = worker["building_approach_slot"]
		world.ensure_navigation_destination(worker, destination)
		result["moving"] = world.move_unit(worker, delta)
		result["animation_state"] = AnimationController.MOVE
		return

	var was_building := String(worker.get("task", "")) == "build"
	OrderPipeline.transition(worker, OrderPipeline.FACE_TARGET)
	world.face_unit_toward(worker, building["pos"])
	OrderPipeline.transition(worker, OrderPipeline.PERFORM_ACTION)
	var worker_rate := maxf(0.01, float(worker.get("components", {}).get("worker", {}).get("work_rate", 1.0)))
	if worker["task"] == "build":
		building["builders"][int(worker["id"])] = true
		var progress_delta := delta * worker_rate / maxf(0.05, float(building.get("construction_required", 1.0)))
		building["construction_progress"] = minf(1.0, float(building.get("construction_progress", 0.0)) + progress_delta)
		building["construction_stage"] = clampi(floori(float(building["construction_progress"]) * 4.0), 0, 3)
		building["hp"] = maxf(float(building["hp"]), float(building["max_hp"]) * maxf(0.1, float(building["construction_progress"])))
		EntityComponents.sync_dynamic(building)
		if float(building["construction_progress"]) >= 1.0 - 0.000001:
			world.complete_foundation(building)
	else:
		var repair_rate := maxf(0.0, float(world.data_repository.runtime_metadata(String(building.get("kind", ""))).get("repair_hp_per_work", 10.0)))
		advance_repair(worker, building, delta * worker_rate * repair_rate)
		if float(building["hp"]) >= float(building["max_hp"]) - 0.0001:
			building["hp"] = building["max_hp"]
			finish_building_order(worker, "repair_complete")
	OrderPipeline.transition(worker, OrderPipeline.RECOVER)
	result["animation_state"] = AnimationController.BUILD if was_building else AnimationController.REPAIR


func _worker_in_building_range(worker: Dictionary, building: Dictionary) -> bool:
	var half_size := Vector2(building.get("footprint", {}).get("half_size", Vector2(0.5, 0.5)))
	var offset := Vector2(worker["pos"]) - Vector2(building["pos"])
	# Navigation's blocked footprint and mobile collision can stop a worker up
	# to roughly one cell short of an exact perimeter slot.
	var reach := float(worker.get("footprint_radius", 0.3)) + 1.0
	var outside := Vector2(maxf(0.0, absf(offset.x) - half_size.x), maxf(0.0, absf(offset.y) - half_size.y))
	return outside.length_squared() <= reach * reach


func advance_repair(worker: Dictionary, target: Dictionary, requested_hp: float) -> float:
	if not can_worker_repair(worker, target):
		return 0.0
	var repair_policy: Dictionary = world.data_repository.runtime_metadata(String(target.get("kind", "")))
	var payer := int(target.get("team", 0)) if String(repair_policy.get("repair_payer", "worker")) == "owner" else int(worker.get("team", 0))
	var source_cost: Dictionary = world.building_cost(String(target.get("kind", "")), int(target.get("team", 0))) if world.find_building(int(target.get("id", -1))) != null else world.unit_resource_cost(String(target.get("kind", "")), int(target.get("team", 0)))
	if source_cost.is_empty():
		source_cost = {1: 10}
	var cost_per_hp: Dictionary = {}
	var max_hp := maxf(1.0, float(target.get("max_hp", 1.0)))
	var cost_ratio := maxf(0.0, float(repair_policy.get("repair_cost_ratio", 0.5)))
	for resource_id_value in source_cost:
		var resource_id := int(resource_id_value)
		if resource_id in [0, 1, 2, 3] and int(source_cost[resource_id_value]) > 0:
			cost_per_hp[resource_id] = float(source_cost[resource_id_value]) * cost_ratio / max_hp
	var fractions_by_payer: Dictionary = target.get("repair_cost_fractions", {})
	var fractions: Dictionary = fractions_by_payer.get(payer, {})
	var restored_hp := minf(maxf(0.0, requested_hp), maxf(0.0, max_hp - float(target.get("hp", 0.0))))
	for resource_id_value in cost_per_hp:
		var resource_id := int(resource_id_value)
		var rate := float(cost_per_hp[resource_id])
		var stock: int = world.economy_system.get_resource_amount(payer, resource_id)
		var pending := float(fractions.get(resource_id, 0.0))
		if rate > 0.0:
			if stock <= 0:
				return 0.0
			restored_hp = minf(restored_hp, maxf(0.0, (float(stock) - pending) / rate))
	if restored_hp <= 0.000001:
		return 0.0
	var completes_target := float(target.get("hp", 0.0)) + restored_hp >= max_hp - 0.000001
	var spent: Dictionary = {}
	for resource_id_value in cost_per_hp:
		var resource_id := int(resource_id_value)
		var total := float(fractions.get(resource_id, 0.0)) + restored_hp * float(cost_per_hp[resource_id])
		var whole := ceili(total - 0.000001) if completes_target else floori(total + 0.000001)
		fractions[resource_id] = 0.0 if completes_target else maxf(0.0, total - float(whole))
		if whole > 0:
			world.economy_system.change_resource_amount(payer, resource_id, -whole)
			spent[resource_id] = whole
	fractions_by_payer[payer] = fractions
	target["repair_cost_fractions"] = fractions_by_payer
	target["hp"] = minf(max_hp, float(target.get("hp", 0.0)) + restored_hp)
	EntityComponents.sync_dynamic(target)
	world.emit_domain_event("entity_repaired", {"entity_id": int(target.get("id", -1)), "payer_team": payer, "restored_hp": restored_hp, "resource_spent": spent})
	return restored_hp


func reserve_building_approach_slot(worker: Dictionary, building: Dictionary) -> Variant:
	if worker.get("building_approach_slot") is Vector2:
		return worker["building_approach_slot"]
	var building_id := int(building["id"])
	var reservations: Dictionary = world.building_approach_slots.get(building_id, {})
	var candidates: Array[Vector2] = world.available_approach_slots(worker, world.building_perimeter_candidates(worker, building), reservations)
	for candidate in candidates:
		var route: Array[Vector2] = world.pathfinder.find_path(Vector2(worker.get("pos", Vector2.ZERO)), candidate, String(worker.get("movement_domain", "land")), int(worker.get("terrain_restriction", -1)))
		if route.is_empty():
			continue
		reservations[int(worker["id"])] = candidate
		world.building_approach_slots[building_id] = reservations
		worker["building_approach_slot"] = candidate
		return candidate
	return null


func prepare_building_approach(worker: Dictionary, building: Dictionary) -> bool:
	if worker.get("building_approach_slot") is Vector2:
		return world.resume_approach(worker, worker["building_approach_slot"])
	var building_id := int(building["id"])
	var reservations: Dictionary = world.building_approach_slots.get(building_id, {})
	var slot: Variant = world.assign_reachable_approach_slot(worker, world.building_perimeter_candidates(worker, building), reservations)
	if not slot is Vector2:
		return false
	reservations[int(worker["id"])] = slot
	world.building_approach_slots[building_id] = reservations
	worker["building_approach_slot"] = slot
	return true


func release_building_approach_slot(worker: Dictionary) -> void:
	var building_id := int(worker.get("target_building_id", -1))
	if world.building_approach_slots.has(building_id):
		var reservations: Dictionary = world.building_approach_slots[building_id]
		reservations.erase(int(worker.get("id", -1)))
		if reservations.is_empty():
			world.building_approach_slots.erase(building_id)
		else:
			world.building_approach_slots[building_id] = reservations
	worker["building_approach_slot"] = null


func finish_building_order(worker: Dictionary, reason: String) -> void:
	release_building_approach_slot(worker)
	world.release_unit_destination(worker)
	worker["target_building_id"] = -1
	worker["task"] = "idle"
	world.worker_role_system.clear(worker)
	OrderPipeline.complete(worker, reason)
	EntityComponents.sync_dynamic(worker)
