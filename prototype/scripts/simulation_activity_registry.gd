class_name RoRSimulationActivityRegistry
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const COMPATIBILITY_REFRESH_INTERVAL_TICKS := 200

# Keeps the expensive unit-order loop proportional to units that can actually
# change authoritative state. Unit state is still sampled every fixed tick for
# compatibility with exposed entity dictionaries and idle animation, while
# roster/order bookkeeping is reconciled only on lifecycle changes or by a
# slower compatibility pass.

var active_units_by_id: Dictionary = {}
var active_units: Array = []
var active_index_by_id: Dictionary = {}
var unit_order_by_id: Dictionary = {}
var order_dirty: bool = false
var roster_dirty: bool = true
var compatibility_ticks: int = 0
var movement_candidate_active: bool = false
var formation_active: bool = false
var tick_prepared: bool = false


func clear() -> void:
	active_units_by_id.clear()
	active_units.clear()
	active_index_by_id.clear()
	unit_order_by_id.clear()
	order_dirty = false
	roster_dirty = true
	compatibility_ticks = 0
	movement_candidate_active = false
	formation_active = false
	tick_prepared = false


func begin_tick(units: Array, delta: float) -> void:
	tick_prepared = true
	compatibility_ticks += 1
	var reconcile_roster := roster_dirty or compatibility_ticks >= COMPATIBILITY_REFRESH_INTERVAL_TICKS or unit_order_by_id.size() != units.size()
	var live_ids: Dictionary = {} if reconcile_roster else unit_order_by_id
	movement_candidate_active = false
	formation_active = false
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var entity_id := int(unit.get("id", -1))
		if entity_id < 0:
			continue
		if reconcile_roster:
			live_ids[entity_id] = true
			if int(unit_order_by_id.get(entity_id, -1)) != index:
				order_dirty = true
			unit_order_by_id[entity_id] = index
		var active := requires_update(unit)
		# The overwhelmingly common case is a stable roster. Avoid a method call
		# and index maintenance check for every unit on every tick; enter the
		# mutation path only when its activity classification actually changes.
		if active != active_units_by_id.has(entity_id):
			_set_active(unit, active)
		if active:
			movement_candidate_active = movement_candidate_active or _is_movement_candidate(unit)
			formation_active = formation_active or _has_active_formation(unit)
		var position := Vector2(unit.get("pos", Vector2.ZERO))
		if Vector2(unit.get("previous_pos", position)) != position:
			unit["previous_pos"] = position
		if not active and float(unit.get("hp", 0.0)) > 0.0:
			# Preserve AnimationController's exact transition semantics without
			# routing stable idle entities through task dispatch.
			if String(unit.get("anim_state", AnimationController.IDLE)) == AnimationController.IDLE:
				unit["anim"] = float(unit.get("anim", 0.0)) + delta
			else:
				AnimationController.update(unit, AnimationController.IDLE, delta)
	if reconcile_roster:
		for entity_id_value in unit_order_by_id.keys():
			var entity_id := int(entity_id_value)
			if not live_ids.has(entity_id):
				forget(entity_id)
		roster_dirty = false
		compatibility_ticks = 0


func ensure_tick(units: Array, delta: float) -> void:
	if not tick_prepared:
		begin_tick(units, delta)


func finish_tick() -> void:
	tick_prepared = false


func refresh(unit: Dictionary) -> bool:
	var entity_id := int(unit.get("id", -1))
	if entity_id >= 0 and not unit_order_by_id.has(entity_id):
		roster_dirty = true
	var is_active := requires_update(unit)
	_set_active(unit, is_active)
	if is_active:
		movement_candidate_active = movement_candidate_active or _is_movement_candidate(unit)
		formation_active = formation_active or _has_active_formation(unit)
	return is_active


func forget(entity_id: int) -> void:
	_remove_active(entity_id)
	if unit_order_by_id.has(entity_id):
		unit_order_by_id.erase(entity_id)
		order_dirty = true
		roster_dirty = true


func ordered_units() -> Array:
	if order_dirty:
		active_units.sort_custom(_precedes)
		_rebuild_active_indices()
		order_dirty = false
	return active_units


func is_active(entity_id: int) -> bool:
	return active_units_by_id.has(entity_id)


func order_of(entity_id: int) -> int:
	return int(unit_order_by_id.get(entity_id, entity_id))


func has_movement_candidate() -> bool:
	return movement_candidate_active


func has_active_formation() -> bool:
	return formation_active


