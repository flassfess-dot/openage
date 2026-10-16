class_name RoRRandomMapNaturalTopology
extends RefCounted

const Base := preload("res://scripts/random_map_topology.gd")

static func orientation(seed: int) -> float:
	return floorf(Base.roll(Vector2i(17, 29), seed) * 4.0) * PI * 0.5 + Base.noise(Vector2.ZERO, 1.0, seed ^ 0x731A) * 0.28

static func orient(point: Vector2, size: Vector2i, seed: int) -> Vector2:
	return (point - Vector2(size) * 0.5).rotated(orientation(seed)) + Vector2(size) * 0.5

static func prepare(size: Vector2i, starts: Array[Vector2], topology: String, generator: Dictionary, seed: int) -> Dictionary:
	var layout := Base.prepare(size, starts, topology, generator, seed)
	layout["angle"] = orientation(seed)
	layout["center"] = Vector2(size) * 0.5 + Vector2(Base.noise(Vector2.ZERO, 1.0, seed ^ 0x4159), Base.noise(Vector2.ONE, 1.0, seed ^ 0x4159)) * float(mini(size.x, size.y)) * 0.025
	if topology == "islands":
		var small := String(generator.get("map_type_id", "")) == "small_islands" or String(generator.get("profile", "")).begins_with("small_islands")
		var radius := sqrt((0.34 if small else 0.56) * float(size.x * size.y) / (PI * float(maxi(1, starts.size()))))
		for i in range(layout["islands"].size()):
			var island: Dictionary = layout["islands"][i]
			var nearest := float(size.x + size.y)
			for j in range(starts.size()):
				if i != j: nearest = minf(nearest, starts[i].distance_to(starts[j]))
			island["radius"] = minf(radius * lerpf(0.94, 1.08, Base.roll(Vector2i(i, 4), seed)), nearest * (0.56 if small else 0.67))
			island["aspect"] = lerpf(0.60, 0.94, Base.roll(Vector2i(i, 5), seed))
			island["core"] = minf(9.5, nearest * 0.40)
	return layout

static func water_at(point: Vector2, layout: Dictionary) -> bool:
	var topology: String = layout["topology"]
	if topology in ["inland", "highlands", "hill_country", "narrows"]: return false
	var size: Vector2i = layout["size"]
	var span := float(mini(size.x, size.y))
	var seed: int = layout["seed"]
	var generator: Dictionary = layout["generator"]
	var delta := (point - Vector2(layout["center"])).rotated(-float(layout["angle"]))
	var coast := Base.noise(point, maxf(10.0, span * 0.22), seed ^ 0x341AF) * span * 0.075
	coast += Base.noise(point, maxf(5.0, span * 0.07), seed ^ 0x317AC) * span * 0.027
	coast += Base.noise(point, 3.5, seed ^ 0x635DA) * 0.65
	if topology == "coastal":
		var slope := lerpf(-0.70, 0.70, Base.roll(Vector2i(2, 3), seed))
		var width := span * (float(generator.get("coast_fraction", 0.21)) - 0.35)
		return delta.x + delta.y * slope < width + coast
	if topology == "continental":
		var aspect := lerpf(0.87, 1.12, Base.roll(Vector2i(5, 8), seed))
		var radius := span * (0.52 - float(generator.get("coast_fraction", 0.16)))
		var angle := delta.angle()
		var contour := Vector2(delta.x / aspect, delta.y * aspect).length()
		var lobes := sin(angle * 3.0 + float(seed % 997)) * span * 0.024
		return contour > radius + coast * 0.70 + lobes
	if topology == "mediterranean":
		var length := span * lerpf(0.38, 0.43, Base.roll(Vector2i(8, 13), seed))
		var width := span * float(generator.get("sea_fraction", 0.23)) / (PI * length / span)
		var bend := sin(delta.x / length * PI) * span * 0.045
		delta.y -= bend
		var contour := Vector2(delta.x / length, delta.y / width).length()
		var ends := maxf(0.0, 1.0 - pow(absf(delta.x) / length, 4.0))
		return contour < 1.0 + coast / width * 0.55 * ends
	if topology == "islands":
		# A shared warped channel field keeps neighbouring shores apart without
		# cutting every island along straight Voronoi borders.
		var warp := Vector2(Base.noise(point, span * 0.24, seed ^ 0xE521), Base.noise(point, span * 0.24, seed ^ 0xA381)) * span * 0.045
		var warped := point + warp
		for island in layout["islands"]:
			var center: Vector2 = island["center"]
			var distance := point.distance_to(center)
			if distance < float(island["core"]): return false
			var local := (point - center).rotated(-float(island["angle"]))
			local.x *= sqrt(float(island["aspect"]))
			local.y /= sqrt(float(island["aspect"]))
			var angle := local.angle()
			var phase := float(int(island["seed"]) % 1009) * 0.01
			var radius := float(island["radius"]) * (1.0 + sin(angle * 2.0 + phase) * 0.12 + sin(angle * 3.0 - phase) * 0.17 + sin(angle * 5.0 + phase) * 0.06)
			if local.length() > radius + coast * 0.45: continue
			var separated := true
			for other in layout["starts"]:
				if other == center: continue
				if warped.distance_to(other) - warped.distance_to(center) < maxf(4.5, span * 0.025): separated = false
			if separated: return false
		return true
	return false
