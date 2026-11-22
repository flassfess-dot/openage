extends RefCounted

const Landscape := preload("res://scripts/random_map_landscape.gd")
const Silt := 1100
const FloodMeadow := 1101
const Terrace := 1102
const Shingle := 1103
const DryMeadow := 1104
const SnowGrass := 1110
const SnowEarth := 1111
const AlpineMeadow := 1112
const SnowCap := 1113
const Limestone := 1120
const RedEarth := 1121
const Scrub := 1122
const Beach := 1123


static func apply(data: Dictionary, fields: Dictionary, climate: String) -> void:
	if climate == "temperate": return
	var size: Vector2i = data["size"]
	var terrain: Array[int] = data["terrain_ids"]
	var surfaces := PackedInt32Array(terrain)
	var distance := Landscape.coast_distances(size, terrain)
	var sea_distance := _sea_distances(data) if climate == "aegean" else PackedInt32Array()
	var variation := Landscape.noise_field(size, 9.0, int(data["seed"]) ^ 0xC11A)
	var levels: Array = data["vertex_levels"]
	var snow_line := maxf(1.5, float(levels.max()) * 0.55) if climate == "anatolia" else 0.0
	for i in range(terrain.size()):
		var id := terrain[i]
		if id in [1, 4, 15, 22]: continue
		var vertex := i + i / size.x
		var level := 0.25 * float(levels[vertex] + levels[vertex + 1] + levels[vertex + size.x + 1] + levels[vertex + size.x + 2])
		var wetness := float(fields["moisture"][i])
		if climate == "nile":
			surfaces[i] = _nile(id, distance[i], level, variation[i], wetness)
		elif climate == "anatolia":
			var exposure := float(levels[vertex + size.x + 2] - levels[vertex]) * 0.28
			surfaces[i] = _anatolia(id, level, snow_line, exposure, variation[i], wetness, fields["geology"][i])
		elif climate == "aegean":
			surfaces[i] = _aegean(id, sea_distance[i], level, variation[i], fields["geology"][i])
	_mark_fords(data, surfaces)
	data["climate_id"] = climate
	data["climate_surfaces"] = surfaces
	data["ford_gravel"] = Shingle
	if climate == "nile": data["bank_silt"] = Silt
	_dress_trees(data, distance, variation)
	_prune_green_decals(data)


static func _sea_distances(data: Dictionary) -> PackedInt32Array:
	var water: Array[int] = data["terrain_ids"].duplicate()
	var rivers: Dictionary = data["rivers"]
	for i in range(water.size()):
		var sea: bool = water[i] in [1, 4, 15, 22] and (rivers["mask"][i] == 0 or rivers["mouth_mask"][i] != 0)
		water[i] = 1 if sea else 0
	for lake in data["lakes"]:
		for i in lake["cells"]: water[i] = 0
	return Landscape.coast_distances(data["size"], water)


static func _prune_green_decals(data: Dictionary) -> void:
	# These particular sprites include a painted green ground patch.
	var green := ["ror_grass", "undergrowth", "overgrown_trail", "ror_grass_trail", "ror_stone_grass_trail", "ror_grass_rocks"]
	var size: Vector2i = data["size"]
	data["scenery"] = data["scenery"].filter(func(item):
		if item.get("decoration_key", "") not in green: return true
		var cell := Vector2i(item["position"])
		var id: int = data["climate_surfaces"][cell.y * size.x + cell.x]
		return id not in [Silt, Shingle, Terrace, SnowGrass, SnowEarth, SnowCap, RedEarth, Limestone, Beach])


static func _nile(id: int, distance: int, level: float, variation: float, wetness: float) -> int:
	if id == 1005: return Shingle
	if id == 1004 or (distance <= 1 and variation + wetness > 0.7): return Silt
	var terrace_distance := float(distance) + level * 1.2 - variation * 4.0 - wetness * 2.0
	if terrace_distance < 2.0: return FloodMeadow
	if terrace_distance < 5.5: return 1003 if id in [10, 1003] else FloodMeadow
	if terrace_distance < 8.5: return DryMeadow
	return Terrace


