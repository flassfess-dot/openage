extends RefCounted

# Owns this state; the world is passed per operation to avoid a reference cycle.
const AnimationController := preload("res://scripts/animation_controller.gd")
const EntityChangeJournal := preload("res://scripts/entity_change_journal.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")

var entity_changes := EntityChangeJournal.new()
var read_generation_pins := 0
var runtime_task_capture := false
var runtime_previous_tasks: Dictionary = {}
var runtime_actor_eligibility: Dictionary = {}

func reset() -> void:
	read_generation_pins = 0
	entity_changes.reset()


func clear_runtime_capture() -> void:
	runtime_task_capture = false
	runtime_previous_tasks.clear()
	runtime_actor_eligibility.clear()


# Domain operations reserve their notification at entry, before any nested
# setter can publish a read. The callback runs synchronously on the owner thread.
# This preserves the existing journal boundary and activity refresh ordering.
func mutate_entity(world, entity: Dictionary, operation: Callable, mask: int = EntityChangeJournal.MUTABLE_GROUPS) -> Variant:
	assert(read_generation_pins == 0, "Pinned observation generation is immutable")
	notify_entity_changed(world, entity, mask)
	return operation.call()


func set_entity_fields(world, entity: Dictionary, values: Dictionary) -> void:
	for field in values:
		set_entity_field(world, entity, String(field), values[field])


func set_entity_field(world, entity: Dictionary, field: String, value: Variant) -> void:
	assert(read_generation_pins == 0, "Pinned observation generation is immutable")
	if not (value is Array or value is Dictionary) and entity.has(field) and typeof(entity[field]) == typeof(value) and entity[field] == value: return
	if runtime_task_capture and field in ["task", "hp", "state", "combat_enabled"]:
		var id = int(entity.get("id", -1))
		if not runtime_actor_eligibility.has(id): runtime_actor_eligibility[id] = bool(entity.get("combat_enabled", false)) and float(entity.get("hp", 0.0)) > 0.0 and (not world.entity_is_static(entity) or String(entity.get("state", "complete")) == "complete")
		if field == "task" and bool(runtime_actor_eligibility[id]) and not runtime_previous_tasks.has(id): runtime_previous_tasks[id] = [entity, String(entity.get("task", "idle"))]
	entity[field] = value
	var mask = EntityChangeJournal.field_mask(field)
	entity_changes.mark(int(entity.get("id", -1)), mask)
	if mask & EntityChangeJournal.ACTIVITY: world.refresh_unit_activity(entity)


func register_entity_changes(world, entity: Dictionary) -> void:
	entity_changes.mark(int(entity.get("id", -1)), EntityChangeJournal.ALL)
	world.refresh_unit_activity(entity)


func rebuild_entity_change_tracking(world) -> void:
	entity_changes.reset()
	world.entity_read_index.clear()
	world.unit_activity_registry.clear()
	for entity in world._entity_change_comparison_roster(): world.register_entity_changes(entity)
	entity_changes.flush()
	if entity_changes.comparison_enabled:
		entity_changes.set_comparison_enabled(true, world._entity_change_comparison_roster())


func set_entity_change_comparison(world, enabled: bool) -> void:
	entity_changes.flush()
	entity_changes.set_comparison_enabled(enabled, world._entity_change_comparison_roster())


func _entity_change_comparison_roster(world) -> Array:
	return world.get_all_units_including_embarked() + world.buildings + world.resource_nodes + world.victory_objectives


func _mark_entity_order_changed(world, entity: Dictionary) -> void:
	entity_changes.mark(int(entity.get("id", -1)), EntityChangeJournal.ACTIVITY | EntityChangeJournal.CONTROL)
	world.refresh_unit_activity(entity)


func begin_entity_order(world, entity: Dictionary, order_type: String, target_entity_id: int = -1, target_position: Vector2 = Vector2.ZERO, repeat: bool = false) -> Dictionary:
	var result = OrderPipeline.begin(entity, order_type, target_entity_id, target_position, repeat)
	world._mark_entity_order_changed(entity)
	return result


