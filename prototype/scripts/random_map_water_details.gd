class_name RoRRandomMapWaterDetails
extends RefCounted

const Decorations := preload("res://scripts/random_map_decorations.gd")
const Hydrology := preload("res://scripts/random_map_hydrology.gd")
const Surface := preload("res://scripts/random_map_river_surface.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Topology := preload("res://scripts/random_map_topology.gd")
const Rules := preload("res://scripts/terrain_rules.gd")

var data: Dictionary
var ctx: Dictionary
var specs: Dictionary = {}
var ground: Dictionary = {}
var wet_ground: Dictionary = {}
var wet_plants: Dictionary = {}
var props: Dictionary = {}
var lakes: Dictionary = {}
var shore: Dictionary = {}
var seed := 0
var density := 1.0
var remaining := 0
var summary: Dictionary = {}
var islets: Dictionary = {}
var islet_budget := 0

# This pass only publishes scenery. Terrain, heights, resources, routes and
# navigation retain the geography already validated by the candidate pipeline.
static func decorate(map_data: Dictionary, fields: Dictionary, map_seed: int, density_scale: float, foundations: Dictionary = {}) -> void:
	if density_scale <= 0.0:
		map_data["water_detail_summary"] = {}
		map_data["decoration_summary"] = Decorations.summarize(map_data["scenery"])
		return
	var builder := RoRRandomMapWaterDetails.new()
	builder.data = map_data
	builder.seed = map_seed
	builder.density = clampf(density_scale, 0.0, 3.0)
	builder.remaining = ceili(map_data["size"].x * map_data["size"].y / 32.0 * builder.density)
	# These small overlapping source fragments form terrain-length bands.
	# Give them their own bounded budget without displacing bank vegetation.
	builder.islet_budget = ceili(map_data["size"].x * map_data["size"].y / 8.0 * builder.density)
	# Resource reserves blanket the whole river to exclude trees and mines.
	# Nonblocking reeds may use that water; actual resources, foundations and
	# existing prop footprints still supply the physical occupancy exclusions.
	builder.ctx = Decorations.context(map_data, fields, {}, foundations)
	for spec in Decorations.palette(): builder.specs[spec["key"]] = spec
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Decorations.DEFINITION_PATH))
	for spec in definition["objects"]:
		if spec["key"] == "ror_river_islets": builder.islets = spec
	for item in map_data["scenery"]:
		var spec: Dictionary = builder.specs.get(item.get("decoration_key", ""), {})
		if spec.is_empty(): continue
		Decorations._remember(item["position"], 0.95 if item.get("ford_detail", false) else float(spec["placement"]["spacing"]), builder._buckets(spec))
		if spec["role"] == "scenery":
			for cell in Decorations.footprint_cells(spec, int(item["source_frame"]), item["position"]): builder.ctx["occupied"][cell] = true
	for lake in map_data.get("lakes", []):
		for i in lake["cells"]: builder.lakes[int(i)] = true
	builder._reaches()
	builder._margins()
	for i in range(map_data["scenery"].size()): map_data["scenery"][i]["id"] = -800000 - i
	map_data["water_detail_summary"] = builder.summary
	map_data["decoration_summary"] = Decorations.summarize(map_data["scenery"])

