class_name RoRRandomMapRiverFalls
extends RefCounted

const Navigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Coordinates := preload("res://scripts/coordinates.gd")

static func plan(size: Vector2i, terrain: Array[int], rivers: Dictionary, lakes: Array, seed: int) -> Array:
	var lake_cells: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: lake_cells[int(i)] = true
	var candidates: Array = []
	for channel in rivers["channels"]:
		var points: PackedVector2Array = channel["points"]
		for i in range(12,points.size()-12,4):
			var drop := int(channel["levels"][i-10])-int(channel["levels"][i+10])
			if drop < 1 or channel["runoff"][i] < rivers["runoff_threshold"]*2.0: continue
			var direction := (points[i+8]-points[i-8]).normalized()
			var axis := direction
			var center := Vector2i(points[i].floor())
			if center.x < 9 or center.y < 9 or center.x >= size.x-9 or center.y >= size.y-9: continue
			var at := center.y*size.x+center.x
			if rivers["mouth_mask"][at] != 0 or lake_cells.has(at): continue
			var excluded := false
			for offset in [-10,0,10]:
				var cell := Vector2i(points[i+offset].floor())
				var index := cell.y*size.x+cell.x
				if rivers["mouth_mask"][index] != 0 or lake_cells.has(index): excluded = true
			if excluded: continue
			# A waterfall's geological shoulders and pools must stay clear of
			# lake surfaces, which have their own fixed hydraulic level.
			for lake in lakes:
				if Vector2(lake["center"]).distance_to(points[i]) < sqrt(float(lake["area"]))+12.0: excluded = true
			if excluded: continue
			candidates.append({"position":Vector2(center)+Vector2.ONE*0.5,"direction":axis,
				"upper":points[i-10],"lower":points[i+10],"upper_level":int(channel["levels"][i-10]),
				"lower_level":int(channel["levels"][i+10]),"radius":float(channel["radii"][i]),
				"score":drop*10.0+Topology.roll(center,seed^0xFA11),"basin":channel["basin"]})
	candidates.sort_custom(func(a,b): return a["score"] > b["score"])
	var result: Array = []
	for candidate in candidates:
		if result.size() >= clampi(ceili(size.x*size.y/50000.0),1,4): break
		if result.any(func(fall): return Vector2(fall["position"]).distance_to(candidate["position"]) < 24.0): continue
		var position: Vector2 = candidate["position"]
		var axis: Vector2 = candidate["direction"]
		var normal := Vector2(-axis.y,axis.x)
		var blocked: Array[Vector2i] = []
		for y in range(maxi(0,floori(position.y-6)),mini(size.y,ceili(position.y+6))):
			for x in range(maxi(0,floori(position.x-6)),mini(size.x,ceili(position.x+6))):
				var delta := Vector2(x+0.5,y+0.5)-position
				if absf(delta.dot(axis)) > 1.0 or absf(delta.dot(normal)) > candidate["radius"]+2.0: continue
				var index := y*size.x+x
				if terrain[index] in [1,4,22] and rivers["mask"][index] != 0: blocked.append(Vector2i(x,y))
		if blocked.is_empty(): continue
		candidate.erase("score")
		candidate["barrier_cells"] = blocked
		candidate["origin"] = "river_crossing_relief_ledge"
		result.append(candidate)
		# A drop is neither a ford nor a shallow walking corridor.
		for y in range(maxi(0,floori(position.y-6)),mini(size.y,ceili(position.y+6))):
			for x in range(maxi(0,floori(position.x-6)),mini(size.x,ceili(position.x+6))):
				var index := y*size.x+x
				if rivers["terrain_types"][index] == 4: rivers["terrain_types"][index] = 1
	return result

