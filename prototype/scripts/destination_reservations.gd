class_name RoRDestinationReservations

var reservations: Dictionary = {}


func clear() -> void:
	reservations.clear()


func release(entity_id: int) -> void:
	reservations.erase(entity_id)


func reserve(entity_id: int, desired: Vector2, radius: float, navigation_grid, group_id: int = -1, movement_domain: String = "land", restriction_id: int = -1) -> Vector2:
	release(entity_id)
	if _is_available(desired, radius, navigation_grid, movement_domain, restriction_id):
		reservations[entity_id] = {"position": desired, "radius": radius, "group_id": group_id}
		return desired
	var desired_cell := Vector2i(floori(desired.x), floori(desired.y))
	var maximum_radius := maxi(navigation_grid.size.x, navigation_grid.size.y) if navigation_grid != null else 4
	for ring in range(1, maximum_radius + 1):
		var ring_candidates: Array[Vector2] = []
		for y in range(desired_cell.y - ring, desired_cell.y + ring + 1):
			for x in range(desired_cell.x - ring, desired_cell.x + ring + 1):
				if absi(x - desired_cell.x) != ring and absi(y - desired_cell.y) != ring:
					continue
				ring_candidates.append(Vector2(x + 0.5, y + 0.5))
		ring_candidates.sort_custom(func(left, right):
			var left_distance: float = left.distance_squared_to(desired)
			var right_distance: float = right.distance_squared_to(desired)
			return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and (left.y < right.y or (left.y == right.y and left.x < right.x))))
		for candidate in ring_candidates:
			if _is_available(candidate, radius, navigation_grid, movement_domain, restriction_id):
				reservations[entity_id] = {"position": candidate, "radius": radius, "group_id": group_id}
				return candidate
	return desired


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
	for existing in reservations.values():
		var minimum_distance := radius + float(existing["radius"]) + 0.02
		if position.distance_squared_to(existing["position"]) < minimum_distance * minimum_distance:
			return false
	return true
