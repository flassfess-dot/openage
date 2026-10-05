class_name RoRHealingSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const CombatRules := preload("res://scripts/combat_rules.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func component(entity: Dictionary) -> Dictionary:
	return entity.get("components", {}).get("healing", {})


func is_healer(entity: Dictionary) -> bool:
	return bool(component(entity).get("enabled", false))


func assign_command(selected: Array, target_id: int) -> String:
	var target: Variant = world.find_unit(target_id)
	if target == null or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_healing_target"
	var resolved_count := 0
	var last_rejection := "no_eligible_healers"
	for unit in selected:
		if not is_healer(unit):
			continue
		var rejection := validate_target(unit, target)
		if not rejection.is_empty():
			last_rejection = rejection
			continue
		world.conversion_system.cancel(unit, "new_healing")
		cancel(unit, "new_healing")
		world.release_resource_approach_slot(unit)
		world.release_building_approach_slot(unit)
		unit["resource_id"] = -1
		unit["gather_stage"] = "none"
		unit["target_building_id"] = -1
		unit["target_id"] = target_id
		unit["task"] = "heal"
		unit["retaliation_target_id"] = -1
		world.clear_combat_intent(unit)
		var target_direction: Vector2 = Vector2(target["pos"]) - Vector2(unit["pos"])
		if target_direction.length_squared() > 0.0001:
			unit["action_facing"] = world.facing_for_vector(target_direction)
		OrderPipeline.begin(unit, "heal", target_id, target["pos"], true)
		rejection = begin(unit, target)
		if not rejection.is_empty():
			last_rejection = rejection
			world.halt_unit(unit, rejection)
			continue
		if is_in_range(unit, target):
			OrderPipeline.transition(unit, OrderPipeline.PLAN_PATH)
			OrderPipeline.transition(unit, OrderPipeline.MOVE_INTO_RANGE)
			OrderPipeline.transition(unit, OrderPipeline.FACE_TARGET)
			resolved_count += 1
		elif world.assign_unit_destination(unit, target["pos"], false):
			resolved_count += 1
		else:
			last_rejection = "target_unreachable"
			finish_healing(unit, last_rejection)
	return "" if resolved_count > 0 else last_rejection


func finish_healing(healer: Dictionary, reason: String, completed: bool = false) -> void:
	if completed:
		complete(healer, reason)
	else:
		cancel(healer, reason)
	world.release_unit_destination(healer)
	healer["target_id"] = -1
	healer["task"] = "idle"
	healer["diagnostic_reason"] = "healing_complete:%s" % reason
	OrderPipeline.complete(healer, reason)
	world.restore_formation_facing(healer)
	if completed and float(healer.get("hp", 0.0)) > 0.0 and OrderPipeline.queued(healer).is_empty():
		var next_target: Variant = next_chain_target(healer)
		if next_target != null:
			assign_command([healer], int(next_target.get("id", -1)))


func validate_target(healer: Dictionary, target: Variant) -> String:
	if not is_healer(healer):
		return "not_a_healer"
	if float(healer.get("hp", 0.0)) <= 0.0:
		return "healer_unavailable"
	if not target is Dictionary or float(target.get("hp", 0.0)) <= 0.0:
		return "invalid_healing_target"
	if world.find_unit(int(target.get("id", -1))) == null:
		return "invalid_healing_target"
	if int(target.get("id", -1)) == int(healer.get("id", -2)):
		return "self_healing_forbidden"
	if not world.are_teams_allied(int(healer.get("team", 0)), int(target.get("team", 0))):
		return "healing_target_not_allied"
	if float(target.get("hp", 0.0)) + 0.0001 >= float(target.get("max_hp", 0.0)):
		return "target_fully_healed"
	return ""


func range_for(healer: Dictionary) -> float:
	return maxf(0.0, float(component(healer).get("range", 4.0)))


func is_in_range(healer: Dictionary, target: Dictionary) -> bool:
	return CombatRules.edge_distance(healer, target) <= range_for(healer) + 0.0001


func rate_for(healer: Dictionary) -> float:
	var healing := component(healer)
	var rate := maxf(0.0, float(healing.get("base_rate", 0.0)))
	var bonus_resource_id := int(healing.get("bonus_resource_id", -1))
	if bonus_resource_id >= 0:
		rate += maxf(0.0, float(world.get_resource_amount(int(healer.get("team", 0)), bonus_resource_id)))
	return rate * maxf(0.0, float(healing.get("rate_multiplier", 1.0)))


func advance_unit_order(healer: Dictionary, delta: float, result: Dictionary) -> void:
	result["moving"] = false
	result["animation_state"] = AnimationController.IDLE
	result["attack_target"] = null
	var target = world.find_unit(int(healer.get("target_id", -1)))
	var rejection := validate_target(healer, target)
	if rejection == "target_fully_healed":
		finish_healing(healer, "healing_complete", true)
	elif not rejection.is_empty():
		finish_healing(healer, rejection)
	elif not world.is_entity_visible_to(int(healer.get("team", 0)), target):
		finish_healing(healer, "target_lost")
	elif not is_in_range(healer, target):
		world.ensure_navigation_destination(healer, Vector2(target.get("pos", healer.get("pos", Vector2.ZERO))))
		result["moving"] = world.move_unit(healer, delta)
	else:
		world.release_unit_destination(healer)
		OrderPipeline.transition(healer, OrderPipeline.FACE_TARGET)
		world.face_unit_toward(healer, Vector2(target.get("pos", healer.get("pos", Vector2.ZERO))))
		OrderPipeline.transition(healer, OrderPipeline.PERFORM_ACTION)
		result["animation_state"] = AnimationController.HEAL
		var healing_result := advance_healing(healer, target, delta)
		if healing_result == "complete":
			finish_healing(healer, "healing_complete", true)
		elif healing_result != "pending":
			finish_healing(healer, healing_result)


func next_chain_target(healer: Dictionary) -> Variant:
	var healing := component(healer)
	if not bool(healing.get("auto_chain_enabled", true)):
		return null
	var radius := maxf(0.0, float(healing.get("auto_chain_radius", range_for(healer))))
	if radius <= 0.0:
		return null
	var healer_position := Vector2(healer.get("pos", Vector2.ZERO))
	var best_target: Variant = null
	var best_distance_squared := INF
	for candidate_value in world.query_units_near(Vector2(healer.get("pos", Vector2.ZERO)), radius):
		var candidate: Dictionary = candidate_value
		if not validate_target(healer, candidate).is_empty():
			continue
		if not world.is_entity_visible_to(int(healer.get("team", 0)), candidate):
			continue
		var distance_squared := healer_position.distance_squared_to(Vector2(candidate.get("pos", Vector2.ZERO)))
		if best_target == null or distance_squared < best_distance_squared or (is_equal_approx(distance_squared, best_distance_squared) and int(candidate.get("id", -1)) < int(best_target.get("id", -1))):
			best_target = candidate
			best_distance_squared = distance_squared
	return best_target


func begin(healer: Dictionary, target: Dictionary) -> String:
	var rejection := validate_target(healer, target)
	if not rejection.is_empty():
		return rejection
	var healing := component(healer)
	healing["active"] = true
	healing["target_id"] = int(target.get("id", -1))
	healing["restored_amount"] = 0.0
	world.emit_domain_event("healing_started", {
		"healer_id": int(healer.get("id", -1)),
		"target_id": int(target.get("id", -1)),
		"team": int(healer.get("team", 0)),
		"rate": rate_for(healer),
	})
	return ""


func advance_healing(healer: Dictionary, target: Dictionary, delta: float) -> String:
	var rejection := validate_target(healer, target)
	if not rejection.is_empty():
		return rejection
	var healing := component(healer)
	if not bool(healing.get("active", false)) or int(healing.get("target_id", -1)) != int(target.get("id", -1)):
		return "healing_not_active"
	var previous := float(target.get("hp", 0.0))
	var maximum := float(target.get("max_hp", previous))
	target["hp"] = minf(maximum, previous + rate_for(healer) * maxf(0.0, delta))
	var restored := maxf(0.0, float(target["hp"]) - previous)
	healing["restored_amount"] = float(healing.get("restored_amount", 0.0)) + restored
	return "complete" if float(target["hp"]) + 0.0001 >= maximum else "pending"


func complete(healer: Dictionary, reason: String = "healing_complete") -> void:
	var healing := component(healer)
	var was_active := bool(healing.get("active", false))
	var target_id := int(healing.get("target_id", -1))
	var restored := float(healing.get("restored_amount", 0.0))
	_clear(healing)
	if was_active:
		world.emit_domain_event("healing_completed", {
			"healer_id": int(healer.get("id", -1)),
			"target_id": target_id,
			"restored_amount": restored,
			"reason": reason,
		})


func cancel(healer: Dictionary, reason: String = "cancelled") -> void:
	if not is_healer(healer):
		return
	var healing := component(healer)
	var was_active := bool(healing.get("active", false))
	var target_id := int(healing.get("target_id", -1))
	_clear(healing)
	if was_active:
		world.emit_domain_event("healing_cancelled", {
			"healer_id": int(healer.get("id", -1)),
			"target_id": target_id,
			"reason": reason,
		})


func _clear(healing: Dictionary) -> void:
	healing["active"] = false
	healing["target_id"] = -1
	healing["restored_amount"] = 0.0
