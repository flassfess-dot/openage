class_name RoRRandomMapRivers
extends RefCounted

const Navigation := preload("res://scripts/random_map_navigation.gd")
const Channels := preload("res://scripts/random_map_river_channels.gd")
const Network := preload("res://scripts/random_map_river_network.gd")
const DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]
const SHOAL := 15 # Native WaterImpassable: no land or ship restriction admits it.
const FORD := 4 # Native Shallows: infantry and ships, with source shallows art.
const MOUTH_CLEARANCE := 8

# Priority flood gives every land cell an acyclic downstream route to the sea.
# Accumulated runoff determines channel size, tributaries and lower-river depth.
static func carve(size: Vector2i, terrain: Array[int], relief: Dictionary, options: Dictionary = {}) -> Dictionary:
	var count := terrain.size()
	var parent := PackedInt32Array()
	var head := PackedInt32Array()
	var distance := PackedInt32Array()
	var basin := PackedInt32Array()
	var seen := PackedByteArray()
	var runoff := PackedFloat32Array()
	var strongest := PackedInt32Array()
	var spill := PackedInt32Array()
	var physical_head := PackedInt32Array()
	physical_head.resize(count)
	spill.resize(count)
	parent.resize(count)
	parent.fill(-1)
	head.resize(count)
	distance.resize(count)
	basin.resize(count)
	basin.fill(-1)
	seen.resize(count)
	runoff.resize(count)
	strongest.resize(count)
	strongest.fill(-1)
	var original := terrain.duplicate()
	var levels: Array[int] = relief["vertex_levels"]
	var heap: Array[Vector2i] = []
	for i in range(count):
		if original[i] != 0:
			seen[i] = 1
			continue
		var x := i % size.x
		var y := i / size.x
		var vertex := y * (size.x + 1) + x
		head[i] = (levels[vertex] + levels[vertex + 1] + levels[vertex + size.x + 1] + levels[vertex + size.x + 2]) * 250
		physical_head[i] = head[i]
		head[i] += int(relief["coast_distance"][i]) * 8 + roundi(float(relief["geology"][i]) * 120.0)
		runoff[i] = 0.6 + float(relief["moisture"][i]) * 1.4
		for direction in DIRECTIONS:
			var next: Vector2i = Vector2i(x, y) + direction
			if not Navigation.inside(next, size): continue
			var index: int = next.y * size.x + next.x
			if original[index] == 0: continue
			seen[i] = 1
			parent[i] = index
			basin[i] = i
			distance[i] = 1
			spill[i] = head[i]
			_push(heap, Vector2i(head[i], i))
			break
		# Inland regions may drain beyond the map rather than into an artificial
		# ocean border. The terminal land cell is a legitimate boundary outlet.
		if seen[i] == 0 and bool(options.get("edge_outlets", false)) and (x == 0 or y == 0 or x == size.x - 1 or y == size.y - 1):
			seen[i] = 1
			basin[i] = i
			distance[i] = 1
			spill[i] = head[i]
			_push(heap, Vector2i(head[i], i))
	var raw_head := head.duplicate() if not options.is_empty() else PackedInt32Array()
	var order := PackedInt32Array()
	while not heap.is_empty():
		var entry := _pop(heap)
		var i := entry.y
		order.append(i)
		var cell := Vector2i(i % size.x, i / size.x)
		for direction in DIRECTIONS:
			var next: Vector2i = cell + direction
			if not Navigation.inside(next, size): continue
			var index: int = next.y * size.x + next.x
			if seen[index] != 0: continue
			seen[index] = 1
			parent[index] = i
			basin[index] = basin[i]
			head[index] = maxi(head[index], head[i] + 1)
			spill[index] = maxi(spill[i], raw_head[index]) if not options.is_empty() else head[index]
			physical_head[index] = maxi(physical_head[index], physical_head[i])
			distance[index] = distance[i] + 1
			_push(heap, Vector2i(head[index], index))
	for cursor in range(order.size() - 1, -1, -1):
		var i := order[cursor]
		var next := parent[i]
		if next < 0 or original[next] != 0: continue
		runoff[next] += runoff[i]
		if strongest[next] < 0 or runoff[i] > runoff[strongest[next]]: strongest[next] = i
	var threshold := float(options.get("runoff_threshold", maxf(32.0, mini(size.x, size.y) * 0.18)))
	# Tiny coastal catchments remain implicit streams. Only a substantial basin
	# cuts a visible river, while its smaller upstream tributaries stay connected.
	var minimum_basin_runoff := float(options.get("minimum_basin_runoff", threshold * 4.5))
	var mask := PackedByteArray()
	var types := PackedInt32Array()
	var coverage := PackedFloat32Array()
	var surface_levels := PackedInt32Array()
	surface_levels.resize(count)
	surface_levels.fill(-1)
	mask.resize(count)
	types.resize(count)
	types.fill(-1)
	coverage.resize(count)
	var nodes: Array = []
	var incoming: Dictionary = {}
	var mouth_count := 0
	var natural_channels := bool(options.get("natural_channels", false))
	for i in order:
		if runoff[i] < threshold or basin[i] < 0 or runoff[basin[i]] < minimum_basin_runoff: continue
		var next := parent[i]
		var boundary_outlet: bool = next < 0 and bool(options.get("edge_outlets", false))
		if next < 0 and not boundary_outlet: continue
		var cell := Vector2i(i % size.x, i / size.x)
		var outlet := cell + (Vector2i.LEFT if cell.x == 0 else Vector2i.RIGHT if cell.x == size.x - 1 else Vector2i.UP if cell.y == 0 else Vector2i.DOWN) if boundary_outlet else Vector2i(next % size.x, next / size.x)
		var is_mouth: bool = boundary_outlet or original[next] != 0
		var direction := Vector2(outlet - cell).normalized()
		var bend := 0.0
		if strongest[i] >= 0:
			var upstream := Vector2i(strongest[i] % size.x, strongest[i] / size.x)
			bend = Vector2(cell - upstream).normalized().cross(direction)
		var radius := clampf((0.8 + sqrt(runoff[i] / threshold) * 0.65) * float(options.get("width_scale", 1.0)), 1.0 if not options.is_empty() else 1.4, float(options.get("maximum_radius", 5.8)))
		if natural_channels: radius=Channels.radius(runoff[i]/float(options.get("width_reference_runoff",threshold)),float(options.get("width_scale",1.0)),float(options.get("maximum_radius",3.2)))
		nodes.append({"cell": cell, "downstream": outlet, "discharge": runoff[i], "head": head[i],
			"downstream_head": head[next] if not is_mouth else 0, "mouth_distance": distance[i],
			"basin": basin[i], "is_mouth": is_mouth, "boundary_outlet": boundary_outlet, "radius": radius, "bend": bend, "surface_level":physical_head[i] / 1000})
		if not is_mouth: incoming[next] = int(incoming.get(next, 0)) + 1
		else: mouth_count += 1
		if natural_channels: continue
		var reach := ceili(radius)
		for y in range(maxi(0, cell.y - reach), mini(size.y, cell.y + reach + 1)):
			for x in range(maxi(0, cell.x - reach), mini(size.x, cell.x + reach + 1)):
				var delta := Vector2(x - cell.x, y - cell.y)
				var strength := 1.0 - delta.length() / radius
				var index := y * size.x + x
				if strength < 0.0 or (mask[index] != 0 and strength <= coverage[index]): continue
				mask[index] = 1
				coverage[index] = strength
				var kind := SHOAL
				if runoff[i] >= threshold * 3.0 and strength >= 0.26: kind = 1
				if runoff[i] >= threshold * 7.0 and distance[i] <= maxi(24, size.x / 10) and strength >= 0.58: kind = 22
				# The inner side of an established bend accumulates sediment; the
				# outside retains its open channel. Banks never span the thalweg.
				var inside := delta.dot(Vector2(-direction.y, direction.x)) * signf(bend)
				if absf(bend) > 0.4 and runoff[i] >= threshold * 3.0 and inside > radius * 0.63 and strength < 0.32:
					kind = 6
				# A river bank must never paint an impassable ring across the sea.
				# Scouring only the outlet's immediate neighbours left that outer
				# ring two or three cells downstream of otherwise open mouths.
				if original[index] != 0: kind = 22 if original[index] == 22 else 1
				types[index] = kind
				surface_levels[index] = physical_head[i] / 1000
	var network_plan: Dictionary={}
	if natural_channels and options.get("network_layout","")=="hierarchical":
		var selected:=Network.select(size,original,nodes,int(options.get("network_seed",1)),options)
		nodes=selected["nodes"];network_plan=selected["plan"]
		incoming.clear();mouth_count=0
		for node in nodes:
			if node["is_mouth"]:mouth_count+=1
			else:incoming[node["downstream"]]=int(incoming.get(node["downstream"],0))+1
	# A shallow tributary's bank must not overwrite the larger river's thalweg.
	# Preserve clearance through bends and confluences, with a scoured outlet
	# joining the sea. This depends on runoff, independently of player access.
	var channel_geometry: Dictionary = {}
	if natural_channels:
		channel_geometry = Channels.build(size, original, nodes, threshold, relief, options)
		mask = channel_geometry["mask"]
		types = channel_geometry["terrain_types"]
		surface_levels = channel_geometry["surface_levels"]
	for node in ([] if natural_channels else nodes):
		if float(node["discharge"]) < threshold * 3.0: continue
		var centers: Array[Vector2i] = [node["cell"]]
		if bool(node["is_mouth"]): centers.append(node["downstream"])
		for center in centers:
			for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var cell: Vector2i = center + offset
				if not Navigation.inside(cell, size): continue
				var index := cell.y * size.x + cell.x
				mask[index] = 1
				if types[index] != 22: types[index] = 1
				var level: int = physical_head[int(node["cell"].y) * size.x + int(node["cell"].x)] / 1000
				surface_levels[index] = level if surface_levels[index] < 0 else mini(surface_levels[index], level)
	var mouth_mask := PackedByteArray()
	mouth_mask.resize(count)
	for node in nodes:
		if not bool(node["is_mouth"]): continue
		var center: Vector2i = node["cell"]
		var reach := maxi(MOUTH_CLEARANCE, ceili(float(node["radius"])) + 2)
		var level: int = physical_head[center.y * size.x + center.x] / 1000
		for y in range(maxi(0, center.y - reach), mini(size.y, center.y + reach + 1)):
			for x in range(maxi(0, center.x - reach), mini(size.x, center.x + reach + 1)):
				if Vector2i(x, y).distance_squared_to(center) > reach * reach: continue
				var index := y * size.x + x
				mouth_mask[index] = 1
				if mask[index] == 0: continue
				if types[index] != 22: types[index] = 1
				surface_levels[index] = level if surface_levels[index] < 0 else mini(surface_levels[index], level)
	var confluences := 0
	for value in incoming.values():
		if int(value) > 1: confluences += 1
	var result := {"mask": mask, "terrain_types": types, "nodes": nodes, "mouth_count": mouth_count,
		"mouth_mask": mouth_mask,
		"surface_levels": surface_levels,
		"confluence_count": confluences, "runoff_threshold": threshold, "minimum_basin_runoff": minimum_basin_runoff,
		"model": "priority_flood_runoff_v1"}
	if natural_channels:
		result["channels"] = channel_geometry["channels"]
		result["model"] = "hydraulic_watershed_channels_v3"
		result["width_reference_runoff"]=float(options.get("width_reference_runoff",threshold))
		if not network_plan.is_empty():
			result["network_plan"]=network_plan
			result["model"]="hierarchical_watershed_channels_v4"
	if not options.is_empty():
		result["drainage"] = {"raw_head": raw_head, "spill_head": spill, "physical_head": physical_head, "head": head,
			"parent": parent, "basin": basin, "runoff": runoff}
	apply(terrain, result)
	return result

