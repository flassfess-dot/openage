class_name RoRSimulationActivityRegistry
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")
var cursor := -1
var epoch := -1
var source_journal
var idle_units_by_id: Dictionary = {}
var idle_units: Array = []
var idle_dirty := true
var pending_units: Dictionary = {}
var idle_position_resets: Dictionary = {}
var animation_kernel: Variant = null
var native_order_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_NATIVE_ACTIVITY_ORDER") != "1"
var native_order_supported := false
var order_tick_native := true
var profile_order_alternatives := "--profile-activity-order-alternatives" in OS.get_cmdline_user_args()
var native_order_calls := 0
var script_order_calls := 0
var native_order_units := 0
var native_refresh_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_ACTIVITY_REFRESH") != "1"
var profile_refresh_alternatives := "--profile-activity-refresh-alternatives" in OS.get_cmdline_user_args()
var refresh_tick_native := true
var refresh_last_native := false
var native_refresh_calls := 0
var native_refresh_units := 0
var refresh_reference_enabled := "--profile-activity-refresh-reference" in OS.get_cmdline_user_args()
var refresh_reference_checks := 0
var refresh_reference_mismatches := 0
var coalesced_boundaries_enabled := OS.get_environment("ROR_DIAGNOSTIC_COALESCED_ACTIVITY") != "0"
var activity_world_ref: WeakRef
var boundary_synchronizations := 0
var boundary_pending_fallbacks := 0




# Source events own membership; only active actors enter fixed-step dispatch.
# Idle elapsed animation is advanced independently of factual classification.

var active_units_by_id: Dictionary = {}
var active_units: Array = []
var active_index_by_id: Dictionary = {}
var unit_order_by_id: Dictionary = {}
var order_dirty: bool = false
var roster_dirty: bool = true
var movement_candidate_active: bool = false
var formation_active: bool = false
var tick_prepared: bool = false


func clear() -> void:
	cursor = -1
	epoch = -1
	pending_units.clear()
	idle_position_resets.clear()
	animation_kernel = null
	idle_units_by_id.clear()
	idle_units.clear()
	idle_dirty = true
	active_units_by_id.clear()
	active_units.clear()
	active_index_by_id.clear()
	unit_order_by_id.clear()
	order_dirty = false
	roster_dirty = true
	movement_candidate_active = false
	formation_active = false
	tick_prepared = false


func synchronize(world) -> void:
	_synchronize_changes(world)


func _synchronize_changes(world) -> Dictionary:
	if activity_world_ref == null or activity_world_ref.get_ref() != world:
		activity_world_ref = weakref(world)
	var journal = world.entity_changes
	source_journal = journal
	var delta: Dictionary = journal.read_changes_since(cursor if epoch == journal.epoch else -1)
	if bool(delta["full"]):
		clear()
		for index in range(world.units.size()):
			var unit: Dictionary = world.units[index]
			unit_order_by_id[int(unit["id"])] = index
			refresh(unit)
	else:
		var classified: Dictionary = {}
		if world.get_script() != null and world.get_script().resource_path == "res://scripts/simulation_world.gd":
			classified = _classify_activity_changes(delta["ids"], world.units_by_id, delta["masks"])
		var candidates: Array = delta["ids"]
		if not classified.is_empty():
			candidates = classified["remaining"]
			movement_candidate_active = bool(classified["movement"])
			formation_active = bool(classified["formation"])
		for id in candidates:
			if classified.is_empty() and not (int(delta["masks"][id]) & (Journal.LIFECYCLE | Journal.ACTIVITY | Journal.COMBAT | Journal.OWNERSHIP)): continue
			var unit: Variant = world.find_unit(int(id))
			if unit == null: forget(int(id))
			else: refresh(unit)
		if roster_dirty:
			for index in range(world.units.size()): unit_order_by_id[int(world.units[index]["id"])] = index
			order_dirty = true
	cursor = int(delta["revision"])
	epoch = journal.epoch
	roster_dirty = false
	return delta

