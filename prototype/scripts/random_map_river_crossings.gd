class_name RoRRandomMapRiverCrossings
extends RefCounted

const Rules := preload("res://scripts/terrain_rules.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const Banks := preload("res://scripts/random_map_river_banks.gd")

static func build(size: Vector2i, terrain: Array[int], fields: Dictionary, rivers: Dictionary, lakes: Array, seed: int) -> Array:
	var lake_cells: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: lake_cells[i] = true
	var candidates: Array = []
	var seen: Dictionary = {}
	var length := 0.0
	for channel in rivers["channels"]:
		var points: PackedVector2Array = channel["points"]
		for i in range(1, points.size()): length += points[i - 1].distance_to(points[i])
		for i in range(3, points.size() - 3, 4):
			if channel["runoff"][i] < rivers["runoff_threshold"] * 1.2: continue
			var center := Vector2i(points[i].floor())
			if Banks.near_fall(rivers,points[i],14.0): continue
			if seen.has(center): continue
			seen[center] = true
			if not Navigation.inside(center, size): continue
			var index := center.y * size.x + center.x
			if lake_cells.has(index) or rivers["mouth_mask"][index] != 0: continue
			var direction := (points[i + 3] - points[i - 3]).normalized()
			var before := (points[i] - points[i - 3]).normalized()
			var after := (points[i + 3] - points[i]).normalized()
			if before.dot(after) < 0.75: continue
			if channel["rockiness"][i] > 0.55: continue
			var normal := Vector2(-direction.y, direction.x)
			var banks: Array[Vector2i] = []
			for side in [-1, 1]:
				for step in range(1, 33):
					var at := Vector2i((Vector2(center) + Vector2.ONE * 0.5 + normal * side * step * 0.25).floor())
					if not Navigation.inside(at, size): break
					var j := at.y * size.x + at.x
					if terrain[j] not in Rules.WATER_TERRAIN_IDS and rivers["mask"][j] == 0:
						banks.append(at)
						break
			if banks.size() != 2 or banks[0] == banks[1]: continue
			var span := Vector2(banks[0]).distance_to(banks[1])
			if span > 7.5: continue
			var a := _level(fields["vertex_levels"], size, banks[0])
			var b := _level(fields["vertex_levels"], size, banks[1])
			if absi(a - b) > 1: continue
			var ribbon := _ribbon(size, terrain, rivers, lake_cells, banks[0], banks[1])
			if ribbon.is_empty(): continue
			candidates.append({"center":center, "bank_a":Vector2(banks[0]) + Vector2.ONE * 0.5,
				"bank_b":Vector2(banks[1]) + Vector2.ONE * 0.5, "cells":ribbon["cells"], "approaches":ribbon["approaches"],
				"basin":channel["basin"], "discharge":channel["runoff"][i], "origin":"curved_river_crossing",
				"half_width":clampf(span*0.16,1.05,1.35),
				"score":span + (1.0 - before.dot(after)) * 3.0 + Topology.roll(center, seed ^ 0xF04D) * 2.0})
	candidates.sort_custom(func(a, b): return a["score"] < b["score"])
	var result: Array = []
	var basins: Dictionary = {}
	var target := clampi(ceili(length / 70.0), 1, maxi(3, mini(size.x, size.y) / 16))
	for phase in range(2):
		for candidate in candidates:
			if result.size() >= target: break
			if phase == 0 and basins.has(candidate["basin"]): continue
			if result.any(func(ford): return Vector2(ford["center"]).distance_to(candidate["center"]) < maxf(12.0, mini(size.x,size.y) * 0.05)): continue
			for cell in candidate["approaches"]: rivers["mask"][cell.y * size.x + cell.x] = 1
			for cell in candidate["cells"]:
				var index: int = cell.y * size.x + cell.x
				rivers["terrain_types"][index] = 4
				terrain[index] = 4
			basins[candidate["basin"]] = true
			var ford: Dictionary = candidate.duplicate()
			ford.erase("score")
			ford.erase("approaches")
			result.append(ford)
	rivers["crossing_candidates"] = candidates.size()
	return result

static func _ribbon(size: Vector2i, terrain: Array[int], rivers: Dictionary, lakes: Dictionary, a: Vector2i, b: Vector2i) -> Dictionary:
	var from := Vector2(a) + Vector2.ONE * 0.5
	var to := Vector2(b) + Vector2.ONE * 0.5
	var direction := (to - from).normalized()
	# A diagonal infantry corridor needs the cell-corner margin as well as
	# the pedestrian footprint. This widens the riffle along the flow only.
	var half_width := clampf(from.distance_to(to)*0.16,1.05,1.35)
	var cells: Array[Vector2i] = []
	var approaches: Array[Vector2i] = []
	var low := 999
	var high := -1
	for y in range(maxi(0, mini(a.y,b.y) - 3), mini(size.y, maxi(a.y,b.y) + 4)):
		for x in range(maxi(0, mini(a.x,b.x) - 3), mini(size.x, maxi(a.x,b.x) + 4)):
			var cell := Vector2i(x,y)
			var point := Vector2(cell) + Vector2.ONE * 0.5
			var closest := Geometry2D.get_closest_point_to_segment(point, from - direction * 1.5, to + direction * 1.5)
			if point.distance_to(closest) > half_width: continue
			var index := y * size.x + x
			if rivers["mouth_mask"][index] != 0 or lakes.has(index): return {}
			approaches.append(cell)
			if terrain[index] not in Rules.WATER_TERRAIN_IDS: continue
			cells.append(cell)
			var level: int = rivers["surface_levels"][index]
			if level < 0: return {}
			low = mini(low, level)
			high = maxi(high, level)
	if cells.is_empty() or high - low > 1: return {}
	return {"cells":cells, "approaches":approaches}

static func _level(levels: Array[int], size: Vector2i, cell: Vector2i) -> int:
	var i := cell.y * (size.x + 1) + cell.x
	return mini(mini(levels[i],levels[i + 1]), mini(levels[i + size.x + 1],levels[i + size.x + 2]))
