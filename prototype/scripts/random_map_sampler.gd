class_name RoRRandomMapSampler
extends RefCounted


static func sample_zone_cells(strategic_zones: Dictionary, size: Vector2i, allowed_zone_ids: Array, target_count: int, minimum_distance: float, seed: int, blocked_cells: Dictionary = {}, existing_anchors: Array[Vector2i] = [], zone_weights: Dictionary = {}, coast_mode: String = "", minimum_start_distance: int = 0) -> Array[Vector2i]:
	var zone_ids: PackedInt32Array = strategic_zones.get("zone_ids", PackedInt32Array())
	var coastal_mask: PackedByteArray = strategic_zones.get("coastal_land_mask", PackedByteArray())
	var start_distances: PackedInt32Array = strategic_zones.get("nearest_start_distances", PackedInt32Array())
	if zone_ids.size() != size.x * size.y or target_count <= 0:
		return []
	var allowed_lookup: Dictionary = {}
	for zone_id_value in allowed_zone_ids:
		allowed_lookup[int(zone_id_value)] = true
	var candidates := PackedInt32Array()
	for index in range(zone_ids.size()):
		if not allowed_lookup.has(int(zone_ids[index])):
			continue
		var cell := Vector2i(index % size.x, index / size.x)
		if cell.x < 2 or cell.y < 2 or cell.x >= size.x - 2 or cell.y >= size.y - 2 or blocked_cells.has(cell):
			continue
		if minimum_start_distance > 0 and start_distances.size() == zone_ids.size() and start_distances[index] >= 0 and start_distances[index] < minimum_start_distance:
			continue
		var coastal := coastal_mask.size() == zone_ids.size() and coastal_mask[index] != 0
		if coast_mode == "coastal" and not coastal:
			continue
		if coast_mode == "inland" and coastal:
			continue
		candidates.append(index)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var value := candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = value
	var bucket_size := maxf(1.0, minimum_distance / sqrt(2.0))
	var bucket_radius := maxi(1, ceili(minimum_distance / bucket_size))
	var buckets: Dictionary = {}
	for anchor in existing_anchors:
		_add_to_bucket(buckets, anchor, bucket_size)
	var result: Array[Vector2i] = []
	for pass_index in range(3):
		for candidate_index in candidates:
			if result.size() >= target_count:
				return result
			var cell := Vector2i(int(candidate_index) % size.x, int(candidate_index) / size.x)
			var zone_id := int(zone_ids[int(candidate_index)])
			var base_weight := clampf(float(zone_weights.get(zone_id, 1.0)), 0.0, 1.0)
			if rng.randf() > minf(1.0, base_weight * float(pass_index + 1)):
				continue
			if _has_nearby_anchor(buckets, cell, bucket_size, bucket_radius, minimum_distance):
				continue
			result.append(cell)
			_add_to_bucket(buckets, cell, bucket_size)
	return result


static func _add_to_bucket(buckets: Dictionary, cell: Vector2i, bucket_size: float) -> void:
	var bucket := Vector2i(floori(float(cell.x) / bucket_size), floori(float(cell.y) / bucket_size))
	if not buckets.has(bucket):
		buckets[bucket] = []
	buckets[bucket].append(cell)


static func _has_nearby_anchor(buckets: Dictionary, cell: Vector2i, bucket_size: float, bucket_radius: int, minimum_distance: float) -> bool:
	var center_bucket := Vector2i(floori(float(cell.x) / bucket_size), floori(float(cell.y) / bucket_size))
	var minimum_squared := minimum_distance * minimum_distance
	for bucket_y in range(center_bucket.y - bucket_radius, center_bucket.y + bucket_radius + 1):
		for bucket_x in range(center_bucket.x - bucket_radius, center_bucket.x + bucket_radius + 1):
			for other_value in buckets.get(Vector2i(bucket_x, bucket_y), []):
				if Vector2(cell).distance_squared_to(Vector2(other_value)) + 0.0001 < minimum_squared:
					return true
	return false
