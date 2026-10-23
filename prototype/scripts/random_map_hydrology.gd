class_name RoRRandomMapHydrology
extends RefCounted

const Rivers := preload("res://scripts/random_map_rivers.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Crossings := preload("res://scripts/random_map_river_crossings.gd")
const RiverSurface := preload("res://scripts/random_map_river_surface.gd")
const RiverBanks := preload("res://scripts/random_map_river_banks.gd")
const RiverFalls := preload("res://scripts/random_map_river_falls.gd")
const RiverRapids := preload("res://scripts/random_map_river_rapids.gd")

# Shared by geographic profiles, including highlands. Neither feature receives
# settlement positions. Lake/ford counts scale with geographic area and reach.
static func build(size: Vector2i, terrain: Array[int], fields: Dictionary, seed: int, options: Dictionary = {}) -> Dictionary:
	var span := float(mini(size.x, size.y))
	var threshold := maxf(float(options.get("minimum_runoff", 48.0)), span * float(options.get("runoff_scale", 0.55)))
	var original := terrain.duplicate()
	var river_options:=options.duplicate(true)
	# The hydraulic reference is independent of the visibility threshold and
	# basin/tributary quotas. Increasing a visibility cutoff cannot narrow water.
	river_options.merge({"runoff_threshold":threshold,"minimum_basin_runoff":threshold*float(options.get("basin_scale",10.0)),
		"width_reference_runoff":float(options.get("width_reference_runoff",maxf(48.0,span*0.55))),
		"width_scale":float(options.get("width_scale",0.9)),"maximum_radius":float(options.get("maximum_radius",3.2)),
		"natural_channels":true,"edge_outlets":bool(options.get("edge_outlets",false)),"network_seed":seed},true)
	var rivers := Rivers.carve(size, terrain, fields, river_options)
	var lakes := _lakes(size, original, rivers, seed)
	Rivers.apply(terrain, rivers)
	rivers["waterfalls"] = RiverFalls.plan(size,terrain,rivers,lakes,seed) if options.get("waterfalls",false) else []
	Rivers.apply(terrain,rivers)
	rivers["rapids"] = RiverRapids.plan(size,terrain,rivers,lakes,seed)
	Rivers.apply(terrain,rivers)
	rivers["shoals"] = RiverBanks.build(size, terrain, fields, rivers, lakes, seed)
	Rivers.apply(terrain, rivers)
	var fords := _fords(size, terrain, fields, rivers, lakes, seed)
	Rivers.apply(terrain, rivers)
	rivers["surface"] = RiverSurface.build(size, original, rivers, lakes, fords)
	RiverSurface.classify(size,rivers,lakes,fords)
	Rivers.apply(terrain,rivers)
	rivers.erase("drainage")
	rivers["ford_count"] = fords.size()
	rivers["lake_count"] = lakes.size()
	return {"rivers": rivers, "lakes": lakes, "fords": fords}

static func _lakes(size: Vector2i, original: Array[int], rivers: Dictionary, seed: int) -> Array:
	var drainage: Dictionary = rivers["drainage"]
	var raw: PackedInt32Array = drainage["raw_head"]
	var spill: PackedInt32Array = drainage["spill_head"]
	var basin: PackedInt32Array = drainage["basin"]
	var seen := PackedByteArray()
	seen.resize(original.size())
	var candidates: Array = []
	var minimum := maxi(18, size.x * size.y / 3500)
	var maximum := maxi(80, size.x * size.y / 60)
	for i in range(original.size()):
		if seen[i] != 0 or original[i] != 0 or spill[i] - raw[i] < 55: continue
		var queue := PackedInt32Array([i])
		seen[i] = 1
		var cursor := 0
		var depth := 0.0
		var center := Vector2.ZERO
		while cursor < queue.size():
			var at := queue[cursor]
			cursor += 1
			depth += spill[at] - raw[at]
			center += Vector2(at % size.x, at / size.x)
			for next in Navigation.neighbors(at, size):
				if seen[next] != 0 or original[next] != 0 or basin[next] != basin[i] or spill[next] != spill[i] or spill[next] - raw[next] < 55: continue
				seen[next] = 1
				queue.append(next)
		if queue.size() < minimum or queue.size() > maximum: continue
		center /= queue.size()
		candidates.append({"cells": queue, "center": center, "spill_head": spill[i], "basin": basin[i],
			"score": sqrt(float(queue.size())) * depth / queue.size() * (0.8 + Topology.roll(Vector2i(center), seed ^ 0x14A31) * 0.4)})
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var lakes: Array = []
	var target := maxi(1, ceili(float(size.x * size.y) / 35000.0))
	for candidate in candidates:
		if lakes.size() >= target: break
		if lakes.any(func(lake): return Vector2(lake["center"]).distance_to(candidate["center"]) < mini(size.x, size.y) * 0.10): continue
		var cells: PackedInt32Array = candidate["cells"]
		var lookup: Dictionary = {}
		for i in cells: lookup[i] = true
		var shore_distance: Dictionary = {}
		var pending := PackedInt32Array()
		for i in cells:
			for next in Navigation.neighbors(i, size):
				if not lookup.has(next):
					shore_distance[i] = 1
					pending.append(i)
					break
		var cursor := 0
		while cursor < pending.size():
			var at := pending[cursor]
			cursor += 1
			for next in Navigation.neighbors(at, size):
				if lookup.has(next) and not shore_distance.has(next):
					shore_distance[next] = int(shore_distance[at]) + 1
					pending.append(next)
		var outlet := cells[0]
		var surface_level := 2147483647
		for i in cells: surface_level = mini(surface_level, int(drainage["physical_head"][i]) / 1000)
		for i in cells:
			if int(drainage["head"][i]) < int(drainage["head"][outlet]): outlet = i
			rivers["mask"][i] = 1
			rivers["terrain_types"][i] = 22 if int(shore_distance.get(i, 1)) >= 3 else 1
			rivers["surface_levels"][i] = surface_level
		lakes.append({"center": candidate["center"], "cells": cells, "area": cells.size(), "basin": candidate["basin"],
			"spill_head": candidate["spill_head"], "surface_level": surface_level, "outlet": Vector2i(outlet % size.x, outlet / size.x), "origin": "filled_relief_depression"})
	return lakes

# Preserve the physical relief used to find the watersheds. Recomputing all
# heights from distance to newly painted water would turn every mountain lake
# and upstream river into a sea-level trench. Hydraulic ordering also contains
# drainage tie-breaks; physical_head deliberately excludes those artificial terms.
static func apply_surface_relief(size: Vector2i, terrain: Array[int], levels: Array[int], rivers: Dictionary, lakes: Array) -> void:
	RiverBanks.shape_valleys(size,terrain,levels,rivers)
	var width := size.x + 1
	var desired := PackedInt32Array()
	desired.resize(levels.size())
	desired.fill(-1)
	var surfaces: PackedInt32Array = rivers["surface_levels"]
	for i in range(terrain.size()):
		if surfaces[i] < 0 or terrain[i] not in Rules.WATER_TERRAIN_IDS: continue
		var vertex := (i / size.x) * width + i % size.x
		for corner in [vertex, vertex + 1, vertex + width, vertex + width + 1]:
			desired[corner] = surfaces[i] if desired[corner] < 0 else mini(desired[corner], surfaces[i])
	for i in range(levels.size()):
		if desired[i] >= 0: levels[i] = desired[i]
	var flat: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: flat[Vector2i(i % size.x, i / size.x)] = true
	for i in range(terrain.size()):
		if terrain[i] == Rivers.FORD: flat[Vector2i(i % size.x, i / size.x)] = true
	Landscape.relax_heights(levels, size, flat)
	refresh_lake_levels(size, levels, lakes)

static func refresh_lake_levels(size: Vector2i, levels: Array[int], lakes: Array) -> void:
	for lake in lakes:
		var i := int(lake["cells"][0])
		lake["surface_level"] = levels[(i / size.x) * (size.x + 1) + i % size.x]

static func _fords(size: Vector2i, terrain: Array[int], fields: Dictionary, rivers: Dictionary, lakes: Array, seed: int) -> Array:
	if rivers.has("channels"):
		return Crossings.build(size, terrain, fields, rivers, lakes, seed)
	var nodes: Array = rivers["nodes"]
	var incoming: Dictionary = {}
	for node in nodes:
		var next: Vector2i = node["downstream"]
		incoming[next] = int(incoming.get(next, 0)) + 1
	var junctions: Array = incoming.keys().filter(func(cell): return int(incoming[cell]) > 1)
	var lake_cells: Dictionary = {}
	for lake in lakes:
		for i in lake["cells"]: lake_cells[i] = true
	var candidates: Array = []
	var threshold := float(rivers["runoff_threshold"])
	var drainage: Dictionary = rivers["drainage"]
	var mouth_mask: PackedByteArray = rivers["mouth_mask"]
	for node in nodes:
		var cell: Vector2i = node["cell"]
		var i := cell.y * size.x + cell.x
		if mouth_mask[i] != 0: continue
		if node["mouth_distance"] < 14 or node["discharge"] < threshold * 3.0 or node["discharge"] > threshold * 5.5 or absf(float(node["bend"])) > 0.15: continue
		if lake_cells.has(i) or terrain[i] == 22 or int(node["head"]) - int(node["downstream_head"]) > 160: continue
		if junctions.any(func(at): return Vector2(at).distance_to(cell) < 8.0): continue
		if lakes.any(func(lake): return Vector2(lake["center"]).distance_to(cell) < sqrt(float(lake["area"])) + 8.0): continue
		var delta: Vector2i = node["downstream"] - cell
		var normal := Vector2i.DOWN if absi(delta.x) > absi(delta.y) else Vector2i.RIGHT
		var banks: Array[Vector2i] = []
		for sign_axis in [-1, 1]:
			for step in range(1, 13):
				var at: Vector2i = cell + normal * step * sign_axis
				if not Navigation.inside(at, size): break
				var index := at.y * size.x + at.x
				if terrain[index] not in Rules.WATER_TERRAIN_IDS and rivers["mask"][index] == 0:
					banks.append(at)
					break
		if banks.size() != 2 or Vector2(banks[0]).distance_to(banks[1]) > 12.0: continue
		var a := banks[0].y * (size.x + 1) + banks[0].x
		var b := banks[1].y * (size.x + 1) + banks[1].x
		if absi(int(fields["vertex_levels"][a]) - int(fields["vertex_levels"][b])) > 1: continue
		if int(drainage["spill_head"][i]) - int(drainage["raw_head"][i]) > 80: continue
		candidates.append({"node": node, "banks": banks, "normal": normal, "score": Topology.roll(cell, seed ^ 0xF04D)})
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var fords: Array = []
	for candidate in candidates:
		if fords.size() >= maxi(1, ceili(mini(size.x, size.y) / 48.0)): break
		var cell: Vector2i = candidate["node"]["cell"]
		if fords.any(func(ford): return Vector2(ford["center"]).distance_to(cell) < maxf(20.0, mini(size.x, size.y) * 0.085)): continue
		var normal: Vector2i = candidate["normal"]
		var tangent := Vector2i(-normal.y, normal.x)
		var banks: Array[Vector2i] = candidate["banks"]
		var cells: Array[Vector2i] = []
		var approaches: Array[Vector2i] = []
		var near_mouth := false
		var length := roundi(Vector2(banks[0]).distance_to(banks[1]))
		for step in range(-2, length + 3):
			for side in range(-1, 2):
				var at := banks[0] + normal * step + tangent * side
				if not Navigation.inside(at, size): continue
				var i := at.y * size.x + at.x
				approaches.append(at)
				if mouth_mask[i] != 0: near_mouth = true
				if terrain[i] in Rules.WATER_TERRAIN_IDS:
					cells.append(at)
		if near_mouth: continue
		for at in approaches: rivers["mask"][at.y * size.x + at.x] = 1
		for at in cells: rivers["terrain_types"][at.y * size.x + at.x] = Rivers.FORD
		if not cells.is_empty(): fords.append({"center": cell, "bank_a": Vector2(banks[0]) + Vector2.ONE * 0.5,
			"bank_b": Vector2(banks[1]) + Vector2.ONE * 0.5, "cells": cells, "discharge": candidate["node"]["discharge"], "origin": "gentle_nonconfluent_reach"})
	return fords


static func decorate_fords(data: Dictionary, seed: int) -> void:
	if data.get("rivers", {}).get("surface", {}).get("model_version", 0) >= 2:
		# The ground material now supplies the continuous bar. Full oval source
		# sprites would reintroduce the isolated patches this field replaces.
		data["scenery"] = data["scenery"].filter(func(item): return item.get("decoration_key", "") != "ror_shallows")
		data["decoration_summary"] = Landscape.Decorations.summarize(data["scenery"])
		return
	# Native Shallows (terrain 4) uses water plus unit 80's sandy islets.
	# Reuse the imported source frames, below units and without obstructions.
	var spec: Dictionary = {}
	for entry in Landscape.Decorations.palette():
		if entry["key"] == "ror_shallows": spec = entry; break
	if spec.is_empty(): return
	# The ambient shoreline pass also uses Shallows art. Exclude those stamps
	# from estuaries so open mouths cannot look like pedestrian crossings.
	if data.has("rivers"):
		data["scenery"] = data["scenery"].filter(func(item): return item.get("asset_name", "") != "aoe2_temperate:ror_shallows" or not _ford_detail_touches_mouth(data, spec, int(item["source_frame"]), item["position"]))
	var placed: Array[Vector2] = []
	var seen: Dictionary = {}
	for ford in data.get("fords", []):
		var candidates: Array = ford["cells"].duplicate()
		candidates.sort_custom(func(a, b): return Vector2i(a).distance_squared_to(ford["center"]) < Vector2i(b).distance_squared_to(ford["center"]))
		var has_anchor := false
		for cell in candidates:
			if seen.has(cell): continue
			seen[cell] = true
			var frame: int = 3 if not has_anchor else [0, 1, 3, 5, 6][mini(4, int(Topology.roll(cell, seed ^ 0x54A111) * 5.0))]
			var position := Vector2.INF
			for offset in [Vector2.ZERO, Vector2(-0.25, -0.25), Vector2(0.25, -0.25), Vector2(-0.25, 0.25), Vector2(0.25, 0.25), Vector2(-0.5,-0.5), Vector2(0.5,-0.5), Vector2(-0.5,0.5), Vector2(0.5,0.5)]:
				var candidate: Vector2 = Vector2(cell) + Vector2.ONE * 0.5 + offset
				if placed.any(func(at): return at.distance_squared_to(candidate) < 0.95 * 0.95): continue
				if not _ford_detail_fits(data, spec, frame, candidate): continue
				position = candidate
				break
			if not position.is_finite(): continue
			has_anchor = true
			placed.append(position)
			data["scenery"].append({"id": -800000 - data["scenery"].size(), "asset_name": "aoe2_temperate:ror_shallows",
				"position": position, "source_frame": frame, "presentation_layer": "decal", "ford_detail": true,
				"decoration_key": "ror_shallows", "source_game": "ror", "feature_family": "ror_shallows", "ecology_role": "ford_detail",
				"ambient": true, "route_id": -1, "presentation_bounds": spec["ground_bounds"][frame]})
	# Filtering ambient stamps leaves gaps in their original ID sequence.
	# Publish one unique sequence for the renderer's static-object caches.
	for i in range(data["scenery"].size()): data["scenery"][i]["id"] = -800000 - i
	data["decoration_summary"] = Landscape.Decorations.summarize(data["scenery"])

static func _ford_detail_touches_mouth(data: Dictionary, spec: Dictionary, frame: int, position: Vector2) -> bool:
	var size: Vector2i = data["size"]
	for cell in Landscape.Decorations.footprint_cells(spec, frame, position):
		if Navigation.inside(cell, size) and data["rivers"]["mouth_mask"][cell.y * size.x + cell.x] != 0: return true
	return false

static func _ford_detail_fits(data: Dictionary, spec: Dictionary, frame: int, position: Vector2) -> bool:
	# Ford membership supplies the habitat; the whole flat sprite must stay on
	# water, including its opaque blue border, rather than spilling over a bank.
	var size: Vector2i = data["size"]
	var cell := Vector2i(position.floor())
	if not Navigation.inside(cell, size): return false
	var levels: Array = data["vertex_levels"]
	var reference := int(levels[cell.y * (size.x + 1) + cell.x])
	for covered in Landscape.Decorations.footprint_cells(spec, frame, position):
		if not Navigation.inside(covered, size): return false
		var index := covered.y * size.x + covered.x
		if int(data["terrain_ids"][index]) not in [1, 4, 22]: return false
		if data.has("rivers") and data["rivers"]["mouth_mask"][index] != 0: return false
		var vertex := covered.y * (size.x + 1) + covered.x
		for offset in [0, 1, size.x + 1, size.x + 2]:
			if int(levels[vertex + offset]) != reference: return false
	# The raster and the smoothly rendered shoreline need not coincide.
	# Check the visible contour too, including the sprite's blue perimeter.
	var shape: Dictionary = data.get("rivers", {}).get("surface", {})
	var bounds: Array = spec["ground_bounds"][frame]
	for y in range(5):
		for x in range(5):
			var point := position + Vector2(lerpf(bounds[0], bounds[2], x / 4.0), lerpf(bounds[1], bounds[3], y / 4.0))
			var field := RiverSurface.sample(shape, point)
			if field.y > 0.05 and field.x < 0.08: return false
	return true
