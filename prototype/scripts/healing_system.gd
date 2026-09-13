class_name RoRHealingSystem
extends RefCounted

const CombatRules := preload("res://scripts/combat_rules.gd")

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
	target.get("components", {}).get("health", {})["current"] = target["hp"]
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