static func _anatolia(id: int, level: float, snow_line: float, exposure: float, variation: float, wetness: float, rock: float) -> int:
	if id in [2, 1004, 1005]: return id
	var cold := level - snow_line + exposure + (variation - 0.5) * 1.4
	if level >= 1.5 and cold >= 0.0:
		if cold >= 1.5: return SnowCap
		return SnowEarth if rock > 0.52 or cold > 0.75 else SnowGrass
	if id in [10, 1003]: return 1003
	return DryMeadow if wetness < 0.38 and variation > 0.52 else AlpineMeadow


static func _aegean(id: int, sea_distance: int, level: float, variation: float, rock: float) -> int:
	if id in [1004, 1005]: return id
	var headland := rock * 0.5 + variation * 0.5 + level * 0.08
	if sea_distance <= 3:
		return Limestone if headland > 0.53 else Beach
	if id == 2: return Shingle
	if headland > 0.78 or (sea_distance <= 7 and headland > 0.57): return Limestone
	return RedEarth if variation * 0.65 + rock * 0.35 > 0.53 else Scrub


static func _mark_fords(data: Dictionary, surfaces: PackedInt32Array) -> void:
	var size: Vector2i = data["size"]
	for ford in data.get("fords", []):
		var a: Vector2 = ford["bank_a"]
		var b: Vector2 = ford["bank_b"]
		var direction := a.direction_to(b)
		a -= direction * 1.8
		b += direction * 1.8
		var width := float(ford.get("half_width", 1.3))
		var low := Vector2i((a.min(b) - Vector2.ONE * width).floor()).max(Vector2i.ZERO)
		var high := Vector2i((a.max(b) + Vector2.ONE * width).ceil()).min(size)
		for y in range(low.y, high.y):
			for x in range(low.x, high.x):
				var index := y * size.x + x
				if data["terrain_ids"][index] in [1, 4, 15, 22]: continue
				var point := Vector2(x + 0.5, y + 0.5)
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b)) <= width:
					surfaces[index] = Shingle


static func _dress_trees(data: Dictionary, distance: PackedInt32Array, variation: PackedFloat32Array) -> void:
	var palettes: Dictionary = Landscape.theme()["tree_palettes"]
	var size: Vector2i = data["size"]
	var seed: int = data["seed"]
	var sources := {"ror": 0, "aoe2": 0}
	if data["climate_id"] == "aegean": sources["regional"] = 0
	for tree in data["resources"]:
		if tree.get("kind", "") != "tree": continue
		var cell := Vector2i(tree["position"])
		var index := cell.y * size.x + cell.x
		var roll := Landscape.random_at(cell, seed ^ 0x7A1E)
		if data["climate_id"] == "nile" and (distance[index] < 11 or variation[index] > 0.52) and roll < 0.84:
			var palms: Array = palettes["palm"]["native"]
			var variant := mini(palms.size() - 1, int(Landscape.random_at(cell, seed ^ 0xDA7E) * palms.size()))
			Landscape._bind_native_tree(tree, palms[variant])
			tree.erase("environment_asset")
			tree.erase("environment_variant")
			tree.erase("tree_condition")
		elif data["climate_id"] == "anatolia" and (Landscape.is_palm(tree) or (data["climate_surfaces"][index] in [SnowEarth, SnowGrass, SnowCap] and roll < 0.83)):
			var conifers: Array = palettes["conifer"]["native"]
			Landscape._bind_native_tree(tree, conifers[int(roll * 32768) % conifers.size()])
			tree["environment_asset"] = "pine"
			tree["environment_variant"] = int(roll * 1000) % int(palettes["conifer"]["imported_variants"])
			tree.erase("tree_condition")
		elif data["climate_id"] == "aegean" and roll < 0.87:
			tree["environment_asset"] = "cypress" if variation[index] + roll * 0.2 > 0.66 else "olive"
			tree["environment_variant"] = 0
			tree.erase("tree_condition")
		var source := "aoe2" if tree.has("environment_asset") else "ror"
		if tree.get("environment_asset", "") in ["olive", "cypress"]: source = "regional"
		sources[source] += 1
	data["ecology"]["tree_sources"] = sources
