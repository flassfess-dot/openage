class_name RoRSpatialHash

var cell_size: float = 2.0
var buckets: Dictionary = {}
var unit_buckets: Dictionary = {}
var unit_entities: Array = []
var unit_index_by_id: Dictionary = {}
var unit_positions: Array[Vector2] = []
var unit_radii: Array[float] = []
var unit_cells: Array[Vector2i] = []
var obstacle_entities: Array = []
var maximum_unit_radius: float = 0.0
var maximum_unit_clearance: float = 0.0
var native_neighbors_enabled := true
var native_neighbors_supported := false
var native_circle_supported := false
var performance_probe: Variant = null
var profile_circle_alternatives := "--profile-circle-alternatives" in OS.get_cmdline_user_args()
var circle_profile_sequence := 0
var native_sync_enabled := OS.get_environment("ROR_DIAGNOSTIC_DISABLE_NATIVE_SPATIAL_SYNC") != "1"
var native_sync_supported := false
var profile_sync_alternatives := "--profile-spatial-sync-alternatives" in OS.get_cmdline_user_args()
var synchronization_serial := 0
var synchronization_tick_native := false
var native_sync_calls := 0
var native_sync_units := 0
var native_sync_fallbacks := 0
var script_sync_calls := 0
var query_kernel: Variant = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null:
	set(value):
		query_kernel = value
		native_neighbors_supported = value != null and value.has_method("spatial_unit_neighbors")
		native_circle_supported = value != null and value.has_method("spatial_unit_circle")
		native_sync_supported = value != null and value.has_method("synchronize_spatial_units_prefix") and value.get_script() == null


func _init(bucket_size: float = 2.0) -> void:
	cell_size = maxf(0.25, bucket_size)
	native_neighbors_supported = query_kernel != null and query_kernel.has_method("spatial_unit_neighbors")
	native_circle_supported = query_kernel != null and query_kernel.has_method("spatial_unit_circle")
	native_sync_supported = query_kernel != null and query_kernel.has_method("synchronize_spatial_units_prefix") and query_kernel.get_script() == null

func clear() -> void:
	buckets.clear()
	unit_buckets.clear()
	unit_entities.clear()
	unit_index_by_id.clear()
	unit_positions.clear()
	unit_radii.clear()
	unit_cells.clear()
	obstacle_entities.clear()
	maximum_unit_radius = 0.0
	maximum_unit_clearance = 0.0

func insert(entity: Dictionary, position: Vector2, radius: float, category: String) -> void:
	if category == "unit":
		var mobile_radius := maxf(0.0, radius)
		maximum_unit_radius = maxf(maximum_unit_radius, mobile_radius)
		maximum_unit_clearance = maxf(maximum_unit_clearance, float(entity.get("minimum_clearance", 0.0)))
		var unit_index := unit_entities.size()
		unit_entities.append(entity)
		unit_index_by_id[int(entity.get("id", -1))] = unit_index
		unit_positions.append(position)
		unit_radii.append(mobile_radius)
		var unit_cell := cell_for(position)
		unit_cells.append(unit_cell)
		if not unit_buckets.has(unit_cell):
			unit_buckets[unit_cell] = []
		unit_buckets[unit_cell].append(unit_index)
		return
	obstacle_entities.append(entity)
	var item := {"entity": entity, "position": position, "radius": maxf(0.0, radius), "category": category}
	var minimum := cell_for(position - Vector2.ONE * item["radius"])
	var maximum := cell_for(position + Vector2.ONE * item["radius"])
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var key := Vector2i(x, y)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(item)


func synchronize_dynamic_entities(units: Array, buildings: Array) -> bool:
	synchronization_serial += 1
	synchronization_tick_native = false
	# The identity/order of live entities changes far less often than their
	# positions. Preserve bucket storage between ticks and move only indices that
	# crossed a cell boundary; callers fall back to a full rebuild on lifecycle
	# changes so query semantics remain identical.
	var unit_index := 0
	for unit_value in units:
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			continue
		if unit_index >= unit_entities.size() or int(unit_entities[unit_index].get("id", -1)) != int(unit.get("id", -1)):
			return false
		_update_unit_slot(unit_index, Vector2(unit.get("pos", Vector2.ZERO)))
		unit_index += 1
	if unit_index != unit_entities.size():
		return false

	var obstacle_index := 0
	for building_value in buildings:
		var building: Dictionary = building_value
		if float(building.get("hp", 0.0)) <= 0.0:
			continue
		if obstacle_index >= obstacle_entities.size() or int(obstacle_entities[obstacle_index].get("id", -1)) != int(building.get("id", -1)):
			return false
		obstacle_index += 1
	return obstacle_index == obstacle_entities.size()


