class_name RoRRandomMapRiverChannels
extends RefCounted

# Drainage remains a discrete acyclic graph. Its presentation/terrain footprint
# comes from gently curved reaches pinned at sources, junctions and outlets.
static func build(size: Vector2i, original: Array[int], nodes: Array, threshold: float, fields: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var lookup: Dictionary = {}
	var incoming: Dictionary = {}
	for node in nodes:
		lookup[node["cell"]] = node
		var next: Vector2i = node["downstream"]
		incoming[next] = int(incoming.get(next, 0)) + 1
	var channels: Array = []
	for node in nodes:
		if int(incoming.get(node["cell"], 0)) == 1: continue
		var chain: Array = [node]
		var at: Dictionary = node
		while not bool(at["is_mouth"]):
			var next: Dictionary = lookup.get(at["downstream"], {})
			if next.is_empty(): break
			chain.append(next)
			if int(incoming.get(next["cell"], 0)) != 1: break
			at = next
		var channel := _curve(chain, threshold)
		_shape_widths(channel, size, fields, options)
		channels.append(channel)
	var mask := PackedByteArray()
	var types := PackedInt32Array()
	var levels := PackedInt32Array()
	var coverage := PackedFloat32Array()
	mask.resize(original.size())
	types.resize(original.size())
	types.fill(-1)
	levels.resize(original.size())
	levels.fill(-1)
	coverage.resize(original.size())
	coverage.fill(-INF)
	for channel in channels:
		var points: PackedVector2Array = channel["points"]
		for i in range(points.size()):
			var point := points[i]
			var radius: float = channel["radii"][i]
			var reach := ceili(radius + 0.5)
			var center := Vector2i(point.floor())
			for y in range(maxi(0, center.y - reach), mini(size.y, center.y + reach + 1)):
				for x in range(maxi(0, center.x - reach), mini(size.x, center.x + reach + 1)):
					var delta := Vector2(x + 0.5, y + 0.5) - point
					var depth := radius - delta.length()
					if depth < 0.0: continue
					var index := y * size.x + x
					# The deepest contributing reach wins at a confluence.
					if mask[index] != 0 and depth <= coverage[index]: continue
					mask[index] = 1
					coverage[index] = depth
					levels[index] = channel["levels"][i]
					var ratio: float = channel["runoff"][i] / threshold
					var kind := 4 if ratio < 2.0 else 1
					if ratio > 18.0 and depth > 1.25: kind = 22
					if original[index] != 0: kind = 22 if original[index] == 22 else 1
					types[index] = kind
	# Flat shallows are separated at changes in physical water level. Otherwise
	# flattening connected shallows would drag an entire upland river to its mouth.
	var shallow := types.duplicate()
	for i in range(types.size()):
		if types[i] != 4: continue
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x := i % size.x + dx
				var y := i / size.x + dy
				if x < 0 or y < 0 or x >= size.x or y >= size.y: continue
				var next := y * size.x + x
				if levels[next] >= 0 and levels[next] != levels[i]: shallow[i] = 1
	return {"mask":mask, "terrain_types":shallow, "surface_levels":levels, "channels":channels}

static func _curve(chain: Array, threshold: float) -> Dictionary:
	var source := PackedVector2Array()
	var flows := PackedFloat32Array()
	var heights := PackedInt32Array()
	for node in chain:
		source.append(Vector2(node["cell"]) + Vector2.ONE * 0.5)
		flows.append(float(node["discharge"]))
		heights.append(int(node.get("surface_level", 0)))
	var last: Dictionary = chain.back()
	if last["is_mouth"]:
		source.append(Vector2(last["downstream"]) + Vector2.ONE * 0.5)
		flows.append(flows[-1])
		heights.append(heights[-1])
	var controls := source.duplicate()
	for i in range(1, source.size() - 1):
		var sum := Vector2.ZERO
		var weight := 0.0
		for offset in range(-4, 5):
			var index := clampi(i + offset, 0, source.size() - 1)
			var w := float(5 - absi(offset))
			sum += source[index] * w
			weight += w
		var shift := (sum / weight - source[i]).limit_length(1.35)
		controls[i] += shift * minf(1.0, mini(i, source.size() - 1 - i) / 2.0)
	var points := PackedVector2Array()
	var radii := PackedFloat32Array()
	var levels := PackedInt32Array()
	var runoff := PackedFloat32Array()
	var sediment := PackedFloat32Array()
	var bends := PackedFloat32Array()
	for i in range(controls.size() - 1):
		var a := controls[maxi(0, i - 1)]
		var b := controls[i]
		var c := controls[i + 1]
		var d := controls[mini(controls.size() - 1, i + 2)]
		var steps := maxi(1, ceili(b.distance_to(c) / 0.30))
		for step in range(steps):
			var t := float(step) / steps
			var point := b.cubic_interpolate(c, a, d, t)
			points.append(point)
			var flow := lerpf(flows[i], flows[i + 1], t)
			runoff.append(flow)
			radii.append(radius(flow / threshold,1.0,INF))
			levels.append(heights[i] if t < 0.5 else heights[i + 1])
			var bend := (b - a).normalized().cross((d - c).normalized())
			var ratio := flow / threshold
			sediment.append(clampf(1.5 - ratio * 0.5, 0.0, 0.8))
			bends.append(bend)
	points.append(controls[-1])
	runoff.append(flows[-1])
	radii.append(radius(flows[-1] / threshold,1.0,INF))
	levels.append(heights[-1])
	sediment.append(sediment[-1] if not sediment.is_empty() else 0.0)
	bends.append(bends[-1] if not bends.is_empty() else 0.0)
	var rockiness := PackedFloat32Array()
	for i in range(points.size()):
		var before := (points[i]-points[maxi(0,i-12)]).normalized()
		var after := (points[mini(points.size()-1,i+12)]-points[i]).normalized()
		bends[i] = before.cross(after)
		var drop := absf(float(levels[maxi(0,i-12)]-levels[mini(levels.size()-1,i+12)]))
		rockiness.append(clampf(drop*0.35,0.0,1.0))
	return {"points":points, "radii":radii, "levels":levels, "runoff":runoff, "sediment":sediment, "bends":bends,"rockiness":rockiness, "basin":int(last["basin"])}

static func sediment_at(channel: Dictionary, index: int, delta: Vector2) -> float:
	var points: PackedVector2Array = channel["points"]
	var tangent := (points[mini(points.size() - 1, index + 2)] - points[maxi(0, index - 2)]).normalized()
	var bend: float = channel["bends"][index]
	var inside := tangent.cross(delta) * signf(bend) / maxf(0.1, channel["radii"][index])
	return clampf(channel["sediment"][index] + minf(0.85, absf(bend) * 2.5) * smoothstep(0.0, 0.7, inside), 0.0, 1.0)

static func radius(flow_ratio: float, width_scale: float = 1.0, maximum_radius: float = 3.2) -> float:
	# Map-scale hydraulic geometry. The lower limit keeps a visible continuous
	# stream in the terrain raster; it has no relationship to unit footprints.
	var source_taper := lerpf(0.6,1.0,smoothstep(1.0,2.0,flow_ratio))
	return clampf(0.86 * pow(maxf(1.0,flow_ratio),0.32) * width_scale * source_taper,0.42,maximum_radius)

static func _shape_widths(channel: Dictionary, size: Vector2i, fields: Dictionary, options: Dictionary) -> void:
	var points: PackedVector2Array = channel["points"]
	var radii: PackedFloat32Array = channel["radii"]
	var geology: PackedFloat32Array = fields.get("geology",PackedFloat32Array())
	var levels: Array = fields.get("vertex_levels",[])
	var scale := float(options.get("width_scale",1.0))
	var maximum := float(options.get("maximum_radius",3.2))
	var raw := radii.duplicate()
	var rocks: PackedFloat32Array = channel["rockiness"]
	for i in range(points.size()):
		var cell := Vector2i(points[i].floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
		var stone := geology[cell.y*size.x+cell.x] if not geology.is_empty() else 0.5
		var tangent := (points[mini(points.size()-1,i+8)]-points[maxi(0,i-8)]).normalized()
		var normal := Vector2(-tangent.y,tangent.x)
		var base := clampf(radii[i]*scale,0.42,maximum)
		# Both high banks confine a gorge. One steep outside bank alone must
		# not turn every alluvial bend into a symmetric narrow rock channel.
		var walls := 0.0
		if not levels.is_empty():
			var water := float(channel["levels"][i])
			walls = minf(_height(size,levels,points[i]+normal*(base+2.5)),_height(size,levels,points[i]-normal*(base+2.5)))-water
		var confinement := smoothstep(0.5,2.5,walls)
		var resistance := smoothstep(0.45,0.85,stone)
		var local_factor := lerpf(1.08,0.82,resistance)*lerpf(1.0,0.72,confinement)
		local_factor *= 1.0+sin(points[i].x*0.11+sin(points[i].y*0.09))*0.05
		var end_weight := smoothstep(0.0,3.0,minf(points[i].distance_to(points[0]),points[i].distance_to(points[-1])))
		raw[i] = clampf(base*lerpf(1.0,local_factor,end_weight),0.42,maximum)
		rocks[i] = clampf(rocks[i]+resistance*0.45+confinement*0.20,0.0,1.0)
	# Width changes belong to reaches, never to independent individual tiles.
	for i in range(points.size()):
		var sum := 0.0
		var weight := 0.0
		for j in range(maxi(0,i-8),mini(points.size(),i+9)):
			var w := maxf(0.0,1.0-points[i].distance_to(points[j])/2.4)
			sum += raw[j]*w;weight += w
		radii[i] = sum/maxf(weight,0.001)
	channel["radii"] = radii
	channel["rockiness"] = rocks

static func _height(size: Vector2i, levels: Array, point: Vector2) -> float:
	var at := Vector2i(point.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var i := at.y*(size.x+1)+at.x
	return (levels[i]+levels[i+1]+levels[i+size.x+1]+levels[i+size.x+2])*0.25