func begin_tick(_units: Array, delta: float, observer: Variant = null) -> void:
	tick_prepared = true
	for unit in idle_position_resets.values(): unit["previous_pos"] = unit.get("pos", Vector2.ZERO)
	idle_position_resets.clear()
	var active: Array = ordered_units()
	var capture_started := Time.get_ticks_usec() if observer != null else 0
	movement_candidate_active = false
	formation_active = false
	for unit in active:
		movement_candidate_active = movement_candidate_active or _is_movement_candidate(unit)
		formation_active = formation_active or _has_active_formation(unit)
		unit["previous_pos"] = unit.get("pos", Vector2.ZERO)
	if observer != null: observer.observe_microseconds("simulation.activity.capture.script", Time.get_ticks_usec() - capture_started)
	if idle_dirty:
		idle_units = idle_units_by_id.values()
		idle_dirty = false
	# No classification or compatibility pass over the army. Idle animation is
	# visual elapsed time only; native advancement preserves fixed-step addition.
	if not idle_units.is_empty():
		if ClassDB.class_exists("RoRReadModelKernel"):
			if animation_kernel == null: animation_kernel = ClassDB.instantiate("RoRReadModelKernel")
			var changed: PackedInt32Array = animation_kernel.advance_idle_animation(idle_units, delta)
			for id in changed: source_journal.mark(int(id), Journal.APPEARANCE)
		else:
			for unit in idle_units:
				if AnimationController.update(unit, AnimationController.IDLE, delta): source_journal.mark(int(unit["id"]), Journal.APPEARANCE)


func ensure_tick(units: Array, delta: float) -> void:
	if not tick_prepared:
		begin_tick(units, delta)


func finish_tick(observer: Variant = null) -> void:
	var started := Time.get_ticks_usec() if observer != null else 0
	var native_calls_before := native_refresh_calls
	tick_prepared = false
	var world: Variant = activity_world_ref.get_ref() if activity_world_ref != null else null
	if coalesced_boundaries_enabled and world != null:
		# Classify the completed actor writes through the journal once, and
		# advance that consumer's cursor at the same boundary. Previously the
		# pending pass left the cursor behind, repeating the work next tick.
		var pending: Array = pending_units.values()
		pending_units.clear()
		var consumed := _synchronize_changes(world)
		boundary_synchronizations += 1
		if not bool(consumed["full"]):
			for unit in pending:
				var id := int(unit.get("id", -1))
				if int(consumed["masks"].get(id, 0)) & (Journal.LIFECYCLE | Journal.ACTIVITY | Journal.COMBAT | Journal.OWNERSHIP): continue
				# Preserve explicit refresh callers that did not publish an event.
				boundary_pending_fallbacks += 1
				refresh(unit)
		if observer != null: observer.observe_microseconds("simulation.activity.finish.native" if native_refresh_calls > native_calls_before else "simulation.activity.finish.script", Time.get_ticks_usec() - started)
		return
	var stable := _stable_activity_updates(pending_units.keys(), pending_units)
	var has_stable := not stable.is_empty()
	var pending: Array = pending_units.values()
	pending_units.clear()
	for unit in pending:
		var id := int(unit.get("id", -1))
		if has_stable and stable.has(id):
			movement_candidate_active = true
			formation_active = formation_active or bool(stable[id])
		else: refresh(unit)

	if observer != null: observer.observe_microseconds("simulation.activity.finish.native" if native_refresh_calls > native_calls_before else "simulation.activity.finish.script", Time.get_ticks_usec() - started)

func _classify_activity_changes(ids: Array, units_by_id: Dictionary, masks: Dictionary) -> Dictionary:
	if tick_prepared or not native_refresh_enabled or not refresh_tick_native or get_script().resource_path != "res://scripts/simulation_activity_registry.gd" or not ClassDB.class_exists("RoRReadModelKernel"): return {}
	if animation_kernel == null: animation_kernel = ClassDB.instantiate("RoRReadModelKernel")
	if animation_kernel.get_script() != null or not animation_kernel.has_method("classify_activity_changes"): return {}
	var verify_limit := maxi(0, 512 - refresh_reference_checks) if refresh_reference_enabled else 0
	var result: Dictionary = animation_kernel.classify_activity_changes(ids, {"units":units_by_id,"active":active_units_by_id,"idle":idle_units_by_id,"orders":unit_order_by_id,"masks":masks,"filter_changes":true,"movement":movement_candidate_active,"formation":formation_active,"verify_limit":verify_limit})
	if result.is_empty(): return {}
	var bad_ids := _verify_activity_updates(result["verification"], units_by_id)
	result["remaining"].append_array(bad_ids)
	refresh_last_native = true
	native_refresh_calls += 1
	native_refresh_units += int(result["stable_count"]) - bad_ids.size()
	return result


