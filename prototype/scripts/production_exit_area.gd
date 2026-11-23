extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")
const STEPS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const CENTER := Vector2(0.5, 0.5)

var signature: Array
var radius: float
var domain: String
var restriction: int
var bounds: Rect2i
var points: Array[Vector2i] = []
var regions: Dictionary = {}
var region_anchors: Array[Vector2i] = []
var outlets: Array[Vector2i] = []


func _init(world, building: Dictionary, kind: String, stamp: Array) -> void:
	signature = stamp
	var stats: Dictionary = world.unit_stats(kind)
	radius = Footprint.mobile(kind, stats)["movement_radius"]
	var source: Dictionary = world.object_record_for(kind, int(building.get("team", 0)))
	restriction = int(source.get("links", {}).get("terrain_restriction", stats.get("terrain_restriction", -1)))
	domain = "water" if restriction == 3 else "land"
	var cells: Array = building.get("occupied_cells", [])
	if cells.is_empty():
		cells = Footprint.occupied_cells(building["pos"], building.get("footprint", {}).get("half_size", CENTER))
	if cells.is_empty(): return
	var low := Vector2i(cells[0])
	var high := low
	for cell in cells:
		low = low.min(cell)
		high = high.max(cell)
	var foundation := Rect2i(low, high - low + Vector2i.ONE)
	var face := maxi(1, ceili(radius + 0.5))
	var reach := 3 if domain == "water" else 2
	# The outer line is beyond every berth, even for the largest hull.
	var perimeter := foundation.grow(face + reach + 2)
	bounds = perimeter.intersection(Rect2i(Vector2i.ZERO, world.get_map_size()))
	var mouths: Array[Vector2i] = []
	for x in range(low.x, high.x + 1):
		mouths.append(Vector2i(x, low.y - face))
		mouths.append(Vector2i(x, high.y + face))
	for y in range(low.y, high.y + 1):
		mouths.append(Vector2i(low.x - face, y))
		mouths.append(Vector2i(high.x + face, y))
	var planner = world.pathfinder
	var seeds: Array[Vector2i] = []
	for cell in mouths:
		if bounds.has_point(cell) and planner.is_position_walkable(Vector2(cell) + CENTER, radius, domain, restriction):
			seeds.append(cell)
	if seeds.is_empty(): return

	var open: Dictionary = {}
	for y in range(bounds.position.y, bounds.end.y):
		var row: Array[Vector2] = []
		for x in range(bounds.position.x, bounds.end.x):
			row.append(Vector2(x, y) + CENTER)
		var fits: PackedByteArray = planner.position_walkability(row, radius, domain, restriction)
		for i in range(row.size()):
			if fits[i]: open[Vector2i(row[i])] = true

	# A berth must be reachable from a face of this building. Moving the
	# search out by several cells must never jump a wall or a strip of beach.
	var distance: Dictionary = {}
	var queue := seeds.duplicate()
	for cell in seeds: distance[cell] = 0
	for cell in queue:
		var depth := int(distance[cell])
		if depth >= reach: continue
		for step: Vector2i in STEPS:
			var next: Vector2i = cell + step
			if open.has(next) and not distance.has(next):
				distance[next] = depth + 1
				queue.append(next)

	var sizes: Array[int] = []
	var roomy: Dictionary = {}
	var inner := perimeter.grow(-1)
	for seed_cell in seeds:
		if regions.has(seed_cell): continue
		var region := sizes.size()
		var connected: Array[Vector2i] = [seed_cell]
		var exits_before := outlets.size()
		regions[seed_cell] = region
		# Consecutive cardinal cell centres sweep a clear circle whenever it
		# fits at both ends: a blocked unit square cannot lie between them.
		for cell in connected:
			if not inner.has_point(cell): outlets.append(cell)
			for step: Vector2i in STEPS:
				var next := cell + step
				if open.has(next) and not regions.has(next):
					regions[next] = region
					connected.append(next)
		sizes.append(connected.size())
		if outlets.size() == exits_before: continue
		region_anchors.append(seed_cell)
		for cell in connected:
			if not distance.has(cell): continue
			points.append(cell)
			roomy[cell] = planner.is_position_walkable(Vector2(cell) + CENTER, radius + 0.5, domain, restriction)
	var water_sizes := {}
	if domain == "water" and region_anchors.size() > 1:
		var by_anchor: Dictionary = planner.component_sizes_at(region_anchors, domain, restriction, radius)
		for anchor in by_anchor: water_sizes[regions[anchor]] = by_anchor[anchor]
	points.sort_custom(func(a, b):
		if water_sizes.get(regions[a], 0) != water_sizes.get(regions[b], 0):
			return int(water_sizes[regions[a]]) > int(water_sizes[regions[b]])
		var size_a := sizes[int(regions[a])]
		var size_b := sizes[int(regions[b])]
		if size_a != size_b: return size_a > size_b
		if roomy[a] != roomy[b]: return bool(roomy[a])
		if distance[a] != distance[b]: return int(distance[a]) < int(distance[b])
		return a.y < b.y if a.y != b.y else a.x < b.x)