func synchronize_active_units(units: Array) -> bool:
	synchronization_serial += 1
	synchronization_tick_native = false
	var started := Time.get_ticks_usec() if performance_probe != null else 0
	var first := 0
	var use_native := native_sync_enabled and native_sync_supported
	if profile_sync_alternatives: use_native = use_native and ((synchronization_serial * 1103515245 + 12345) & 0xffff) >= 32768
	if use_native:
		first = int(query_kernel.synchronize_spatial_units_prefix(units, unit_index_by_id, unit_entities, unit_positions, unit_cells, unit_buckets, cell_size))
		if first < 0 or first > units.size(): first = 0
		native_sync_units += first
		if first == units.size():
			synchronization_tick_native = true
			native_sync_calls += 1
			if performance_probe != null: performance_probe.observe_microseconds("simulation.spatial.sync.native", Time.get_ticks_usec() - started)
			return true
		native_sync_fallbacks += 1
	script_sync_calls += 1
	var valid := _synchronize_active_units_reference(units if first == 0 else units.slice(first))
	if performance_probe != null: performance_probe.observe_microseconds("simulation.spatial.sync.mixed" if first > 0 else "simulation.spatial.sync.script", Time.get_ticks_usec() - started)
	return valid


func _synchronize_active_units_reference(units: Array) -> bool:
	# Lifecycle changes are handled by the world's dirty flag. Between those
	# boundaries only active units can have moved, so update their dense slots
	# directly instead of walking the complete authoritative roster.
	for unit_value in units:
		var unit: Dictionary = unit_value
		if float(unit.get("hp", 0.0)) <= 0.0:
			return false
		var entity_id := int(unit.get("id", -1))
		if not unit_index_by_id.has(entity_id):
			return false
		var unit_index := int(unit_index_by_id[entity_id])
		if unit_index < 0 or unit_index >= unit_entities.size() or int(unit_entities[unit_index].get("id", -1)) != entity_id:
			return false
		_update_unit_slot(unit_index, Vector2(unit.get("pos", Vector2.ZERO)))
	return true


func _update_unit_slot(unit_index: int, position: Vector2) -> void:
	if unit_positions[unit_index] == position:
		return
	var next_cell := cell_for(position)
	var previous_cell := unit_cells[unit_index]
	unit_positions[unit_index] = position
	if next_cell == previous_cell:
		return
	var previous_bucket: Array = unit_buckets.get(previous_cell, [])
	previous_bucket.erase(unit_index)
	if previous_bucket.is_empty():
		unit_buckets.erase(previous_cell)
	if not unit_buckets.has(next_cell):
		unit_buckets[next_cell] = []
	unit_buckets[next_cell].append(unit_index)
	unit_cells[unit_index] = next_cell


func movement_neighbor_radius(entity: Dictionary) -> float:
	# LocalMovement reacts only inside 1.6 times the combined footprint and
	# clearance. query_neighbors adds each candidate radius itself, so this
	# conservative bound includes every potentially contributing unit without
	# scanning the former arbitrary extra world unit.
	return (
		1.6 * float(entity["footprint_radius"])
		+ 0.6 * maximum_unit_radius
		+ 1.6 * maximum_unit_clearance
	)
func has_friendly_gatherer(unit: Dictionary, radius: float) -> bool:
	if query_kernel != null and query_kernel.has_method("spatial_unit_match"):
		var found: int = query_kernel.spatial_unit_match(unit, radius, 0, unit_buckets, unit_entities, unit_positions, unit_radii, cell_size, maximum_unit_radius)
		if found >= 0: return found != 0
	for other in _query_unit_circle(unit["pos"], radius):
		if int(other["id"]) != int(unit["id"]) and String(other.get("task", "")) == "gather" and int(other.get("team", 0)) == int(unit["team"]): return true
	return false