func transition_entity_order(world, entity: Dictionary, phase: String) -> void:
	var order = OrderPipeline.current(entity)
	var changed = not bool(order.get("completed", true)) and String(order.get("phase", "")) != phase and OrderPipeline.PHASES.has(phase)
	OrderPipeline.transition(entity, phase)
	if changed: world._mark_entity_order_changed(entity)


func complete_entity_order(world, entity: Dictionary, reason: String = "complete") -> void:
	var order = OrderPipeline.current(entity)
	var changed = not bool(order.get("completed", true)) or String(order.get("completion_reason", "")) != reason or String(order.get("phase", "")) != OrderPipeline.REPEAT_OR_COMPLETE
	OrderPipeline.complete(entity, reason)
	if changed: world._mark_entity_order_changed(entity)


func restart_entity_order(world, entity: Dictionary) -> void:
	var order = OrderPipeline.current(entity)
	var changed = not bool(order.get("completed", true)) and bool(order.get("repeat", false))
	OrderPipeline.restart(entity)
	if changed: world._mark_entity_order_changed(entity)


func append_entity_queued_order(world, entity: Dictionary, entry: Dictionary) -> bool:
	var result = OrderPipeline.append_queued(entity, entry)
	if result: world._mark_entity_order_changed(entity)
	return result


func prepend_entity_queued_order(world, entity: Dictionary, entry: Dictionary) -> bool:
	var result = OrderPipeline.prepend_queued(entity, entry)
	if result: world._mark_entity_order_changed(entity)
	return result


func pop_entity_queued_order(world, entity: Dictionary) -> Dictionary:
	var result = OrderPipeline.pop_queued(entity)
	if not result.is_empty(): world._mark_entity_order_changed(entity)
	return result


func clear_entity_queued_orders(world, entity: Dictionary) -> void:
	var changed = not OrderPipeline.queued(entity).is_empty()
	OrderPipeline.clear_queued(entity)
	if changed: world._mark_entity_order_changed(entity)

# Pinning is owner-thread isolation, not a saved gameplay cursor. The fixed-step
# barrier holds source_tick until all deterministic capture portions are sealed.


func pin_read_generation(world) -> Dictionary:
	entity_changes.flush()
	read_generation_pins += 1
	return {"epoch": entity_changes.epoch, "revision": entity_changes.revision}


func release_read_generation(world, token: Dictionary) -> void:
	if int(token.get("epoch", -1)) == int(entity_changes.epoch): read_generation_pins = maxi(0, read_generation_pins - 1)


func begin_runtime_task_capture(world) -> void:
	runtime_previous_tasks.clear()
	runtime_actor_eligibility.clear()
	runtime_task_capture = true


func end_runtime_task_capture(world) -> Array:
	runtime_task_capture = false
	var result: Array = []
	var ids: Array = runtime_previous_tasks.keys()
	ids.sort()
	for id in ids:
		var old: Array = runtime_previous_tasks[id]
		var current = String(old[0].get("task", "idle"))
		if not bool(old[0].get("removed", false)) and current != String(old[1]): result.append({"entity_id": int(id), "previous_task": old[1], "current_task": current, "issuer_id": 0, "command_sequence_id": 0})
	runtime_previous_tasks.clear()
	runtime_actor_eligibility.clear()
	return result


func notify_entity_changed(world, entity: Dictionary, mask: int = EntityChangeJournal.MUTABLE_GROUPS) -> void:
	entity_changes.mark(int(entity.get("id", -1)), mask)
	if mask & EntityChangeJournal.ACTIVITY: world.refresh_unit_activity(entity)


func erase_entity_field(world, entity: Dictionary, field: String) -> void:
	if entity.erase(field):
		entity_changes.mark(int(entity.get("id", -1)), EntityChangeJournal.field_mask(field))
		world.refresh_unit_activity(entity)


func advance_entity_animation(world, entity: Dictionary, state: String, delta: float, restart_same_clip: bool = false) -> bool:
	assert(read_generation_pins == 0, "Pinned observation generation is immutable")
	var changed = AnimationController.update(entity, state, delta, restart_same_clip)
	if changed: entity_changes.mark(int(entity["id"]), EntityChangeJournal.APPEARANCE)
	return changed
