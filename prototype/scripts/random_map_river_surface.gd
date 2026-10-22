class_name RoRRandomMapRiverSurface
extends RefCounted

const RESOLUTION := 2
const STRIDE := 4 # bank distance, influence, water depth, gravel fraction
const SILT := 1004
const GRAVEL := 1005

# One bed field supplies the visible shore, exposed bars and navigation classes.
# Depth is measured below the water surface; negative values are exposed bed.
static func build(size: Vector2i, original: Array[int], rivers: Dictionary, lakes: Array, fords: Array = []) -> Dictionary:
	var grid := size*RESOLUTION+Vector2i.ONE
	var samples := PackedFloat32Array()
	samples.resize(grid.x*grid.y*STRIDE)
	# Preserve water flow through deposits, not a ship-sized navigation lane.
	# This narrow thread scales with the local channel and may be too small
	# even for a fishing boat. Exposed bars remain real navigation terrain.
	var flow_floor := PackedFloat32Array()
	flow_floor.resize(grid.x*grid.y)
	flow_floor.fill(-0.5)
	for i in range(grid.x*grid.y):
		samples[i*STRIDE] = -8.0
		samples[i*STRIDE+2] = 2.0
	for channel in rivers["channels"]:
		var points: PackedVector2Array = channel["points"]
		for i in range(0,points.size(),2):
			var point := points[i]
			var radius: float = channel["radii"][i]
			var tangent := (points[mini(points.size()-1,i+6)]-points[maxi(0,i-6)]).normalized()
			var normal := Vector2(-tangent.y,tangent.x)
			var bend := float(channel["bends"][i])
			var rocky: float = channel.get("rockiness",PackedFloat32Array())[i] if channel.has("rockiness") else 0.0
			var reach := ceili((radius+1.8)*RESOLUTION)
			var center := Vector2i(point*RESOLUTION)
			for y in range(maxi(0,center.y-reach),mini(grid.y,center.y+reach+1)):
				for x in range(maxi(0,center.x-reach),mini(grid.x,center.x+reach+1)):
					var delta := Vector2(x,y)/RESOLUTION-point
					var distance := delta.length()
					var at := y*grid.x+x
					# Confluences are a union of wet sections. A narrow tributary
					# must not pinch the surface of a larger receiving channel.
					if radius-distance <= samples[at*STRIDE]: continue
					var crosswise := delta.dot(normal)/radius
					# The deep thread shifts toward the eroding outer bank.
					var thalweg := -signf(bend)*minf(0.38,absf(bend)*0.7)
					var flow_distance := delta.distance_to(normal*thalweg*radius)
					var flow_radius := minf(0.35,radius*0.22)
					if flow_distance < flow_radius+0.5:
						flow_floor[at] = maxf(flow_floor[at],lerpf(0.10,-0.5,smoothstep(flow_radius,flow_radius+0.5,flow_distance)))
					var section := maxf(0.0,1.0-pow(absf(crosswise-thalweg)/(1.0+absf(thalweg)),1.7))
					var depth := 0.12+section*lerpf(1.10,1.65,rocky)
					var index := at*STRIDE
					samples[index] = radius-distance
					samples[index+1] = 1.0-smoothstep(0.9,1.8,distance-radius)
					samples[index+2] = depth
					samples[index+3] = rocky
	for bar in rivers.get("shoals",[]): _bar(samples,grid,bar)
	for i in range(flow_floor.size()): samples[i*STRIDE+2] = maxf(samples[i*STRIDE+2],flow_floor[i])
	for ford in fords: _riffle(samples,grid,ford)
	var excluded := PackedByteArray()
	excluded.resize(original.size())
	for i in range(original.size()): excluded[i] = int(original[i] != 0 or rivers["mouth_mask"][i] != 0)
	for lake in lakes:
		for i in lake["cells"]: excluded[i] = 1
	for y in range(grid.y):
		for x in range(grid.x):
			var index := (y*grid.x+x)*STRIDE
			if samples[index+1] <= 0.0: continue
			var cell := Vector2i(x/RESOLUTION,y/RESOLUTION)
			for dy in range(-1,2):
				for dx in range(-1,2):
					var at := cell+Vector2i(dx,dy)
					if at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y and excluded[at.y*size.x+at.x] != 0: samples[index+1] = 0.0
	return {"size":grid,"resolution":RESOLUTION,"stride":STRIDE,"samples":samples,"model_version":2}

static func _bar(samples: PackedFloat32Array, grid: Vector2i, bar: Dictionary) -> void:
	var points: PackedVector2Array = bar["points"]
	for i in range(0,points.size(),2):
		var width: float = bar["widths"][i]
		if width < 0.05: continue
		var point := points[i]
		var center := Vector2i(point*RESOLUTION)
		var feather := clampf(width*0.35,0.12,0.35)
		var reach := ceili((width+feather)*RESOLUTION)
		for y in range(maxi(0,center.y-reach),mini(grid.y,center.y+reach+1)):
			for x in range(maxi(0,center.x-reach),mini(grid.x,center.x+reach+1)):
				var distance := Vector2(x,y).distance_to(point*RESOLUTION)/RESOLUTION
				var amount := 1.0-smoothstep(width*0.45,width+feather,distance)
				if amount <= 0.0: continue
				var at := (y*grid.x+x)*STRIDE
				var bed := lerpf(1.3,float(bar.get("crest_depth",-0.10)),amount)
				samples[at+2] = minf(samples[at+2],bed)
				samples[at+3] = lerpf(samples[at+3],float(bar.get("gravel",0.0)),amount)

