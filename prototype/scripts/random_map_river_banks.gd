class_name RoRRandomMapRiverBanks
extends RefCounted

const Navigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")

# Each entry is one coherent depositional landform, with a tapered outline.
# Quiet reaches may have no bar. Curvature chooses the bank, slope the material.
static func build(size: Vector2i, terrain: Array[int], fields: Dictionary, rivers: Dictionary, lakes: Array, seed: int) -> Array:
	var excluded: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: excluded[int(i)] = true
	var result: Array = []
	for channel in rivers["channels"]:
		var points: PackedVector2Array = channel["points"]
		if points.size() < 25: continue
		var distances := PackedFloat32Array([0.0])
		for i in range(1,points.size()): distances.append(distances[-1]+points[i].distance_to(points[i-1]))
		var candidates: Array = []
		for i in range(12,points.size()-12,6):
			var bend := float(channel["bends"][i])
			var radius := float(channel["radii"][i])
			var side := int(signf(bend)) if absf(bend)>0.10 else (1 if sin(distances[i]*0.14+channel["basin"])>0 else -1)
			var normal := _normal(points,i)*side
			var grade := _grade(size,fields["vertex_levels"],points[i],normal,radius)
			var cell := Vector2i(points[i].floor())
			if not Navigation.inside(cell,size) or excluded.has(cell.y*size.x+cell.x) or rivers["mouth_mask"][cell.y*size.x+cell.x] != 0 or near_fall(rivers,points[i],9.0): continue
			var rocky: float = channel["rockiness"][i]
			if rocky>0.6 or grade>0.9: continue
			# A long straight bank occasionally receives an alternate bar, rather
			# than a continuous border of uniform width.
			if absf(bend)<0.10 and Topology.roll(cell,seed^0xBAA71)>0.12: continue
			candidates.append({"i":i,"side":side,"grade":grade,"score":absf(bend)*3.0+Topology.roll(cell,seed^0xBAA72)*0.2})
		candidates.sort_custom(func(a,b): return a["score"]>b["score"])
		var selected: Array[int] = []
		for candidate in candidates:
			var at: int = candidate["i"]
			var radius := float(channel["radii"][at])
			if selected.any(func(other): return absf(distances[other]-distances[at])<maxf(7.0,radius*5.0)): continue
			var half_length := 2.0+radius*1.8
			var lo := at
			var hi := at
			while lo>0 and distances[at]-distances[lo]<half_length: lo-=1
			while hi<points.size()-1 and distances[hi]-distances[at]<half_length: hi+=1
			if distances[hi]-distances[lo]<3.5: continue
			var positions := PackedVector2Array()
			var widths := PackedFloat32Array()
			var source: bool = channel["runoff"][at]<rivers["runoff_threshold"]*2.0
			var maximum_width := radius*(0.42 if source else 0.58)
			var side: int = candidate["side"]
			for i in range(lo,hi+1):
				var fraction := (distances[i]-distances[lo])/maxf(0.01,distances[hi]-distances[lo])
				var width := maximum_width*pow(sin(fraction*PI),1.2)
				var normal := _normal(points,i)*side
				positions.append(points[i]+normal*(channel["radii"][i]-width*0.45))
				widths.append(width)
			var connected := PackedVector2Array([positions[0]])
			var connected_widths := PackedFloat32Array([widths[0]])
			for i in range(1,positions.size()):
				var steps := maxi(1,ceili(positions[i-1].distance_to(positions[i])/0.3))
				for step in range(1,steps+1):
					var fraction := float(step)/steps
					connected.append(positions[i-1].lerp(positions[i],fraction))
					connected_widths.append(lerpf(widths[i-1],widths[i],fraction))
			positions = connected
			widths = connected_widths
			var gravel := clampf(float(channel["rockiness"][at])*1.4,0.0,0.8)
			result.append({"points":positions,"widths":widths,"length":distances[hi]-distances[lo],"side":side,
				"origin":"source_silt" if source else "inner_bend" if absf(channel["bends"][at])>0.1 else "alternate_bar",
				"level":channel["levels"][at],"bank_grade":candidate["grade"],"gravel":gravel,
				"crest_depth":lerpf(-0.14,0.06,clampf(gravel*0.7+candidate["grade"]*0.25,0.0,1.0)),"stable_margin":gravel<0.3 and candidate["grade"]<0.4})
			selected.append(at)
	return result

static func shape_valleys(size: Vector2i, terrain: Array[int], levels: Array[int], rivers: Dictionary) -> void:
	for channel in rivers["channels"]:
		var points: PackedVector2Array = channel["points"]
		for i in range(0,points.size(),6):
			var point := points[i]
			var radius: float = channel["radii"][i]
			var level: int = channel["levels"][i]
			var reach := ceili(radius+4.5)
			for y in range(maxi(0,floori(point.y)-reach),mini(size.y+1,floori(point.y)+reach+1)):
				for x in range(maxi(0,floori(point.x)-reach),mini(size.x+1,floori(point.x)+reach+1)):
					var distance := Vector2(x,y).distance_to(point)-radius
					if distance<0.0 or distance>4.5: continue
					var terrace := level+floori(pow(distance/2.6,1.6))
					var at := y*(size.x+1)+x
					levels[at] = mini(levels[at],terrace)

static func near_fall(rivers: Dictionary, point: Vector2, distance: float) -> bool:
	for fall in rivers.get("waterfalls",[]):
		if point.distance_squared_to(fall["position"])<distance*distance: return true
	for rapid in rivers.get("rapids",[]):
		if point.distance_squared_to(rapid["position"])<distance*distance: return true
	return false

static func _normal(points: PackedVector2Array, index: int) -> Vector2:
	var direction := (points[mini(points.size()-1,index+6)]-points[maxi(0,index-6)]).normalized()
	return Vector2(-direction.y,direction.x)

static func _grade(size: Vector2i, levels: Array, point: Vector2, normal: Vector2, radius: float) -> float:
	return maxf(0.0,_height(size,levels,point+normal*(radius+3.0))-_height(size,levels,point+normal*(radius+0.5)))

static func _height(size: Vector2i, levels: Array, point: Vector2) -> float:
	var cell := Vector2i(point.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
	var at := cell.y*(size.x+1)+cell.x
	return (levels[at]+levels[at+1]+levels[at+size.x+1]+levels[at+size.x+2])*0.25
