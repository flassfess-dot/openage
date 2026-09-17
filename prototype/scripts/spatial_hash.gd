class_name RoRSpatialHash

var cell_size: float = 2.0
var buckets: Dictionary = {}


func _init(bucket_size: float = 2.0) -> void:
	cell_size = maxf(0.25, bucket_size)

func clear() -> void:
	buckets.clear()

func insert(entity: Dictionary, position: Vector2, radius: float, category: String) -> void:
	var item := {"entity": entity, "position": position, "radius": maxf(0.0, radius), "category": category}
	var minimum := cell_for(position - Vector2.ONE * item["radius"])
	var maximum := cell_for(position + Vector2.ONE * item["radius"])
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			var key := Vector2i(x, y)
			if not buckets.has(key):
				buckets[key] = []
			buckets[key].append(item)

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
	# Movement calls this for every mobile entity on every fixed tick. Avoid the
	# generic query's String keys and the second Array created by filter(). IDs
	# are unique inside one requested category, and final ID sorting preserves
	# deterministic avoidance order.
	var result: Array = []
	var seen_ids: Dictionary = {}
	var center: Vector2 = entity.get("pos", Vector2.ZERO)
	var entity_id := int(entity.get("id", -1))
	var minimum := cell_for(center - Vector2.ONE * radius)
	var maximum := cell_for(center + Vector2.ONE * radius)
	for y in range(minimum.y, maximum.y + 1):
		for x in range(minimum.x, maximum.x + 1):
			for item in buckets.get(Vector2i(x, y), []):
				if category != "" and item["category"] != category:
					continue
				var candidate: Dictionary = item["entity"]
				var candidate_id := int(candidate.get("id", -2))
				if candidate_id == entity_id or seen_ids.has(candidate_id):
					continue
				var allowed_distance: float = radius + float(item["radius"])
				if center.distance_squared_to(item["position"]) > allowed_distance * allowed_distance:
					continue
				seen_ids[candidate_id] = true
				result.append(candidate)
	result.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return result

func _unique_key(item: Dictionary) -> String:
	return "%s:%d" % [item["category"], int(item["entity"].get("id", -1))]

func cell_for(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / cell_size), floori(position.y / cell_size))
