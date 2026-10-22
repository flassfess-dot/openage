class_name RoRRandomMapRiverRapids
extends RefCounted

const Topology := preload("res://scripts/random_map_topology.gd")
const Banks := preload("res://scripts/random_map_river_banks.gd")

# A bedrock/boulder reach is distinct from a walkable gravel riffle and from
# a vertical waterfall. Water remains visible between the original wet rocks;
# the same rocks publish the actual cells which stop ships and infantry.
static func plan(size: Vector2i, terrain: Array[int], rivers: Dictionary, lakes: Array, seed: int) -> Array:
	var excluded: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: excluded[int(i)] = true
	var candidates: Array = []
	for channel in rivers["channels"]:
		var points: PackedVector2Array = channel["points"]
		for i in range(15,points.size()-15,8):
			var point := points[i]
			var cell := Vector2i(point.floor())
			if cell.x<3 or cell.y<3 or cell.x>=size.x-3 or cell.y>=size.y-3: continue
			var index := cell.y*size.x+cell.x
			if rivers["mouth_mask"][index]!=0 or excluded.has(index) or Banks.near_fall(rivers,point,13.0): continue
			var drop := int(channel["levels"][i-12])-int(channel["levels"][i+12])
			var rocky := float(channel["rockiness"][i])
			# Drops over rocky ground and strongly confined rocky shelves are
			# candidates. Randomness ranks suitable terrain, never creates it.
			if rocky<0.55 or (drop<=0 and rocky<0.72): continue
			if channel["runoff"][i]<rivers["runoff_threshold"]*1.5: continue
			candidates.append({"position":point,"direction":(points[i+8]-points[i-8]).normalized(),
				"radius":float(channel["radii"][i]),"basin":channel["basin"],"rockiness":rocky,
				"score":rocky+minf(2.0,drop)*0.4+Topology.roll(cell,seed^0x7A91)*0.15})
	candidates.sort_custom(func(a,b):return a["score"]>b["score"])
	var result: Array = []
	for candidate in candidates:
		if result.size()>=maxi(1,ceili(size.x*size.y/6500.0)): break
		if result.any(func(other):return Vector2(other["position"]).distance_to(candidate["position"])<18.0): continue
		var point: Vector2 = candidate["position"]
		var direction: Vector2 = candidate["direction"]
		var normal := Vector2(-direction.y,direction.x)
		var reach := ceili(candidate["radius"]+2.0)
		var cells: Array[Vector2i] = []
		var valid := true
		for y in range(maxi(0,floori(point.y)-reach),mini(size.y,floori(point.y)+reach+1)):
			for x in range(maxi(0,floori(point.x)-reach),mini(size.x,floori(point.x)+reach+1)):
				var delta := Vector2(x+0.5,y+0.5)-point
				if absf(delta.dot(direction))>1.15 or absf(delta.dot(normal))>candidate["radius"]+0.8: continue
				var index := y*size.x+x
				if rivers["mouth_mask"][index]!=0 or excluded.has(index): valid=false
				if rivers["mask"][index]!=0 and terrain[index] in [1,4,22]: cells.append(Vector2i(x,y))
		if not valid or cells.size()<2: continue
		candidate.erase("score")
		candidate["barrier_cells"] = cells
		candidate["origin"] = "bedrock_rapid"
		result.append(candidate)
		for cell in cells: rivers["terrain_types"][cell.y*size.x+cell.x]=1
	return result

static func append_rocks(rivers: Dictionary, scenery: Array, cells: Dictionary, used: Dictionary, seed: int) -> void:
	var variants := [2,3,9,10]
	for rapid in rivers.get("rapids",[]):
		for cell in rapid["barrier_cells"]:
			var position := Vector2(cell)+Vector2.ONE*0.5
			# All native fragments stay at their authored scale. A staggered
			# cluster uses the large wet-rock variants, without giant stretched art.
			var roll := Topology.roll(cell,seed^0x7A92)
			position += Vector2(sin(roll*TAU),cos(roll*TAU))*0.10
			cells[cell]=true;used[cell]=true
			scenery.append({"id":-700000-scenery.size(),"kind":"cliff","asset_name":"aoe2_temperate:ror_sea_rocks",
				"source_frame":variants[mini(variants.size()-1,int(roll*variants.size()))],"position":position,
				"river_rapid":true,"occupied_cells":[cell],"presentation_layer":"scenery",
				"presentation_bounds":[-1.0,-1.0,1.0,1.0]})
