class_name RoROrderPipeline

const ACQUIRE_TARGET := "AcquireTarget"
const PLAN_PATH := "PlanPath"
const MOVE_INTO_RANGE := "MoveIntoRange"
const FACE_TARGET := "FaceTarget"
const PERFORM_ACTION := "PerformAction"
const RECOVER := "Recover"
const REPEAT_OR_COMPLETE := "RepeatOrComplete"

const PHASES: Array[String] = [
	ACQUIRE_TARGET,
	PLAN_PATH,
	MOVE_INTO_RANGE,
	FACE_TARGET,
	PERFORM_ACTION,
	RECOVER,
	REPEAT_OR_COMPLETE,
]


static func empty_order() -> Dictionary:
	return {
		"type": "none",
		"phase": REPEAT_OR_COMPLETE,
		"target_entity_id": -1,
		"target_position": Vector2.ZERO,
		"repeat": false,
		"completed": true,
		"completion_reason": "idle",
		"revision": 0,
		"history": [],
	}


static func begin(entity: Dictionary, order_type: String, target_entity_id: int = -1, target_position: Vector2 = Vector2.ZERO, repeat: bool = false) -> Dictionary:
	var order := current(entity)
	var revision := int(order.get("revision", 0)) + 1
	order = {
		"type": order_type,
		"phase": ACQUIRE_TARGET,
		"target_entity_id": target_entity_id,
		"target_position": target_position,
		"repeat": repeat,
		"completed": false,
		"completion_reason": "",
		"revision": revision,
		"history": [ACQUIRE_TARGET],
	}
	set_order(entity, order)
	return order


static func transition(entity: Dictionary, phase: String) -> void:
	if not PHASES.has(phase):
		return
	var order := current(entity)
	if bool(order.get("completed", true)) or String(order.get("phase", "")) == phase:
		return
	order["phase"] = phase
	var history: Array = order.get("history", [])
	history.append(phase)
	if history.size() > 32:
		history.pop_front()
	order["history"] = history
	set_order(entity, order)


static func complete(entity: Dictionary, reason: String = "complete") -> void:
	var order := current(entity)
	if String(order.get("phase", "")) != REPEAT_OR_COMPLETE:
		transition(entity, REPEAT_OR_COMPLETE)
		order = current(entity)
	order["completed"] = true
	order["completion_reason"] = reason
	set_order(entity, order)


static func restart(entity: Dictionary) -> void:
	var order := current(entity)
	if bool(order.get("completed", true)) or not bool(order.get("repeat", false)):
		return
	transition(entity, REPEAT_OR_COMPLETE)
	transition(entity, ACQUIRE_TARGET)


static func current(entity: Dictionary) -> Dictionary:
	var components: Dictionary = entity.get("components", {})
	var order: Dictionary = components.get("order", {})
	if order.is_empty():
		order = empty_order()
		set_order(entity, order)
	return order


static func phase(entity: Dictionary) -> String:
	return String(current(entity).get("phase", REPEAT_OR_COMPLETE))


static func is_active(entity: Dictionary, order_type: String = "") -> bool:
	var order := current(entity)
	if bool(order.get("completed", true)):
		return false
	return order_type.is_empty() or String(order.get("type", "")) == order_type


static func set_order(entity: Dictionary, order: Dictionary) -> void:
	var components: Dictionary = entity.get("components", {})
	components["order"] = order
	entity["components"] = components
