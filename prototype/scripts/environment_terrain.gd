class_name RoREnvironmentTerrain

const Coordinates := preload("res://scripts/coordinates.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")
const TerrainElevation := preload("res://scripts/terrain_elevation.gd")
const SUBDIVISIONS := 8
const BLEND_SUBDIVISIONS := 4
const MATERIAL_HALO := 2
const RiverSurface := preload("res://scripts/random_map_river_surface.gd")


static func affects(cell: Vector2i, provider: Callable, pack) -> bool:
	if pack == null or not pack.enabled:
		return false
	return int(provider.call(cell)) >= 0


static func _material_id(id: int, pack) -> int:
	if pack != null and pack.has_material(id):
		return id
	if id in [1, 4, 15, 22]: return id
	return 6 if id in [2, 6, 13] else 0


static func _priority(id: int, pack) -> int:
	if id == 4: return -3
	if id in [1, 4, 15, 22]: return -5 if id == 22 else -4 if id == 1 else -3
	return int(pack.materials_by_id[id]["priority"]) if pack.has_material(id) else (-1 if id == 0 else 0)


static func weights(point: Vector2, provider: Callable, pack, fallback: int) -> Dictionary:
	var sample := _coast_sample(point)
	var coverage := _coast_coverage(sample, provider)
	# Sample a continuous footprint around the point. The slow drift bends soil
	# boundaries in world space while the shoreline keeps its own precise contour.
	var drift := Vector2(sin(point.y * 1.37 + sin(point.x * 0.73)), cos(point.x * 1.19 + sin(point.y * 0.91))) * 0.22
	var ground := sample + drift
	var origin := Vector2i(ground.floor())
	var local := ground - Vector2(origin)
	var horizontal := _material_taps(local.x)
	var vertical := _material_taps(local.y)
	var result: Dictionary = {}
	var land := 0.0
	var water := 0.0
	for y in range(4):
		for x in range(4):
			var id := int(provider.call(origin + Vector2i(x - 1, y - 1)))
			if id < 0:
				continue
			id = _material_id(id, pack)
			var weight := horizontal[x] * vertical[y]
			if id in [1, 4, 15, 22]:
				water += weight
			else:
				land += weight
			result[id] = float(result.get(id, 0.0)) + weight
	if land + water < 0.000001: return {fallback: 1.0}
	var land_scale := coverage / land if land > 0.0 else 0.0
	var water_scale := (1.0 - coverage) / water if water > 0.0 else 0.0
	for id in result:
		result[id] *= water_scale if id in [1, 4, 15, 22] else land_scale
	return result


static func _material_taps(fraction: float) -> Vector4:
	# Compact biweight kernel. Both the value and its slope reach zero at
	# radius two, so dropping the far tap cannot introduce a grid seam.
	var taps := Vector4.ZERO
	for i in range(4):
		var distance := (i - 1 - fraction) * 0.5
		var base := 1.0 - distance * distance
		taps[i] = base * base
	return taps


static func _coast_sample(point: Vector2) -> Vector2:
	var bend := Vector2(sin(point.y*7.1+sin(point.x*3.7)),cos(point.x*6.3+sin(point.y*4.1)))*0.035
	return point+bend-Vector2.ONE*0.5


static func _coast_coverage(sample: Vector2, provider: Callable) -> float:
	var origin := Vector2i(sample.floor())
	var linear := sample-Vector2(origin)
	var fraction := Vector2(smoothstep(0.30,0.70,linear.x),smoothstep(0.30,0.70,linear.y))
	var land := 0.0
	var water := 0.0
	var linear_land := 0.0
	var linear_total := 0.0
	for y in range(2):
		for x in range(2):
			var id := int(provider.call(origin+Vector2i(x,y)))
			if id<0: continue
			var weight := (fraction.x if x==1 else 1.0-fraction.x)*(fraction.y if y==1 else 1.0-fraction.y)
			var linear_weight := (linear.x if x==1 else 1.0-linear.x)*(linear.y if y==1 else 1.0-linear.y)
			linear_total += linear_weight
			if id in [1,4,15,22]: water += weight
			else:
				land += weight
				linear_land += linear_weight
	if land+water<0.000001: return 1.0
	return smoothstep(0.495,0.535,linear_land/maxf(linear_total,0.000001)) if land>0.0 and water>0.0 else (1.0 if land>0.0 else 0.0)


# Shore ribbons and material blending evaluate the same land/water contour.
static func surface_land_coverage(point: Vector2, provider: Callable, river: Dictionary = {}) -> float:
	var coverage := _coast_coverage(_coast_sample(point), provider)
	if not river.is_empty():
		var field := RiverSurface.sample(river,point)
		var wet := smoothstep(-0.08,0.10,field.x)*smoothstep(-0.035,0.10,field.z)
		coverage = lerpf(coverage,1.0-wet,field.y)
	return coverage