static func requires_update(unit: Dictionary) -> bool:
	if float(unit.get("hp", 0.0)) <= 0.0:
		return String(unit.get("death_phase", "alive")) == "alive"
	if String(unit.get("task", "idle")) != "idle":
		return true
	if not unit.get("path", []).is_empty() or int(unit.get("path_index", 0)) != 0:
		return true
	var position := Vector2(unit.get("pos", Vector2.ZERO))
	if Vector2(unit.get("previous_pos", position)) != position:
		return true
	if Vector2(unit.get("target", position)) != position:
		return true
	if Vector2(unit.get("actual_velocity", Vector2.ZERO)) != Vector2.ZERO:
		return true
	if int(unit.get("stuck_ticks", 0)) != 0:
		return true
	if int(unit.get("push_priority", 0)) != int(unit.get("base_push_priority", unit.get("push_priority", 0))):
		return true
	if bool(unit.get("formation_shared_motion", false)) or bool(unit.get("formation_shared_isolated", false)):
		return true
	if not is_equal_approx(float(unit.get("cohesion_speed_scale", 1.0)), 1.0):
		return true
	if float(unit.get("cooldown", 0.0)) > 0.0 or float(unit.get("work", 0.0)) > 0.0:
		return true
	if int(unit.get("retaliation_target_id", -1)) >= 0:
		return true
	var conversion: Dictionary = unit.get("components", {}).get("conversion", {})
	if bool(conversion.get("enabled", false)):
		if bool(conversion.get("active", false)):
			return true
		if float(conversion.get("faith", 0.0)) + 0.0001 < float(conversion.get("max_faith", 100.0)):
			return true
	return false


static func _is_movement_candidate(unit: Dictionary) -> bool:
	if float(unit.get("hp", 0.0)) <= 0.0:
		return false
	if int(unit.get("retaliation_target_id", -1)) >= 0 or String(unit.get("task", "idle")) != "idle":
		return true
	var position := Vector2(unit.get("pos", Vector2.ZERO))
	return not unit.get("path", []).is_empty() or Vector2(unit.get("target", position)) != position


static func _has_active_formation(unit: Dictionary) -> bool:
	if int(unit.get("formation_group_id", -1)) >= 0 and String(unit.get("task", "idle")) == "move":
		return true
	return bool(unit.get("formation_shared_motion", false)) or bool(unit.get("formation_shared_isolated", false)) or not is_equal_approx(float(unit.get("cohesion_speed_scale", 1.0)), 1.0)


func _set_active(unit: Dictionary, should_be_active: bool) -> void:
	var entity_id := int(unit.get("id", -1))
	if entity_id < 0:
		return
	var registered: Variant = active_units_by_id.get(entity_id)
	if should_be_active:
		if registered != null:
			return
		active_units_by_id[entity_id] = unit
		if order_dirty or not unit_order_by_id.has(entity_id):
			active_units.append(unit)
			active_index_by_id[entity_id] = active_units.size() - 1
			order_dirty = true
		else:
			_insert_ordered(unit)
	elif registered != null:
		_remove_active(entity_id)


func _insert_ordered(unit: Dictionary) -> void:
	var low := 0
	var high := active_units.size()
	while low < high:
		var middle := (low + high) >> 1
		if _precedes(unit, active_units[middle]):
			high = middle
		else:
			low = middle + 1
	active_units.insert(low, unit)
	for index in range(low, active_units.size()):
		active_index_by_id[int(active_units[index].get("id", -1))] = index


func _remove_active(entity_id: int) -> void:
	if not active_units_by_id.has(entity_id):
		return
	active_units_by_id.erase(entity_id)
	var index := int(active_index_by_id.get(entity_id, -1))
	active_index_by_id.erase(entity_id)
	if index < 0 or index >= active_units.size():
		# Compatibility recovery for externally modified records. A later sort
		# rebuilds the dense index after this rare linear fallback.
		for fallback_index in range(active_units.size()):
			if int(active_units[fallback_index].get("id", -1)) == entity_id:
				index = fallback_index
				break
	if index < 0 or index >= active_units.size():
		return
	var last_index := active_units.size() - 1
	if index != last_index:
		var moved: Dictionary = active_units[last_index]
		active_units[index] = moved
		active_index_by_id[int(moved.get("id", -1))] = index
	active_units.pop_back()
	order_dirty = true


func _rebuild_active_indices() -> void:
	active_index_by_id.clear()
	for index in range(active_units.size()):
		active_index_by_id[int(active_units[index].get("id", -1))] = index


func _precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_id := int(left.get("id", -1))
	var right_id := int(right.get("id", -1))
	var left_order := int(unit_order_by_id.get(left_id, left_id))
	var right_order := int(unit_order_by_id.get(right_id, right_id))
	return left_order < right_order or (left_order == right_order and left_id < right_id)