func choose(world, building: Dictionary) -> Variant:
	if points.is_empty(): return null
	var available: Dictionary = {}
	var blocked: Dictionary = {}
	var edges: Dictionary = {}
	var traffic: Array = world.spatial_index.query_aabb(Rect2(bounds).grow(radius + world.spatial_index.maximum_unit_clearance + Footprint.DEFAULT_CLEARANCE), "unit")
	for unit in traffic:
		if float(unit.get("hp", 0.0)) <= 0.0: continue
		_mark_traffic(unit, blocked, edges)
	if not blocked.is_empty() or not edges.is_empty():
		var queue: Array[Vector2i] = []
		for cell in outlets:
			if not blocked.has(cell):
				queue.append(cell)
				available[cell] = true
		for cell in queue:
			for step: Vector2i in STEPS:
				var next := cell + step
				if available.has(next) or blocked.has(next) or not regions.has(next): continue
				if edges.has(_edge_key(cell, next)): continue
				queue.append(next)
				available[next] = true
		if available.is_empty(): return null

	var preferred := _rally_regions(world.pathfinder, building)
	var rally: Vector2 = building.get("rally_point", building["pos"])
	var has_rally := rally.distance_squared_to(building["pos"]) > 0.04
	var first_region := -1
	var nearest: Variant = null
	var best_distance := INF
	var direct: Variant = null
	var direct_distance := INF
	for cell in points:
		if not available.is_empty() and not available.has(cell): continue
		var region := int(regions[cell])
		if not preferred.is_empty() and not preferred.has(region): continue
		var pos := Vector2(cell) + CENTER
		if not has_rally: return pos
		if first_region < 0: first_region = region
		if preferred.is_empty() and region != first_region: continue
		var distance := pos.distance_squared_to(rally)
		if distance < best_distance:
			nearest = pos
			best_distance = distance
		# Movement plans around fixed obstructions. Choose the rally-facing
		# side with a clear departure past both the building and idle units.
		if distance >= direct_distance: continue
		var ahead := pos.move_toward(rally, 6.0)
		if _clear_departure(world.pathfinder, pos, ahead, traffic):
			direct = pos
			direct_distance = distance
	return direct if direct != null else nearest


func _clear_departure(planner, start: Vector2, end: Vector2, traffic: Array) -> bool:
	if start.is_equal_approx(end): return true
	if not planner.is_segment_walkable(start, end, radius, domain, restriction): return false
	for unit in traffic:
		if float(unit.get("hp", 0.0)) <= 0.0: continue
		var center := Vector2(unit["pos"])
		var closest := Geometry2D.get_closest_point_to_segment(center, start, end)
		if closest.distance_squared_to(center) < _separation_squared(unit): return false
	return true


func _rally_regions(planner, building: Dictionary) -> Dictionary:
	var result := {}
	var rally: Vector2 = building.get("rally_point", building["pos"])
	if region_anchors.size() < 2 or rally.distance_squared_to(building["pos"]) <= 0.04: return result
	var goal: int = planner.component_id(Vector2i(rally.floor()), domain, restriction, radius)
	if goal < 0: return result
	for anchor in region_anchors:
		if planner.component_id(anchor, domain, restriction, radius) == goal:
			result[regions[anchor]] = true
	return result


func _edge_key(a: Vector2i, b: Vector2i) -> Vector3i:
	return Vector3i(mini(a.x, b.x), mini(a.y, b.y), int(a.x == b.x))


func _mark_traffic(unit: Dictionary, blocked: Dictionary, edges: Dictionary) -> void:
	var pos: Vector2 = unit["pos"]
	var gap_squared := _separation_squared(unit)
	var extent := Vector2.ONE * (sqrt(gap_squared) + 1.0)
	var low := bounds.position.max(Vector2i((pos - extent).floor()))
	var high := bounds.end.min(Vector2i((pos + extent).ceil()))
	for y in range(low.y, high.y):
		for x in range(low.x, high.x):
			var cell := Vector2i(x, y)
			if not regions.has(cell): continue
			var center := Vector2(cell) + CENTER
			if pos.distance_squared_to(center) < gap_squared: blocked[cell] = true
			for step: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
				var next := cell + step
				if not regions.has(next): continue
				var nearest := Geometry2D.get_closest_point_to_segment(pos, center, center + Vector2(step))
				if pos.distance_squared_to(nearest) < gap_squared:
					edges[_edge_key(cell, next)] = true


func _separation_squared(unit: Dictionary) -> float:
	var separation := radius + float(unit["footprint_radius"]) + maxf(Footprint.DEFAULT_CLEARANCE, float(unit.get("minimum_clearance", 0.0)))
	return separation * separation
