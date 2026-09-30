class_name RoRAiResourceSpatialIndex
extends RefCounted

# AI resource selection does not need the simulation collision grid's very
# small buckets. Coarser immutable buckets keep planner queries cheap while the
# exact distance and entity-ID comparison below preserve deterministic choices.

const CELL_SIZE := 8.0

var bucket_lists_by_domain: Dictionary = {}


func rebuild(resources: Array, movement_domains: Array, empty_domains_are_unrestricted: bool = true) -> void:
	bucket_lists_by_domain.clear()
	var unique_domains: Dictionary = {}
	for domain_value in movement_domains:
		unique_domains[String(domain_value)] = true
	var domains: Array = unique_domains.keys()
	domains.sort()
	var bucket_maps: Dictionary = {}
	for domain in domains:
		bucket_maps[domain] = {}
	for resource_order in range(resources.size()):
		var resource: Dictionary = resources[resource_order]
		var allowed_domains: Array = resource.get("allowed_gatherer_domains", [])
		for domain_value in domains:
			var domain := String(domain_value)
			if not allowed_domains.is_empty() and domain not in allowed_domains:
				continue
			if allowed_domains.is_empty() and not empty_domains_are_unrestricted and domain != "land":
				continue
			var cell := _cell(Vector2(resource.get("pos", Vector2.ZERO)))
			var domain_buckets: Dictionary = bucket_maps[domain]
			if not domain_buckets.has(cell):
				domain_buckets[cell] = []
			domain_buckets[cell].append({"resource": resource, "order": resource_order})
	for domain_value in domains:
		var domain := String(domain_value)
		var bucket_list: Array = []
		var domain_buckets: Dictionary = bucket_maps[domain]
		for cell_value in domain_buckets.keys():
			bucket_list.append({"cell": Vector2i(cell_value), "entries": domain_buckets[cell_value]})
		bucket_list.sort_custom(func(left, right):
			var left_cell: Vector2i = left["cell"]
			var right_cell: Vector2i = right["cell"]
			return left_cell.y < right_cell.y or (left_cell.y == right_cell.y and left_cell.x < right_cell.x)
		)
		bucket_lists_by_domain[domain] = bucket_list


func nearest(position: Vector2, movement_domain: String) -> Variant:
	var buckets: Array = bucket_lists_by_domain.get(movement_domain, [])
	if buckets.is_empty():
		return null
	var nearest_bucket_index := 0
	var nearest_bucket_distance := INF
	for index in range(buckets.size()):
		var lower_bound := _distance_squared_to_cell(position, buckets[index]["cell"])
		if lower_bound < nearest_bucket_distance:
			nearest_bucket_distance = lower_bound
			nearest_bucket_index = index

	var upper_bound_distance := INF
	for entry_value in buckets[nearest_bucket_index]["entries"]:
		var entry: Dictionary = entry_value
		var resource: Dictionary = entry["resource"]
		upper_bound_distance = minf(upper_bound_distance, position.distance_squared_to(Vector2(resource.get("pos", Vector2.ZERO))))
	var candidates: Array = []
	for index in range(buckets.size()):
		var lower_bound := _distance_squared_to_cell(position, buckets[index]["cell"])
		if lower_bound > upper_bound_distance and not is_equal_approx(lower_bound, upper_bound_distance):
			continue
		candidates.append_array(buckets[index]["entries"])
	# The legacy scan used snapshot resource order. Preserve that order before
	# applying its approximate-distance tie rule so bucket layout cannot change a
	# deterministic AI decision on nearly equidistant nodes.
	candidates.sort_custom(func(left, right): return int(left["order"]) < int(right["order"]))
	var best_resource: Variant = null
	var best_distance := INF
	var best_id := 2147483647
	for entry_value in candidates:
		var resource: Dictionary = entry_value["resource"]
		var distance := position.distance_squared_to(Vector2(resource.get("pos", Vector2.ZERO)))
		var resource_id := int(resource.get("id", -1))
		if distance < best_distance - 0.000001 or (is_equal_approx(distance, best_distance) and resource_id < best_id):
			best_resource = resource
			best_distance = distance
			best_id = resource_id
	return best_resource


static func _distance_squared_to_cell(position: Vector2, cell: Vector2i) -> float:
	var minimum := Vector2(cell) * CELL_SIZE
	var maximum := minimum + Vector2.ONE * CELL_SIZE
	var delta_x := maxf(maxf(minimum.x - position.x, 0.0), position.x - maximum.x)
	var delta_y := maxf(maxf(minimum.y - position.y, 0.0), position.y - maximum.y)
	return delta_x * delta_x + delta_y * delta_y


static func _cell(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))