func has_live_overlap(unit: Dictionary, radius: float) -> bool:
	if query_kernel != null and query_kernel.has_method("spatial_unit_match"):
		var found: int = query_kernel.spatial_unit_match(unit, radius, 1, unit_buckets, unit_entities, unit_positions, unit_radii, cell_size, maximum_unit_radius)
		if found >= 0: return found != 0
	for other in _query_unit_circle(unit["pos"], radius):
		if int(other["id"]) == int(unit["id"]) or String(other.get("movement_domain", "land")) != String(unit.get("movement_domain", "land")) or float(other.get("hp", 0.0)) <= 0.0: continue
		var separation := float(unit["footprint_radius"]) + float(other["footprint_radius"])
		if Vector2(unit["pos"]).distance_squared_to(Vector2(other["pos"])) < separation * separation - 0.00001: return true
	return false


func query_circle(center: Vector2, radius: float, category: String = "") -> Array:
	if category == "unit":
		return _query_unit_circle(center, radius)
	var result: Array = []
	var seen: Dictionary = {}
	var minimum := cell_for(center - Vector2.ONE * radius)
	var maximum := cell_for(center + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for item in buckets.get(Vector2i(x, y), []):
				if category != "" and item["category"] != category:
					continue
				var unique_key := _unique_key(item)
				if seen.has(unique_key):
					continue
				var allowed_distance: float = radius + float(item["radius"])
				if center.distance_squared_to(item["position"]) <= allowed_distance * allowed_distance:
					seen[unique_key] = true
					result.append(item["entity"])
	if category.is_empty():
		result.append_array(_query_unit_circle(center, radius))
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result

func query_aabb(rectangle: Rect2, category: String = "") -> Array:
	if category == "unit":
		return _query_unit_aabb(rectangle)
	var result: Array = []
	var seen: Dictionary = {}
	var minimum := cell_for(rectangle.position)
	var maximum := cell_for(rectangle.end)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for item in buckets.get(Vector2i(x, y), []):
				if category != "" and item["category"] != category:
					continue
				var unique_key := _unique_key(item)
				if seen.has(unique_key) or not rectangle.grow(float(item["radius"])).has_point(item["position"]):
					continue
				seen[unique_key] = true
				result.append(item["entity"])
	if category.is_empty():
		result.append_array(_query_unit_aabb(rectangle))
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result


func has_external_unit_in_aabb(rectangle: Rect2, formation_group_id: int) -> bool:
	# Formation cohesion only needs to know whether an external unit exists.
	# Avoid allocating and ID-sorting a complete result array for this boolean
	# broad-phase query, and stop on the first relevant candidate.
	var expanded := rectangle.grow(maximum_unit_radius)
	var minimum := cell_for(expanded.position)
	var maximum := cell_for(expanded.end)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for unit_index in unit_buckets.get(Vector2i(x, y), []):
				var candidate: Dictionary = unit_entities[unit_index]
				if int(candidate.get("formation_group_id", -1)) == formation_group_id:
					continue
				if rectangle.grow(unit_radii[unit_index]).has_point(unit_positions[unit_index]):
					return true
	return false

func query_neighbors(entity: Dictionary, radius: float, category: String = "unit") -> Array:
	var result: Array = []
	query_neighbors_into(entity, radius, category, result)
	return result


func query_neighbors_into(entity: Dictionary, radius: float, category: String, result: Array) -> void:
	# Movement calls this for every mobile entity on every fixed tick. Avoid the
	# generic query's String keys, per-call de-duplication Dictionary and the
	# second Array created by filter(). IDs are unique inside one requested
	# category, and final ID sorting preserves deterministic avoidance order.
	result.clear()
	if category != "unit":
		for candidate in query_circle(entity["pos"], radius, category):
			if int(candidate.get("id", -1)) != int(entity["id"]):
				result.append(candidate)
		return
	if native_neighbors_enabled and native_neighbors_supported and query_kernel.spatial_unit_neighbors(entity, radius, null, unit_buckets, unit_entities, unit_positions, unit_radii, cell_size, maximum_unit_radius, result): return
	var center: Vector2 = entity["pos"]
	var entity_id := int(entity["id"])
	var last_candidate_id := -9223372036854775807
	var already_sorted := true
	var bucket_radius := radius + maximum_unit_radius
	var minimum := cell_for(center - Vector2.ONE * bucket_radius)
	var maximum := cell_for(center + Vector2.ONE * bucket_radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for unit_index in unit_buckets.get(Vector2i(x, y), []):
				var candidate: Dictionary = unit_entities[unit_index]
				var candidate_id := int(candidate["id"])
				if candidate_id == entity_id:
					continue
				var allowed_distance: float = radius + unit_radii[unit_index]
				if center.distance_squared_to(unit_positions[unit_index]) > allowed_distance * allowed_distance:
					continue
				if candidate_id < last_candidate_id:
					already_sorted = false
				last_candidate_id = candidate_id
				result.append(candidate)
	if not already_sorted:
		result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))


