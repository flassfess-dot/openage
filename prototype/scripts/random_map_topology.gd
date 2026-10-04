class_name RoRRandomMapTopology
extends RefCounted

# RoR land percentages and AoE2 player lands, border fuzziness and neutral
# clumps inform the layout: map-scale silhouette, regional bays, fine detail.
static func prepare(size: Vector2i, starts: Array[Vector2], topology: String, generator: Dictionary, seed: int) -> Dictionary:
	var islands: Array = []
	if topology == "islands":
		var small := String(generator.get("map_type_id", "")) == "small_islands" or String(generator.get("profile", "")).begins_with("small_islands")
		var coverage := 0.27 if small else 0.50
		var radius := sqrt(coverage * float(size.x * size.y) / (PI * float(maxi(1, starts.size()))))
		for i in range(starts.size()):
			var start := starts[i]
			var nearest := INF
			for j in range(starts.size()):
				if i != j: nearest = minf(nearest, start.distance_to(starts[j]))
			var local_seed := seed ^ ((i + 1) * 104729)
			# Clip protrusions at channels instead of shrinking all islands to
			# the smallest pair of start distances across the whole map.
			var extent := minf(radius, nearest * (0.50 if small else 0.65))
			islands.append({"center": start, "radius": extent, "angle": roll(Vector2i(i, 1), local_seed) * PI,
				"aspect": lerpf(0.72, 0.88, roll(Vector2i(i, 2), local_seed)), "seed": local_seed,
				"core": minf(10.0, nearest * 0.43)})
	return {"islands": islands, "starts": starts, "size": size, "topology": topology, "generator": generator, "seed": seed}


static func water_at(point: Vector2, layout: Dictionary) -> bool:
	var size: Vector2i = layout["size"]
	var topology: String = layout["topology"]
	var generator: Dictionary = layout["generator"]
	var seed: int = layout["seed"]
	if topology in ["inland", "highlands", "hill_country", "narrows"]: return false
	var span := float(mini(size.x, size.y))
	var coast := noise(point, maxf(12.0, span * 0.19), seed ^ 0x341AF) * span * 0.065
	coast += noise(point, maxf(6.0, span * 0.045), seed ^ 0x317AC) * span * 0.022
	coast += noise(point, 3.0, seed ^ 0x635DA) * 0.8
	if topology == "coastal":
		var width := span * float(generator.get("coast_fraction", 0.21))
		return point.x < width + coast or point.y < width - coast * 0.7
	if topology == "continental":
		var width := span * float(generator.get("coast_fraction", 0.16))
		return point.x < width + coast or point.y < width - coast or point.x >= size.x - width + coast or point.y >= size.y - width - coast
	if topology == "mediterranean":
		# Enclosed sea: a wide central basin, narrowing ends and separate bays.
		var center := Vector2(size) * Vector2(0.50 + noise(Vector2.ZERO, 1.0, seed ^ 0x783D) * 0.025, 0.50)
		var delta := point - center
		delta.y += noise(Vector2(point.x, 0), maxf(12.0, span * 0.28), seed ^ 0x4E017) * span * 0.045
		var radii := Vector2(size.x * 0.42, size.y * float(generator.get("sea_fraction", 0.23)) / (PI * 0.42))
		var contour := Vector2(delta.x / radii.x, delta.y / radii.y).length()
		var ends := maxf(0.0, 1.0 - pow(absf(delta.x) / radii.x, 4.0))
		return contour < 1.0 + coast / maxf(1.0, radii.y) * 0.65 * ends
	if topology == "islands":
		var starts: Array[Vector2] = layout["starts"]
		for island in layout["islands"]:
			var delta: Vector2 = point - Vector2(island["center"])
			if delta.length() < float(island["core"]): return false
			var local := delta.rotated(-float(island["angle"]))
			local.x *= sqrt(float(island["aspect"]))
			local.y /= sqrt(float(island["aspect"]))
			var angle := local.angle()
			var phase := float(island["seed"] % 1009) * 0.01
			var radius := float(island["radius"]) * (1.0 + sin(angle * 3.0 + phase) * 0.16 + sin(angle * 5.0 - phase) * 0.08)
			if local.length() > radius + coast * 0.55: continue
			var distance := delta.length()
			var separated := true
			for other in starts:
				if other == island["center"]: continue
				if point.distance_to(other) - distance < maxf(5.0, span * 0.025): separated = false
			if separated: return false
		return true
	return false


static func noise(point: Vector2, period: float, seed: int) -> float:
	var sample := point / maxf(1.0, period)
	var at := Vector2i(floori(sample.x), floori(sample.y))
	var t := sample - Vector2(at)
	t = t * t * (Vector2(3.0, 3.0) - t * 2.0)
	return lerpf(lerpf(roll(at, seed), roll(at + Vector2i.RIGHT, seed), t.x), lerpf(roll(at + Vector2i.DOWN, seed), roll(at + Vector2i.ONE, seed), t.x), t.y) * 2.0 - 1.0


static func roll(cell: Vector2i, seed: int) -> float:
	var value := (int(cell.x) * 73856093) ^ (int(cell.y) * 19349663) ^ (seed * 83492791)
	value = ((value ^ (value >> 16)) * 0x7feb352d) & 0xffffffff
	value = ((value ^ (value >> 15)) * 0x846ca68b) & 0xffffffff
	value = (value ^ (value >> 16)) & 0xffffffff
	return float(value) / 4294967295.0