func _reaches() -> void:
	var size: Vector2i = data["size"]
	var rivers: Dictionary = data.get("rivers", {})
	var shape: Dictionary = rivers.get("surface", {})
	if shape.get("model_version",0) >= 2:
		_shoal_bands(rivers,shape)
		for strip in rivers.get("shoals",[]):
			if not strip.get("stable_margin",false): continue
			var points: PackedVector2Array = strip["points"]
			for i in range(8,points.size()-8,9):
				var cell := Vector2i(points[i].floor())
				if not _chance(cell,0xBAA73,0.40): continue
				var tangent := (points[mini(points.size()-1,i+2)]-points[maxi(0,i-2)]).normalized()
				var point := points[i]-Vector2(-tangent.y,tangent.x)*int(strip["side"])*0.15
				if Surface.sediment(Surface.sample(shape,point)) < 0.25: continue
				_stamp("ror_reeds",point,[0,0,1],strip["origin"],2.0)
		return
	var seen: Dictionary = {}
	var threshold := float(rivers.get("runoff_threshold", 1.0))
	for channel in rivers.get("channels", []):
		var points: PackedVector2Array = channel["points"]
		for i in range(0, points.size(), 3):
			var point := points[i]
			var cell := Vector2i(point.floor())
			if not Navigation.inside(cell, size): continue
			var source: bool = channel["runoff"][i] < threshold * 2.0
			var bend := float(channel["bends"][i])
			var tangent := (points[mini(points.size() - 1, i + 3)] - points[maxi(0, i - 3)]).normalized()
			if not source:
				if absf(bend) < 0.12: continue
				# Point bars belong on the inside bank, leaving the thalweg open.
				point += Vector2(-tangent.y, tangent.x) * signf(bend) * float(channel["radii"][i]) * 0.58
				cell = Vector2i(point.floor())
			if not Navigation.inside(cell, size) or seen.has(cell): continue
			seen[cell] = true
			var field := Surface.sample(shape, point)
			if Surface.sediment(field) < 0.25 or not _chance(cell, 0xD3401, 0.85): continue
			var role := "source_silt" if source else "inner_bend"
			# Sandy islands communicate walkable shallows. Do not paint apparent
			# crossings over an ordinary deep, infantry-inaccessible channel.
			if int(data["terrain_ids"][cell.y * size.x + cell.x]) == 4:
				_stamp("ror_shallows", point, [0, 5, 1, 3, 4, 6], role, 1.05)
			_stamp("ror_reeds", point + Vector2(-tangent.y, tangent.x) * 0.2, [0, 1], role, 1.0)
		# The original waterfall has one fixed direction. Use it only where
		# actual published relief drops steeply in the matching world direction.
		for i in range(5, points.size() - 5, 5):
			var direction := (points[i + 5] - points[i - 5]).normalized()
			if direction.dot(Vector2.DOWN) < 0.90: continue
			var upper := _level(points[i - 4])
			var lower := _level(points[i + 4])
			if upper - lower < 2: continue
			var cell := Vector2i(points[i].floor())
			if not _chance(cell, 0xFA110, 0.7): continue
			if _stamp("ror_waterfall", points[i], [0], "waterfall", 10.0):
				data["scenery"][-1]["presentation_layer"] = "decal"
				data["scenery"][-1]["height_drop"] = upper - lower
				data["scenery"][-1]["flow_direction"] = direction

# Source islets overlap along the actual depositional ribbon, rather than
# scattering independent oval water decals. Their transparent backing allows
# the bankward edge to merge into dry silt without painting blue over the land.
func _shoal_bands(rivers: Dictionary, shape: Dictionary) -> void:
	# Crossings must remain legible even when a map exhausts its detail budget.
	_riffle_islets(shape)
	for strip in rivers.get("shoals",[]):
		var points: PackedVector2Array = strip["points"]
		var walked := 0.0
		var next := 0.0
		for i in range(1,points.size()-1):
			walked += points[i].distance_to(points[i-1])
			if walked < next: continue
			next = walked+0.28/maxf(0.4,sqrt(density))
			var width := float(strip["widths"][i])
			if width < 0.25: continue
			var tangent := (points[i+1]-points[i-1]).normalized()
			var outward := Vector2(-tangent.y,tangent.x)*int(strip["side"])
			var rows := 3 if width > 1.35 else 2 if width > 0.65 else 1
			for row in range(rows):
				var across := (float(row)-float(rows-1)*0.5)*0.36
				var point := points[i]+outward*(across+sin(walked*1.7)*0.12)
				point += tangent*(0.14 if row%2==1 else 0.0)
				_islet(point,shape,String(strip["origin"]))

func _riffle_islets(shape: Dictionary) -> void:
	for ford in data.get("fords",[]):
		var a: Vector2 = ford["bank_a"]
		var b: Vector2 = ford["bank_b"]
		var direction := (b-a).normalized()
		var normal := Vector2(-direction.y,direction.x)
		var steps := ceili(a.distance_to(b)/0.28)
		for i in range(steps+1):
			var point := a.lerp(b,float(i)/steps)
			# Offset strands leave native narrow water channels between the
			# sand tongues, rather than a solid dry bridge or a straight dot row.
			for side in [-1,0,1]:
				_islet(point+normal*(float(side)*0.36+sin(i*0.8)*0.16),shape,"riffle_islets")

