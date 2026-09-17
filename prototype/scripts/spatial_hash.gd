class_name RoRSpatialHash

var cell_size: float = 2.0
var buckets: Dictionary = {}
var maximum_unit_radius: float = 0.0
var maximum_unit_clearance: float = 0.0
var neighbor_query_generation: int = 0
var neighbor_seen_generation: Dictionary = {}


func _init(bucket_size: float = 2.0) -> void:
	cell_size = maxf(0.25, bucket_size)

func clear() -> void:
	buckets.clear()
	maximum_unit_radius = 0.0
	maximum_unit_clearance = 0.0
	neighbor_seen_generation.clear()
	neighbor_query_generation = 0

func insert(entity: Dictionary, position: Vector2, radius: float, category: String) -> void:
	var item := {"entity": entity, "position": position, "radius": maxf(0.0, radius), "category": category}
	if category == "unit":
		maximum_unit_radius = maxf(maximum_unit_radius, float(item["radius"]))
		maximum_unit_clearance = maxf(maximum_unit_clearance, float(entity.get("minimum_clearance", 0.0)))
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
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result

func query_aabb(rectangle: Rect2, category: String = "") -> Array:
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
	neighbor_query_generation += 1
	var generation := neighbor_query_generation
	var center: Vector2 = entity["pos"]
	var entity_id := int(entity["id"])
	var last_candidate_id := -9223372036854775807
	var already_sorted := true
	var minimum := cell_for(center - Vector2.ONE * radius)
	var maximum := cell_for(center + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for item in buckets.get(Vector2i(x, y), []):
				if category != "" and item["category"] != category:
					continue
				var candidate: Dictionary = item["entity"]
				var candidate_id := int(candidate["id"])
				if candidate_id == entity_id or int(neighbor_seen_generation.get(candidate_id, 0)) == generation:
					continue
				var allowed_distance: float = radius + float(item["radius"])
				if center.distance_squared_to(item["position"]) > allowed_distance * allowed_distance:
					continue
				neighbor_seen_generation[candidate_id] = generation
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
	neighbor_query_generation += 1
	var generation := neighbor_query_generation
	var center: Vector2 = entity["pos"]
	var entity_id := int(entity["id"])
	var last_candidate_id := -9223372036854775807
	var already_sorted := true
	var minimum := cell_for(center - Vector2.ONE * radius)
	var maximum := cell_for(center + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for item in buckets.get(Vector2i(x, y), []):
				if item["category"] != "unit":
					continue
				var candidate: Dictionary = item["entity"]
				var candidate_id := int(candidate["id"])
				if candidate_id == entity_id or int(candidate.get("formation_group_id", -1)) == formation_group_id or int(neighbor_seen_generation.get(candidate_id, 0)) == generation:
					continue
				var allowed_distance: float = radius + float(item["radius"])
				if center.distance_squared_to(item["position"]) > allowed_distance * allowed_distance:
					continue
				neighbor_seen_generation[candidate_id] = generation
				if candidate_id < last_candidate_id:
					already_sorted = false
				last_candidate_id = candidate_id
				result.append(candidate)
	if not already_sorted:
		result.sort_custom(func(left, right): return int(left["id"]) < int(right["id"]))

func _unique_key(item: Dictionary) -> String:
	return "%s:%d" % [item["category"], int(item["entity"].get("id", -1))]

func cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))