static func tile_drawable(cell: Vector2i, id: int, provider: Callable, catalog, elevation, zoom: float, offset: Vector2, seed: int) -> Dictionary:
	var pack = catalog.environment_pack
	var profile: Dictionary = elevation.cell_profile(cell)
	var center_id := _material_id(id, pack)
	var ids: Array = []
	var vertex_weights: Array = []
	var points := PackedVector2Array()
	var locals := PackedVector2Array()
	var lighting := PackedFloat32Array()
	var corners: Array = profile["corners"]
	var uniform := bool(profile["is_flat"])
	var coastal := false
	for dy in range(-MATERIAL_HALO, MATERIAL_HALO + 1):
		for dx in range(-MATERIAL_HALO, MATERIAL_HALO + 1):
			var neighbor := int(provider.call(cell + Vector2i(dx, dy)))
			if neighbor >= 0 and _material_id(neighbor, pack) != center_id:
				uniform = false
				if absi(dx) <= 1 and absi(dy) <= 1 and (neighbor in TerrainRules.WATER_TERRAIN_IDS) != (center_id in [1, 4, 15, 22]): coastal = true
	if not elevation.river_shape.is_empty():
		for y in range(3):
			for x in range(3):
				if RiverSurface.sample(elevation.river_shape, Vector2(cell) + Vector2(x, y) * 0.5).y > 0.0:
					uniform = false
					coastal = true
	var planar: bool = corners[0] + corners[2] == corners[1] + corners[3]
	var subdivisions := 1 if uniform else 16 if coastal else BLEND_SUBDIVISIONS if planar else SUBDIVISIONS
	for y in range(subdivisions + 1):
		for x in range(subdivisions + 1):
			var uv := Vector2(float(x), float(y)) / subdivisions
			var world := Vector2(cell) + uv
			var weight := {center_id: 1.0} if uniform else weights(world, provider, pack, center_id)
			if not elevation.river_shape.is_empty(): weight = RiverSurface.blend(weight, RiverSurface.sample(elevation.river_shape, world), elevation.bank_silt, elevation.ford_gravel)
			vertex_weights.append(weight)
			for material_id in weight:
				if float(weight[material_id]) > 0.00001 and material_id not in ids:
					ids.append(material_id)
			var height := lerpf(lerpf(corners[0], corners[1], uv.x), lerpf(corners[3], corners[2], uv.x), uv.y)
			points.append(Coordinates.world_to_screen(world, zoom, offset) + TerrainElevation.screen_offset(height, zoom))
			locals.append(uv)
			var dx := lerpf(corners[1] - corners[0], corners[2] - corners[3], uv.y)
			var dy := lerpf(corners[3] - corners[0], corners[2] - corners[1], uv.x)
			lighting.append(clampf(1.0 - dx * 0.11 - dy * 0.06, 0.8, 1.16))
	ids.sort_custom(func(a, b): return int(a) < int(b) if _priority(a, pack) == _priority(b, pack) else _priority(a, pack) < _priority(b, pack))
	var indices := PackedInt32Array()
	for y in range(subdivisions):
		for x in range(subdivisions):
			var p := y * (subdivisions + 1) + x
			indices.append_array(PackedInt32Array([p, p + 1, p + subdivisions + 2, p, p + subdivisions + 2, p + subdivisions + 1]))
	var layers: Array = []
	var accumulated := PackedFloat32Array()
	accumulated.resize(points.size())
	var phase := Vector2i(posmod(seed, 10), posmod(seed / 10, 10))
	for material_id in ids:
		var texture: Texture2D
		var imported: bool = pack.has_material(material_id)
		if imported:
			texture = pack.material_texture(material_id)
		else:
			texture = pack.legacy_textures[material_id]
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		for i in range(points.size()):
			var weight := float(vertex_weights[i].get(material_id, 0.0))
			accumulated[i] += weight
			var alpha := 1.0 if layers.is_empty() else (weight / accumulated[i] if accumulated[i] > 0.00001 else 0.0)
			colors.append(Color(lighting[i], lighting[i], lighting[i], alpha))
			var uv := locals[i]
			if imported:
				var pixel := (Vector2(posmod(cell.x + phase.x, 10), posmod(cell.y + phase.y, 10)) + uv) * 32.0
				uvs.append(pixel.clamp(Vector2(0.5, 0.5), Vector2(319.5, 319.5)) / 320.0)
			else:
				var frame := TerrainRules.tile_variant(cell, "terrain", seed, 9)
				var patch := Vector2(frame % 3, frame / 3) * 32.0
				uvs.append((patch + (uv * 32.0).clamp(Vector2(0.5, 0.5), Vector2(31.5, 31.5))) / 96.0)
		layers.append({"texture": texture, "points": points, "uvs": uvs, "colors": colors, "indices": indices})
	var flat_center := Coordinates.world_to_screen(Vector2(cell) + Vector2(0.5, 0.5), zoom, offset)
	return {"cell": cell, "terrain_id": id, "profile": profile, "mesh_layers": layers,
		"position": elevation.tile_screen_origin(flat_center, Vector2(65, 33), profile, zoom),
		"borders": []}


static func draw_layer(canvas: CanvasItem, layer: Dictionary) -> void:
	for triangle in range(0, layer["indices"].size(), 3):
		var points := PackedVector2Array()
		var uvs := PackedVector2Array()
		var colors := PackedColorArray()
		for corner in range(3):
			var index: int = layer["indices"][triangle + corner]
			points.append(layer["points"][index])
			uvs.append(layer["uvs"][index])
			colors.append(layer["colors"][index])
		canvas.draw_polygon(points, colors, uvs, layer["texture"])