func _islet(position: Vector2, shape: Dictionary, role: String) -> bool:
	if islet_budget <= 0 or islets.is_empty(): return false
	var size: Vector2i = data["size"]
	var cell := Vector2i(position.floor())
	if not Navigation.inside(cell,size) or not Decorations._room(position,0.19,wet_ground): return false
	var field := Surface.sample(shape,position)
	if field.y < 0.9 or field.z > 0.40 or field.x < -0.30: return false
	var index := cell.y*size.x+cell.x
	if data["terrain_ids"][index] in [1,22]: return false
	if data["rivers"]["mouth_mask"][index] != 0: return false
	var variants := [1,3,4,6,3,6,1,4,5,0]
	var variant: int = variants[mini(variants.size()-1,int(Topology.roll(Vector2i(position*8.0),seed^0xB4A51)*variants.size()))]
	var bounds: Array = islets["ground_bounds"][variant]
	var level := _level(position)
	var levels: Array = data["vertex_levels"]
	for y in range(3):
		for x in range(3):
			var point := position+Vector2(lerpf(bounds[0],bounds[2],x*0.5),lerpf(bounds[1],bounds[3],y*0.5))
			var at := Vector2i(point.floor())
			if not Navigation.inside(at,size): return false
			var vertex := at.y*(size.x+1)+at.x
			for offset in [0,1,size.x+1,size.x+2]:
				if levels[vertex+offset]!=level: return false
			if ctx["foundations"].has(at) or ctx["occupied"].has(at): return false
			var covered := at.y*size.x+at.x
			if data["terrain_ids"][covered] in [1,22] or data["rivers"]["mouth_mask"][covered]!=0: return false
	Decorations._remember(position,0.19,wet_ground)
	data["scenery"].append({"asset_name":"aoe2_temperate:ror_river_islets","position":position,
		"source_frame":variant,"presentation_layer":"decal","decoration_key":"ror_river_islets",
		"source_game":"ror","feature_family":"ror_river_islets","ecology_role":role,
		"water_detail":true,"ambient":true,"route_id":-1,
		"presentation_bounds":bounds})
	islet_budget -= 1
	summary[role] = int(summary.get(role,0))+1
	return true

func _margins() -> void:
	var size: Vector2i = data["size"]
	var terrain: Array = data["terrain_ids"]
	var distance: PackedInt32Array = ctx["water_distance"]
	var shape: Dictionary = data.get("rivers", {}).get("surface", {})
	for i in range(terrain.size()):
		if int(terrain[i]) not in [1, 4] or distance[i] > 2: continue
		var cell := Vector2i(i % size.x, i / size.x)
		var point := Vector2(cell) + Vector2.ONE * 0.5
		var marine := _marine(i)
		var field := Surface.sample(shape, point)
		var quiet: bool = marine or lakes.has(i) or terrain[i] == 4 or Surface.sediment(field) > 0.25
		if quiet and _chance(cell, 0xA1311, 0.22):
			_stamp("ror_reeds", point + _jitter(cell, 0xA1312), [0, 1], "coastal_margin" if marine else "lake_margin" if lakes.has(i) else "quiet_river_margin", 1.15)
		if shape.is_empty() and terrain[i] == 4 and _chance(cell, 0xA1313, 0.50):
			_stamp("ror_shallows", point, [0, 5, 1, 3, 6], "coastal_shoal" if marine else "lake_margin" if lakes.has(i) else "river_shoal", 1.15)
		if distance[i] != 1: continue
		# Only a narrow dry band is needed. This is bounded by shore length,
		# rather than a separate full-map distance field for each water body.
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var at := cell + Vector2i(dx, dy)
				if dx * dx + dy * dy > 5 or not Navigation.inside(at, size): continue
				var index := at.y * size.x + at.x
				if int(terrain[index]) in Rules.WATER_TERRAIN_IDS: continue
				var squared := dx * dx + dy * dy
				if shore.has(index) and int(shore[index]["distance"]) <= squared: continue
				shore[index] = {"distance": squared, "marine": marine, "lake": lakes.has(i), "wet": Surface.sediment(field) > 0.25}
	for index in shore:
		var info: Dictionary = shore[index]
		var cell := Vector2i(int(index) % size.x, int(index) / size.x)
		var point := Vector2(cell) + Vector2.ONE * 0.5 + _jitter(cell, 0xDA110)
		var role := "coastal_wrack" if info["marine"] else "lake_wrack" if info["lake"] else "river_wrack"
		if _chance(cell, 0xDA111, 0.24): _stamp("ror_shore_wrack", point, [0, 1], role, 2.4)
		if info["marine"]:
			if info["distance"] <= 1 and _chance(cell, 0xDA112, 0.40): _stamp("ror_beach_articles", point, [0, 1, 2, 3, 4], "marine_beach", 2.2)
		else:
			# Grass, damp stones and rare deadwood extend the composition onto
			# land. Native ground artwork is checked against its whole footprint.
			if _chance(cell, 0xDA113, 0.12): _stamp("ror_grass", point, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], "wet_bank_grass", 2.2)
			if (info["wet"] or info["lake"]) and _chance(cell, 0xDA114, 0.09): _stamp("ror_mud_rocks", point, [0, 1, 2], "wet_bank_stones", 3.5)
			if _chance(cell, 0xDA115, 0.025): _stamp("ror_deadwood", point, [0], "bank_deadwood", 4.0)

