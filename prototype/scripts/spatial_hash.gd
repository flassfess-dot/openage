class_name RoRSpatialHash

var cell_size: float = 2.0
var buckets: Dictionary = {}
var unit_buckets: Dictionary = {}
var unit_entities: Array = []
var unit_positions: Array[Vector2] = []
var unit_radii: Array[float] = []
var maximum_unit_radius: float = 0.0
var maximum_unit_clearance: float = 0.0


func _init(bucket_size: float = 2.0) -> void:
	cell_size = maxf(0.25, bucket_size)

func clear() -> void:
	buckets.clear()
	unit_buckets.clear()
	unit_entities.clear()
	unit_positions.clear()
	unit_radii.clear()
	maximum_unit_radius = 0.0
	maximum_unit_clearance = 0.0

func insert(entity: Dictionary, position: Vector2, radius: float, category: String) -> void:
	if category == "unit":
		var mobile_radius := maxf(0.0, radius)
		maximum_unit_radius = maxf(maximum_unit_radius, mobile_radius)
		maximum_unit_clearance = maxf(maximum_unit_clearance, float(entity.get("minimum_clearance", 0.0)))
		var unit_index := unit_entities.size()
		unit_entities.append(entity)
		unit_positions.append(position)
		unit_radii.append(mobile_radius)
		var unit_cell := cell_for(position)
		if not unit_buckets.has(unit_cell):
			unit_buckets[unit_cell] = []
		unit_buckets[unit_cell].append(unit_index)
		return
	var item := {"entity": entity, "position": position, "radius": maxf(0.0, radius), "category": category}
	var minimum := cell_for(position - Vector2.ONE * item["radius"])
	var maximum := cell_for(position + Vector2.ONE * item["radius"])
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var key := Vector2i(x, y)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(item)


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
	var result: Array = []
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