func query_external_neighbors_into(entity: Dictionary, radius: float, formation_group_id: int, result: Array) -> void:
	# A rigidly translating formation preserves every internal pair distance.
	# Only entities outside that proven shared-motion group can influence local
	# avoidance. Keep the same stable-ID result contract as query_neighbors_into.
	result.clear()
	if native_neighbors_enabled and native_neighbors_supported and query_kernel.spatial_unit_neighbors(entity, radius, formation_group_id, unit_buckets, unit_entities, unit_positions, unit_radii, cell_size, maximum_unit_radius, result): return
	var center: Vector2 = entity["pos"]
	var entity_id := int(entity["id"])
	var last_candidate_id := -9223372036854775807
	var already_sorted := true
	var bucket_radius := radius + maximum_unit_radius
	var minimum := cell_for(center - Vector2.ONE * bucket_radius)
	var maximum := cell_for(center + Vector2.ONE * bucket_radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for unit_index in unit_buckets.get(Vector2i(x, y), []):
				var candidate: Dictionary = unit_entities[unit_index]
				var candidate_id := int(candidate["id"])
				if candidate_id == entity_id or int(candidate.get("formation_group_id", -1)) == formation_group_id:
					continue
				var allowed_distance: float = radius + unit_radii[unit_index]
				if center.distance_squared_to(unit_positions[unit_index]) > allowed_distance * allowed_distance:
					continue
				if candidate_id < last_candidate_id:
					already_sorted = false
				last_candidate_id = candidate_id
				result.append(candidate)
	if not already_sorted:
		result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))


func _query_unit_circle(center: Vector2, radius: float) -> Array:
	var started := Time.get_ticks_usec() if performance_probe != null else 0
	var result: Array = []
	var use_native := native_neighbors_enabled and native_circle_supported
	if profile_circle_alternatives and performance_probe != null:
		circle_profile_sequence += 1
		use_native = use_native and circle_profile_sequence % 2 == 0
	if use_native and query_kernel.spatial_unit_circle(center, radius, unit_buckets, unit_entities, unit_positions, unit_radii, cell_size, maximum_unit_radius, result):
		if performance_probe != null: performance_probe.observe_microseconds("simulation.spatial.circle.native", Time.get_ticks_usec() - started)
		return result
	var query_radius := maxf(0.0, radius)
	var bucket_radius := query_radius + maximum_unit_radius
	var minimum := cell_for(center - Vector2.ONE * bucket_radius)
	var maximum := cell_for(center + Vector2.ONE * bucket_radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for unit_index in unit_buckets.get(Vector2i(x, y), []):
				var allowed_distance := query_radius + unit_radii[unit_index]
				if center.distance_squared_to(unit_positions[unit_index]) <= allowed_distance * allowed_distance:
					result.append(unit_entities[unit_index])
	result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	if performance_probe != null: performance_probe.observe_microseconds("simulation.spatial.circle.script", Time.get_ticks_usec() - started)
	return result


func _query_unit_aabb(rectangle: Rect2) -> Array:
	var result: Array = []
	var expanded := rectangle.grow(maximum_unit_radius)
	var minimum := cell_for(expanded.position)
	var maximum := cell_for(expanded.end)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for unit_index in unit_buckets.get(Vector2i(x, y), []):
				if rectangle.grow(unit_radii[unit_index]).has_point(unit_positions[unit_index]):
					result.append(unit_entities[unit_index])
	result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))
	return result


func _unique_key(item: Dictionary) -> String:
	return "%s:%d" % [item["category"], int(item["entity"].get("id", -1))]

func cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))