func _stamp(key: String, position: Vector2, variants: Array, role: String, spacing: float) -> bool:
	if remaining <= 0 or not specs.has(key): return false
	var spec: Dictionary = specs[key]
	var buckets := _buckets(spec)
	if not Decorations._room(position, spacing, buckets): return false
	var cell := Vector2i(position.floor())
	var first := mini(variants.size() - 1, int(Topology.roll(cell, seed ^ 0xA331) * variants.size()))
	for attempt in range(variants.size()):
		var variant := int(variants[(first + attempt) % variants.size()])
		if not Decorations.fits(spec, variant, position, ctx): continue
		if key == "ror_shallows" and not Hydrology._ford_detail_fits(data, spec, variant, position): continue
		if not _visible_footprint(spec, variant, position): continue
		Decorations._remember(position, spacing, buckets)
		data["scenery"].append({"id": -800000 - data["scenery"].size(), "asset_name": "aoe2_temperate:" + key,
			"position": position, "source_frame": variant, "presentation_layer": "decal" if spec["role"] == "decal" else "scenery",
			"water_detail": true, "shallow_detail": key == "ror_shallows", "decoration_key": key, "source_game": "ror",
			"feature_family": key, "ecology_role": role, "ambient": true, "route_id": -1, "presentation_bounds": spec["ground_bounds"][variant]})
		remaining -= 1
		summary[role] = int(summary.get(role, 0)) + 1
		if spec["role"] == "scenery":
			for covered in Decorations.footprint_cells(spec, variant, position): ctx["occupied"][covered] = true
		return true
	return false

func _buckets(spec: Dictionary) -> Dictionary:
	if spec["key"] == "ror_reeds": return wet_plants
	if spec["role"] != "decal": return props
	# A weed submerged below the bank must not consume the dry wrack line's
	# spacing budget. The full footprints still prevent spills across the shore.
	return wet_ground if spec["placement"]["materials"].has(1) else ground

func _visible_footprint(spec: Dictionary, variant: int, position: Vector2) -> bool:
	var shape: Dictionary = data.get("rivers", {}).get("surface", {})
	var wet: bool = spec["placement"]["materials"].has(1)
	var radius := float(spec.get("footprint_radius", 0.3))
	var bounds: Array = spec["ground_bounds"][variant] if spec["role"] == "decal" else [-radius, -radius, radius, radius]
	for y in range(3):
		for x in range(3):
			var point := position + Vector2(lerpf(bounds[0], bounds[2], x / 2.0), lerpf(bounds[1], bounds[3], y / 2.0))
			var field := Surface.sample(shape, point)
			if field.y < 0.05: continue
			if wet and field.x < 0.06: return false
			if not wet and field.x > -0.06: return false
	return true

func _marine(index: int) -> bool:
	if lakes.has(index): return false
	var mask: PackedByteArray = data.get("rivers", {}).get("mask", PackedByteArray())
	return mask.is_empty() or mask[index] == 0

func _level(point: Vector2) -> int:
	var size: Vector2i = data["size"]
	var cell := Vector2i(point.floor())
	if not Navigation.inside(cell, size): return 0
	var i := cell.y * (size.x + 1) + cell.x
	var levels: Array = data["vertex_levels"]
	return mini(mini(levels[i], levels[i + 1]), mini(levels[i + size.x + 1], levels[i + size.x + 2]))

func _chance(cell: Vector2i, salt: int, chance: float) -> bool:
	var patch := lerpf(0.5, 1.3, Topology.roll(Vector2i(cell.x / 4, cell.y / 4), seed ^ 0xA2C4))
	return Topology.roll(cell, seed ^ salt) < chance * density * patch

func _jitter(cell: Vector2i, salt: int) -> Vector2:
	return Vector2(Topology.roll(cell, seed ^ salt), Topology.roll(cell, seed ^ (salt + 1))) * 0.4 - Vector2.ONE * 0.2