static func apply(terrain: Array[int], rivers: Dictionary) -> void:
	var types: PackedInt32Array = rivers.get("terrain_types", PackedInt32Array())
	for i in range(types.size()):
		if types[i] >= 0: terrain[i] = types[i]

static func inspect(rivers: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var nodes: Dictionary = {}
	for node in rivers.get("nodes", []): nodes[node["cell"]] = node
	var incoming_runoff: Dictionary = {}
	for node in nodes.values():
		if int(node["head"]) < int(node["downstream_head"]): errors.append("river_uphill")
		var next: Dictionary = nodes.get(node["downstream"], {})
		if not next.is_empty():
			incoming_runoff[node["downstream"]] = float(incoming_runoff.get(node["downstream"], 0.0)) + float(node["discharge"])
			if float(next["discharge"]) + 0.001 < float(node["discharge"]): errors.append("river_runoff_lost")
			if int(next["head"]) >= int(node["head"]): errors.append("river_drainage_order_invalid")
			if int(next["mouth_distance"]) != int(node["mouth_distance"]) - 1: errors.append("river_distance_invalid")
		elif not bool(node.get("is_mouth", false)):
			errors.append("river_disconnected_from_outlet")
	for cell in incoming_runoff:
		if float(incoming_runoff[cell]) > float(nodes[cell]["discharge"]) + 0.01: errors.append("river_confluence_runoff_lost")
	return {"valid": errors.is_empty(), "errors": errors, "channel_nodes": nodes.size(),
		"mouths": rivers.get("mouth_count", 0), "confluences": rivers.get("confluence_count", 0)}

static func _before(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)

static func _push(heap: Array[Vector2i], value: Vector2i) -> void:
	heap.append(value)
	var at := heap.size() - 1
	while at > 0:
		var parent := (at - 1) / 2
		if not _before(heap[at], heap[parent]): break
		var swap := heap[parent]
		heap[parent] = heap[at]
		heap[at] = swap
		at = parent

static func _pop(heap: Array[Vector2i]) -> Vector2i:
	var result := heap[0]
	var last: Vector2i = heap.pop_back()
	if heap.is_empty(): return result
	heap[0] = last
	var at := 0
	while at * 2 + 1 < heap.size():
		var child := at * 2 + 1
		if child + 1 < heap.size() and _before(heap[child + 1], heap[child]): child += 1
		if not _before(heap[child], heap[at]): break
		var swap := heap[at]
		heap[at] = heap[child]
		heap[child] = swap
		at = child
	return result