func _stable_activity_updates(ids: Array, units_by_id: Dictionary, masks: Dictionary = {}, filter_changes: bool = false) -> Dictionary:
	if tick_prepared or not native_refresh_enabled or not refresh_tick_native or get_script().resource_path != "res://scripts/simulation_activity_registry.gd" or not ClassDB.class_exists("RoRReadModelKernel"): return {}
	if animation_kernel == null: animation_kernel = ClassDB.instantiate("RoRReadModelKernel")
	if animation_kernel.get_script() != null or not animation_kernel.has_method("stable_activity_updates"): return {}
	var stable: Dictionary = animation_kernel.stable_activity_updates(ids, {"units":units_by_id,"active":active_units_by_id,"idle":idle_units_by_id,"orders":unit_order_by_id,"masks":masks,"filter_changes":filter_changes})
	refresh_last_native = true
	native_refresh_calls += 1
	_verify_activity_updates(stable, units_by_id)
	native_refresh_units += stable.size()
	return stable


func _verify_activity_updates(stable: Dictionary, units_by_id: Dictionary) -> Array:
	var bad_ids: Array = []
	if refresh_reference_enabled and refresh_reference_checks < 512:
		for id in stable.keys():
			var unit: Dictionary = units_by_id[id]
			var valid := int(id) >= 0 and unit_order_by_id.has(id) and active_units_by_id.get(id) != null and not idle_units_by_id.has(id) and requires_update(unit) and _is_movement_candidate(unit) and _has_active_formation(unit) == bool(stable[id])
			refresh_reference_checks += 1
			if not valid:
				refresh_reference_mismatches += 1
				stable.erase(id)
				bad_ids.append(id)
			if refresh_reference_checks >= 512: break
	return bad_ids


func refresh(unit: Dictionary) -> bool:
	if tick_prepared:
		pending_units[int(unit.get("id", -1))] = unit
		return false
	var entity_id := int(unit.get("id", -1))
	if entity_id >= 0 and not unit_order_by_id.has(entity_id):
		roster_dirty = true
	var is_active := requires_update(unit)
	_set_active(unit, is_active)
	var idle := not is_active and float(unit.get("hp", 0.0)) > 0.0
	if idle != idle_units_by_id.has(entity_id):
		idle_dirty = true
		if idle:
			idle_position_resets[entity_id] = unit
			idle_units_by_id[entity_id] = unit
		else:
			idle_units_by_id.erase(entity_id)
			idle_position_resets.erase(entity_id)
	if is_active:
		movement_candidate_active = movement_candidate_active or _is_movement_candidate(unit)
		formation_active = formation_active or _has_active_formation(unit)
	return is_active


func forget(entity_id: int) -> void:
	idle_position_resets.erase(entity_id)
	pending_units.erase(entity_id)
	idle_units_by_id.erase(entity_id)
	idle_dirty = true
	_remove_active(entity_id)
	if unit_order_by_id.has(entity_id):
		unit_order_by_id.erase(entity_id)
		order_dirty = true
		roster_dirty = true


func ordered_units() -> Array:
	if order_dirty:
		var probe: Variant = source_journal.performance_probe if source_journal != null else null
		var started := Time.get_ticks_usec() if probe != null else 0
		var sorted_natively := false
		if native_order_enabled and get_script().resource_path == "res://scripts/simulation_activity_registry.gd" and ClassDB.class_exists("RoRReadModelKernel"):
			if animation_kernel == null: animation_kernel = ClassDB.instantiate("RoRReadModelKernel")
			native_order_supported = animation_kernel.get_script() == null and animation_kernel.has_method("sort_active_units")
			if native_order_supported and order_tick_native:
				sorted_natively = animation_kernel.sort_active_units(active_units, unit_order_by_id)
		if sorted_natively:
			native_order_calls += 1
			native_order_units += active_units.size()
		else:
			script_order_calls += 1
			active_units.sort_custom(_precedes)
		if probe != null: probe.observe_microseconds("simulation.activity.order.native" if sorted_natively else "simulation.activity.order.script", Time.get_ticks_usec() - started)
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
	assert(index >= 0 and index < active_units.size(), "Activity dense index is owned by this registry")
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
