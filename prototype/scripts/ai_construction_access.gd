extends RefCounted

const Footprint := preload("res://scripts/footprint.gd")
const OFFSETS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const MARGIN := 6
const MAX_FOOTPRINT_CELLS := 256


# One detached legal observation, shared by all workers and sites in this plan.
# Unknown terrain and hidden changes never enter this index.
static func prepare(navigation: Dictionary) -> Dictionary:
	if not bool(navigation.get("cell_geometry", false)):
		return {}
	# Navigation publications already have immutable row-major point arrays.
	# Retain that detached array; a construction decision must not rebuild an
	# index of every explored cell on a large map.
	return {"_ordered_land": navigation.get("land", [])}


static func local_cells(context: Dictionary, minimum: Vector2i, maximum: Vector2i) -> Dictionary:
	if not context.has("_ordered_land"):
		return context
	var points: Array = context["_ordered_land"]
	var result: Dictionary = {}
	for y in range(minimum.y, maximum.y + 1):
		var lower := Vector2(minimum.x + 0.5, y + 0.5)
		var first := 0
		var last := points.size()
		while first < last:
			var middle: int = (first + last) / 2
			var point: Vector2 = points[middle]
			if point.y < lower.y or (point.y == lower.y and point.x < lower.x):
				first = middle + 1
			else:
				last = middle
		while first < points.size():
			var point: Vector2 = points[first]
			if point.y != lower.y or point.x > float(maximum.x) + 0.5:
				break
			result[Vector2i(point.floor())] = true
			first += 1
	return result


static func preserves(site: Vector2, half_size: Vector2, context: Dictionary) -> bool:
	var cells := Footprint.occupied_cells(site, half_size)
	if cells.is_empty() or cells.size() > MAX_FOOTPRINT_CELLS:
		return false
	var blocked: Dictionary = {}
	var minimum: Vector2i = cells[0]
	var maximum: Vector2i = cells[0]
	for cell in cells:
		blocked[cell] = true
		minimum = minimum.min(cell)
		maximum = maximum.max(cell)
	var land := local_cells(context, minimum - Vector2i.ONE * MARGIN, maximum + Vector2i.ONE * MARGIN)
	# Open surroundings are the common case: no local graph search is needed.
	var open_ring := true
	for y in range(minimum.y - 1, maximum.y + 2):
		for x in range(minimum.x - 1, maximum.x + 2):
			if x in [minimum.x - 1, maximum.x + 1] or y in [minimum.y - 1, maximum.y + 1]:
				if not land.has(Vector2i(x, y)):
					open_ring = false
	if open_ring:
		return true
	var rim: Dictionary = {}
	for cell in cells:
		for offset in OFFSETS:
			var next: Vector2i = cell + offset
			if not blocked.has(next) and land.has(next):
				rim[next] = true
	if rim.size() < 2:
		return true
	minimum -= Vector2i.ONE * MARGIN
	maximum += Vector2i.ONE * MARGIN
	var after := labels(rim, land, blocked, minimum, maximum)
	var first: int = int(after[rim.keys()[0]])
	if rim.keys().all(func(cell): return int(after[cell]) == first):
		return true
	var before := labels(rim, land, {}, minimum, maximum)
	var surviving: Dictionary = {}
	for cell in rim:
		var component: int = int(before[cell])
		if surviving.has(component) and int(surviving[component]) != int(after[cell]):
			return false
		surviving[component] = after[cell]
	return true


# Only a fixed neighbourhood is searched. Rejection can be conservative when
# a known alternative runs farther away, but never relies on unexplored land.
static func labels(rim: Dictionary, land: Dictionary, blocked: Dictionary, minimum: Vector2i, maximum: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	var component := 0
	for start in rim:
		if result.has(start):
			continue
		component += 1
		result[start] = component
		var queue: Array[Vector2i] = [start]
		var head := 0
		while head < queue.size():
			var cell := queue[head]
			head += 1
			for offset in OFFSETS:
				var next: Vector2i = cell + offset
				if next.x < minimum.x or next.y < minimum.y or next.x > maximum.x or next.y > maximum.y:
					continue
				if result.has(next) or blocked.has(next) or not land.has(next):
					continue
				result[next] = component
				queue.append(next)
	return result