static func append_cliffs(size: Vector2i, terrain: Array[int], levels: Array[int], rivers: Dictionary, scenery: Array, cells: Dictionary, used: Dictionary, seed: int) -> void:
	for fall in rivers.get("waterfalls",[]):
		var position: Vector2 = fall["position"]
		var direction: Vector2 = fall["direction"]
		var normal := Vector2(-direction.y,direction.x)
		var occupied: Array[Vector2i] = []
		for y in range(maxi(0,floori(position.y-8)),mini(size.y,ceili(position.y+8))):
			for x in range(maxi(0,floori(position.x-8)),mini(size.x,ceili(position.x+8))):
				var cell := Vector2i(x,y)
				var delta := Vector2(cell)+Vector2.ONE*0.5-position
				if absf(delta.dot(direction))>0.85 or absf(delta.dot(normal))>fall["radius"]+2.4: continue
				if terrain[y*size.x+x] in [1,4,22] and cell not in fall["barrier_cells"]: continue
				occupied.append(cell)
				cells[cell] = true
				used[cell] = true
		for cell in fall["barrier_cells"]:
			if cell not in occupied: occupied.append(cell)
			cells[cell] = true
		scenery.append({"id":-700000-scenery.size(),"kind":"cliff","asset_name":"river_ledge","river_feature":"ledge",
			"position":position+direction*1.4,"river_form":fall.duplicate(true),"river_barrier":true,
			"river_crest_level":float(fall["upper_level"]),"occupied_cells":occupied,"animated":true,
			"presentation_layer":"scenery","presentation_bounds":[-7.0,-5.0,7.0,5.0]})

static func obstruction_cells(rivers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for fall in rivers.get("waterfalls", []):
		for cell in fall["barrier_cells"]: result[cell] = true
	for rapid in rivers.get("rapids", []):
		for cell in rapid["barrier_cells"]: result[cell] = true
	return result

static func pool_reservations(size: Vector2i, _terrain: Array[int], rivers: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for fall in rivers.get("waterfalls",[]):
		var center: Vector2 = fall["position"]
		var direction: Vector2 = fall["direction"]
		var normal := Vector2(-direction.y,direction.x)
		var reach := ceili(fall["radius"]+8.0)
		for y in range(maxi(0,floori(center.y)-reach),mini(size.y,ceili(center.y)+reach+1)):
			for x in range(maxi(0,floori(center.x)-reach),mini(size.x,ceili(center.x)+reach+1)):
				var delta := Vector2(x+0.5,y+0.5)-center
				if absf(delta.dot(direction))<8.5 and absf(delta.dot(normal))<fall["radius"]+6.5: result[Vector2i(x,y)] = true
	return result

static func restore_pools(size: Vector2i, _terrain: Array[int], levels: Array[int], rivers: Dictionary) -> void:
	# The same bedrock step continues into both banks. Blend the outer shoulders
	# into the valley; otherwise a rock face appears suspended over low grass.
	for fall in rivers.get("waterfalls",[]):
		var position: Vector2 = fall["position"]
		var direction: Vector2 = fall["direction"]
		var normal := Vector2(-direction.y,direction.x)
		var reach := ceili(fall["radius"]+8.0)
		for y in range(maxi(0,floori(position.y)-reach),mini(size.y+1,ceili(position.y)+reach+1)):
			for x in range(maxi(0,floori(position.x)-reach),mini(size.x+1,ceili(position.x)+reach+1)):
				var delta := Vector2(x,y)-position
				var along := delta.dot(direction)
				var across := absf(delta.dot(normal))
				var amount := (1.0-smoothstep(fall["radius"]+2.0,fall["radius"]+6.0,across))*(1.0-smoothstep(5.0,8.0,absf(along)))
				if amount<=0.0: continue
				var transition := smoothstep(-0.4,0.4,along)
				var target := lerpf(fall["upper_level"],fall["lower_level"],transition)
				var at := y*(size.x+1)+x
				levels[at] = roundi(lerpf(levels[at],target,amount))

static func decorate(_data: Dictionary) -> void:
	# The animated water sheet belongs to the ledge geometry itself.
	pass

static func update_presentation(size: Vector2i,levels: Array[int],items: Array) -> void:
	for item in items:
		if not item.get("river_barrier",false): continue
		var point: Vector2 = item["position"]
		var cell := Vector2i(point.floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
		var at := cell.y*(size.x+1)+cell.x
		var f := point-Vector2(cell)
		var actual := lerpf(lerpf(levels[at],levels[at+1],f.x),lerpf(levels[at+size.x+1],levels[at+size.x+2],f.x),f.y)
		item["cliff_screen_offset"] = Vector2(0,(actual-float(item["river_crest_level"]))*16.0)