static func _riffle(samples: PackedFloat32Array, grid: Vector2i, ford: Dictionary) -> void:
	var a: Vector2 = ford["bank_a"]
	var b: Vector2 = ford["bank_b"]
	var half_width := float(ford.get("half_width",clampf(a.distance_to(b)*0.16,0.55,1.35)))
	for y in range(maxi(0,floori(minf(a.y,b.y)*2)-4),mini(grid.y,ceili(maxf(a.y,b.y)*2)+5)):
		for x in range(maxi(0,floori(minf(a.x,b.x)*2)-4),mini(grid.x,ceili(maxf(a.x,b.x)*2)+5)):
			var point := Vector2(x,y)*0.5
			var distance := point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))
			var amount := 1.0-smoothstep(half_width*0.6,half_width+0.45,distance)
			var at := (y*grid.x+x)*STRIDE
			# A continuous water film over a gravel ridge; no dry sand bridge.
			samples[at+2] = lerpf(samples[at+2],0.12,amount)
			samples[at+3] = maxf(samples[at+3],amount*0.8)

static func classify(size: Vector2i, rivers: Dictionary, lakes: Array, fords: Array) -> void:
	var shape: Dictionary = rivers["surface"]
	var protected: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: protected[int(i)] = true
	for ford in fords:
		for cell in ford["cells"]: protected[cell.y*size.x+cell.x] = true
	for i in range(size.x*size.y):
		if rivers["mask"][i] == 0 or rivers["terrain_types"][i] < 0 or rivers["mouth_mask"][i] != 0 or protected.has(i): continue
		var point := Vector2(i%size.x,i/size.x)+Vector2.ONE*0.5
		var field := sample(shape,point)
		if field.y < 0.9: continue
		var kind := 1
		if field.z < 0.65: kind = 4
		if field.z > 1.40: kind = 22
		var dry := field.z < -0.045
		if dry: kind = GRAVEL if field.w > 0.5 else SILT
		# Only level shelves are pedestrian corridors.
		if kind == 4:
			for dy in range(-1,2):
				for dx in range(-1,2):
					var next := Vector2i(i%size.x+dx,i/size.x+dy)
					if next.x < 0 or next.y < 0 or next.x >= size.x or next.y >= size.y: continue
					var level: int = rivers["surface_levels"][next.y*size.x+next.x]
					if level >= 0 and level != rivers["surface_levels"][i]: kind = 1
		rivers["terrain_types"][i] = kind

static func sediment(field: Vector4) -> float:
	return 1.0-smoothstep(0.1,0.9,field.z)

static func sample(shape: Dictionary, point: Vector2) -> Vector4:
	if shape.is_empty(): return Vector4(-8,0,2,0)
	var grid: Vector2i = shape["size"]
	var at := (point*int(shape["resolution"])).clamp(Vector2.ZERO,Vector2(grid-Vector2i.ONE))
	var origin := Vector2i(at.floor())
	var next := (origin+Vector2i.ONE).min(grid-Vector2i.ONE)
	var fraction := at-Vector2(origin)
	var data: PackedFloat32Array = shape["samples"]
	var result := Vector4.ZERO
	for component in range(STRIDE):
		result[component] = lerpf(lerpf(data[(origin.y*grid.x+origin.x)*STRIDE+component],data[(origin.y*grid.x+next.x)*STRIDE+component],fraction.x),lerpf(data[(next.y*grid.x+origin.x)*STRIDE+component],data[(next.y*grid.x+next.x)*STRIDE+component],fraction.x),fraction.y)
	return result

static func blend(weights: Dictionary, field: Vector4) -> Dictionary:
	var influence := field.y
	if influence <= 0.0: return weights
	var land := 0.0
	for id in weights:
		if id not in [1,4,15,22]: land += weights[id]
	var wet := smoothstep(-0.08,0.10,field.x)*smoothstep(-0.035,0.10,field.z)
	var target_land := lerpf(land,1.0-wet,influence)
	var target_water := 1.0-target_land
	var exposed := target_land*influence*smoothstep(-0.8,0.1,field.x)
	var wet_edge := target_land*influence*(1.0-smoothstep(0.15,0.8,-field.x))*0.65
	var bed_land := maxf(exposed,wet_edge)
	var gravel := clampf(field.w,0.0,1.0)
	for id in weights:
		weights[id] *= (target_land-bed_land)/land if id not in [1,4,15,22] and land > 0.0 else 0.0
	if land <= 0.0: weights[0] = target_land-bed_land
	weights[SILT] = float(weights.get(SILT,0.0))+bed_land*(1.0-gravel)
	weights[GRAVEL] = float(weights.get(GRAVEL,0.0))+bed_land*gravel
	var shallow := target_water*influence*(1.0-smoothstep(0.10,0.95,field.z))*0.85
	var deep := target_water*influence*smoothstep(0.95,1.65,field.z)*0.55
	weights[1] = target_water-shallow-deep
	weights[4] = shallow
	weights[22] = deep
	return weights
