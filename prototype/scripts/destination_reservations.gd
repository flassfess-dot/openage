class_name RoRDestinationReservations

const BUCKET_SIZE := 2.0

var reservations: Dictionary = {}
var reservation_buckets: Dictionary = {}
var reservation_cells: Dictionary = {}
var maximum_reserved_radius: float = 0.0
var cached_ring_desired: Variant = null
var cached_ring_offsets: Array = []
var cached_search_signature: Array = []
var cached_search_ring: int = 0
var cached_search_offset_index: int = -1


func clear() -> void:
	reservations.clear()
	reservation_buckets.clear()
	reservation_cells.clear()
	maximum_reserved_radius = 0.0
	cached_ring_desired = null
	cached_ring_offsets.clear()
	_invalidate_search_cursor()


func release(entity_id: int) -> void:
	var released := reservations.has(entity_id)
	if reservation_cells.has(entity_id):
		var cell: Vector2i = reservation_cells[entity_id]
		var bucket: Array = reservation_buckets.get(cell, [])
		bucket.erase(entity_id)
		if bucket.is_empty():
			reservation_buckets.erase(cell)
		reservation_cells.erase(entity_id)
	reservations.erase(entity_id)
	if released:
		_invalidate_search_cursor()


func reserve(entity_id: int, desired: Vector2, radius: float, navigation_grid, group_id: int = -1, movement_domain: String = "land", restriction_id: int = -1) -> Vector2:
	release(entity_id)
	var signature := [desired, radius, movement_domain, restriction_id, int(navigation_grid.revision) if navigation_grid != null else -1]
	var continues_search := signature == cached_search_signature
	if not continues_search:
		cached_search_signature = signature
		cached_search_ring = 0
		cached_search_offset_index = -1
	if _is_available(desired, radius, navigation_grid, movement_domain, restriction_id):
		_store(entity_id, desired, radius, group_id)
		cached_search_ring = 0
		cached_search_offset_index = -1
		return desired
	var desired_cell := Vector2i(floori(desired.x), floori(desired.y))
	var maximum_radius := maxi(navigation_grid.size.x, navigation_grid.size.y) if navigation_grid != null else 4
	var first_ring := maxi(1, cached_search_ring) if continues_search else 1
	for ring in range(first_ring, maximum_radius + 1):
		var offsets := _ring_offsets(desired, ring)
		var first_offset := cached_search_offset_index + 1 if continues_search and ring == cached_search_ring else 0
		for offset_index in range(first_offset, offsets.size()):
			var offset: Vector2 = offsets[offset_index]
			var candidate := Vector2(desired_cell) + Vector2(offset)
			if _is_available(candidate, radius, navigation_grid, movement_domain, restriction_id):
				_store(entity_id, candidate, radius, group_id)
				cached_search_ring = ring
				cached_search_offset_index = offset_index
				return candidate
	return desired


func _invalidate_search_cursor() -> void:
	cached_search_signature.clear()
	cached_search_ring = 0
	cached_search_offset_index = -1


func _ring_offsets(desired: Vector2, ring: int) -> Array:
	if cached_ring_desired == null or Vector2(cached_ring_desired) != desired:
		cached_ring_desired = desired
		cached_ring_offsets.clear()
	var fractional := desired - Vector2(floorf(desired.x), floorf(desired.y))
	while cached_ring_offsets.size() < ring:
		var next_ring := cached_ring_offsets.size() + 1
		var offsets: Array[Vector2] = []
		for y in range(-next_ring, next_ring + 1):
			for x in range(-next_ring, next_ring + 1):
				if absi(x) != next_ring and absi(y) != next_ring:
					continue
				offsets.append(Vector2(x + 0.5, y + 0.5))
		offsets.sort_custom(func(left: Vector2, right: Vector2):
			var left_distance: float = (left - fractional).length_squared()
			var right_distance: float = (right - fractional).length_squared()
			return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left.y < right.y or (left.y == right.y and left.x < right.x))))
		cached_ring_offsets.append(offsets)
	return cached_ring_offsets[ring - 1]


func _store(entity_id: int, position: Vector2, radius: float, group_id: int) -> void:
	reservations[entity_id] = {"position": position, "radius": radius, "group_id": group_id}
	var cell := _bucket_cell(position)
	var bucket: Array = reservation_buckets.get(cell, [])
	bucket.append(entity_id)
	reservation_buckets[cell] = bucket
	reservation_cells[entity_id] = cell
	maximum_reserved_radius = maxf(maximum_reserved_radius, radius)


func assigned_position(entity_id: int) -> Variant:
	if not reservations.has(entity_id):
		return null
	return reservations[entity_id]["position"]


func is_occupied(entity: Dictionary) -> bool:
	var reservation = assigned_position(int(entity.get("id", -1)))
	if reservation == null:
		return true
	var tolerance := maxf(0.035, float(entity.get("footprint_radius", 0.3)) * 0.2)
	return entity["pos"].distance_squared_to(reservation) <= tolerance * tolerance


func _is_available(position: Vector2, radius: float, navigation_grid, movement_domain: String = "land", restriction_id: int = -1) -> bool:
	if navigation_grid != null and not navigation_grid.is_position_walkable_for(position, radius, movement_domain, restriction_id):
		return false
	var reach := radius + maximum_reserved_radius + 0.02
	var minimum_cell := _bucket_cell(position - Vector2(reach, reach))
	var maximum_cell := _bucket_cell(position + Vector2(reach, reach))
	for y in range(minimum_cell.y, maximum_cell.y + 1):
		for x in range(minimum_cell.x, maximum_cell.x + 1):
			for entity_id in reservation_buckets.get(Vector2i(x, y), []):
				var existing: Dictionary = reservations.get(entity_id, {})
				if existing.is_empty():
					continue
				var minimum_distance := radius + float(existing["radius"]) + 0.02
				if position.distance_squared_to(existing["position"]) < minimum_distance * minimum_distance:
					return false
	return true


func _bucket_cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / BUCKET_SIZE), floori(position.y / BUCKET_SIZE))
