class_name RoRRandomMapDecorations
extends RefCounted

const DEFINITION_PATH := "res://data/environment/aoe2_temperate.json"
const Water := preload("res://scripts/random_map_water.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const BUCKET_SIZE := 5.0
static var _palette: Array = []

static func palette() -> Array:
	if _palette.is_empty():
		var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEFINITION_PATH))
		for spec in definition["objects"]:
			if spec.has("placement"):
				# JSON numbers are floats; Array.has uses typed equality in Godot.
				var materials: Array[int] = []
				for terrain_id in spec["placement"]["materials"]: materials.append(int(terrain_id))
				spec["placement"]["materials"] = materials
				_palette.append(spec)
	return _palette

static func context(data: Dictionary, fields: Dictionary, reserved: Dictionary, foundations: Dictionary = {}) -> Dictionary:
	var size: Vector2i = data["size"]
	var forest := PackedByteArray()
	forest.resize(size.x * size.y)
	var occupied := reserved.duplicate()
	var excluded := foundations.duplicate()
	for cell in data.get("reserved_foundation_cells", []): excluded[Vector2i(cell)] = true
	for cell in data.get("cliff_cells", []): excluded[Vector2i(cell)] = true
	for resource in data["resources"]:
		var cell := Vector2i(resource["position"])
		occupied[cell] = true
		if resource.get("kind", "") == "tree": forest[cell.y * size.x + cell.x] = 1
	var routes: Dictionary = {}
	var route_ids: Dictionary = {}
	var paved: Dictionary = {}
	var directions: Dictionary = {}
	var route_index := 0
	for edge in data.get("region_graph", {}).get("edges", []):
		var path: PackedInt32Array = edge.get("path", PackedInt32Array())
		for point_index in range(path.size()):
			var at := int(path[point_index])
			var cell := Vector2i(at % size.x, at / size.x)
			var previous := int(path[maxi(0, point_index - 1)])
			var next := int(path[mini(path.size() - 1, point_index + 1)])
			directions[cell] = Vector2(next % size.x - previous % size.x, next / size.x - previous / size.x).normalized()
			routes[cell] = true
			route_ids[cell] = route_index
			# Paving belongs to inhabited ends, while wilderness links remain trails.
			if point_index >= path.size() - 10 or (int(edge.get("to_team", 0)) > 0 and point_index < 10): paved[cell] = true
		route_index += 1
	var route_band: Dictionary = {}
	for cell in routes:
		for dy in range(-1, 2):
			for dx in range(-1, 2): route_band[cell + Vector2i(dx, dy)] = true
	return {"size": size, "terrain": data["terrain_ids"], "levels": data["vertex_levels"], "fields": fields,
		"forest_distance": _distance(size, forest), "water_distance": Water.water_distance_from_land(data["terrain_ids"], size),
		"occupied": occupied, "foundations": excluded, "routes": routes, "route_band": route_band, "route_ids": route_ids, "paved": paved, "route_directions": directions}

static func _distance(size: Vector2i, mask: PackedByteArray) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(mask.size())
	distances.fill(999)
	var queue := PackedInt32Array()
	for i in range(mask.size()):
		if mask[i] != 0:
			distances[i] = 0
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for next in Navigation.neighbors(i, size):
			if distances[next] > distances[i] + 1:
				distances[next] = distances[i] + 1
				queue.append(next)
	return distances

static func habitat_matches(spec: Dictionary, cell: Vector2i, ctx: Dictionary) -> bool:
	var size: Vector2i = ctx["size"]
	if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y: return false
	var i := cell.y * size.x + cell.x
	var rule: Dictionary = spec["placement"]
	if int(ctx["terrain"][i]) not in rule["materials"]: return false
	var moisture := float(ctx["fields"]["moisture"][i])
	var limits: Array = rule["moisture"]
	if moisture < float(limits[0]) or moisture > float(limits[1]): return false
	if float(ctx["fields"]["geology"][i]) < float(rule.get("geology_min", 0.0)): return false
	if int(ctx["fields"]["coast_distance"][i]) > int(rule.get("coast_max", 9999)): return false
	for key in ["forest_distance", "water_distance"]:
		if not rule.has(key): continue
		var distance := int(ctx[key][i])
		if distance < int(rule[key][0]) or distance > int(rule[key][1]): return false
	if rule.get("mode", "natural") == "route":
		if not ctx["routes"].has(cell): return false
		if bool(rule.get("paved", false)) != ctx["paved"].has(cell): return false
	return true

static func footprint_cells(spec: Dictionary, variant: int, position: Vector2) -> Array[Vector2i]:
	var bounds: Array = spec["ground_bounds"][variant]
	# Upright rocks and wood use their base; projecting their height onto the
	# ground would incorrectly exclude the bank behind a coastal rock.
	if spec.get("role", "") == "scenery":
		var radius := 0.499 if spec["key"] in ["boulders", "ror_rocks", "coastal_rocks", "ror_sea_rocks"] else 0.35
		bounds = [-radius, -radius, radius, radius]
	var result: Array[Vector2i] = []
	if spec.has("ground_masks"):
		var covered: Dictionary = {}
		for sample in spec["ground_masks"][variant]:
			var start := position + Vector2(float(sample[0]), float(sample[1])) * 0.5
			for y in range(floori(start.y), floori(start.y + 0.4999) + 1):
				for x in range(floori(start.x), floori(start.x + 0.4999) + 1): covered[Vector2i(x, y)] = true
		for cell in covered: result.append(cell)
		return result
	for y in range(floori(position.y + float(bounds[1])), floori(position.y + float(bounds[3])) + 1):
		for x in range(floori(position.x + float(bounds[0])), floori(position.x + float(bounds[2])) + 1): result.append(Vector2i(x, y))
	return result

static func fits(spec: Dictionary, variant: int, position: Vector2, ctx: Dictionary) -> bool:
	var cell := Vector2i(position.floor())
	if not habitat_matches(spec, cell, ctx): return false
	var size: Vector2i = ctx["size"]
	var levels: Array = ctx["levels"]
	var reference := int(levels[cell.y * (size.x + 1) + cell.x])
	var is_decal: bool = spec["role"] == "decal"
	var route: bool = spec["placement"].get("mode", "natural") == "route"
	if route and spec.has("route_axes"):
		var axis := Vector2(spec["route_axes"][variant][0], spec["route_axes"][variant][1])
		var direction: Vector2 = ctx["route_directions"].get(cell, Vector2.ZERO)
		if axis.length_squared() > 0.1 and absf(axis.dot(direction)) < 0.70: return false
	for covered in footprint_cells(spec, variant, position):
		if covered.x < 0 or covered.y < 0 or covered.x >= size.x or covered.y >= size.y: return false
		var i := covered.y * size.x + covered.x
		if int(ctx["terrain"][i]) not in spec["placement"]["materials"]: return false
		if ctx["foundations"].has(covered): return false
		if not is_decal and ctx["occupied"].has(covered): return false
		if route and not ctx["route_band"].has(covered): return false
		# Check the entire stamp, not only its anchor: no land/water spills or
		# floating flat artwork across a terrace edge.
		var vertex := covered.y * (size.x + 1) + covered.x
		for offset in [0, 1, size.x + 1, size.x + 2]:
			if absi(int(levels[vertex + offset]) - reference) > int(spec["placement"].get("max_slope", 0)): return false
	return true

static func _room(position: Vector2, spacing: float, buckets: Dictionary) -> bool:
	var at := Vector2i((position / BUCKET_SIZE).floor())
	for y in range(at.y - 2, at.y + 3):
		for x in range(at.x - 2, at.x + 3):
			for other in buckets.get(Vector2i(x, y), []):
				if position.distance_squared_to(other[0]) < pow((spacing + float(other[1])) * 0.5, 2.0): return false
	return true

static func _remember(position: Vector2, spacing: float, buckets: Dictionary) -> void:
	var at := Vector2i((position / BUCKET_SIZE).floor())
	if not buckets.has(at): buckets[at] = []
	buckets[at].append([position, spacing])

static func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var value: Variant = values[i]
		values[i] = values[j]
		values[j] = value

static func generate(data: Dictionary, fields: Dictionary, reserved: Dictionary, seed: int, density: float = 1.0, foundations: Dictionary = {}) -> Array:
	var result: Array = []
	if density <= 0.0: return result
	var ctx := context(data, fields, reserved, foundations)
	var size: Vector2i = data["size"]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var order: Array = []
	for i in range(size.x * size.y): order.append(i)
	_shuffle(order, rng)
	var ground: Dictionary = {}
	var props: Dictionary = {}
	var cursors: Dictionary = {}
	var by_pass: Array = [{}, {}, {}]
	var by_key: Dictionary = {}
	var family_counts: Dictionary = {}
	var land_cells := 0
	for id in data["terrain_ids"]:
		if id not in [1, 4, 22]: land_cells += 1
	for spec in palette():
		by_key[spec["key"]] = spec
		var rule: Dictionary = spec["placement"]
		var pass_id := 0 if rule.get("mode", "natural") == "route" else 1 if rule.get("large", false) else 2
		for material in rule["materials"]:
			if not by_pass[pass_id].has(material): by_pass[pass_id][material] = []
			by_pass[pass_id][material].append(spec)
	for spec in palette(): cursors[spec["key"]] = rng.randi_range(0, spec["frames"].size() - 1)
	# Trails first, then broad vegetation, then small details. Spatial buckets
	# enforce minimum spacing without a visible lattice or quadratic searches.
	for pass_index in range(3):
		if pass_index == 1:
			result = connected_routes(result)
			ground.clear()
			for item in result: _remember(item["position"], float(by_key[item["decoration_key"]]["placement"]["spacing"]), ground)
		for i in order:
			var cell := Vector2i(i % size.x, i / size.x)
			if pass_index == 0 and not ctx["routes"].has(cell): continue
			var patch := float(fields.get("woodland", fields["moisture"])[i])
			var chance := (1.0 if pass_index == 0 else 0.09 if pass_index == 1 else 0.27) * clampf(density, 0.0, 3.0)
			if pass_index != 0: chance *= lerpf(0.45, 1.5, smoothstep(0.25, 0.70, patch))
			if rng.randf() > chance: continue
			var candidates: Array = []
			var total := 0.0
			for spec in by_pass[pass_index].get(int(ctx["terrain"][i]), []):
				var rule: Dictionary = spec["placement"]
				if not habitat_matches(spec, cell, ctx): continue
				candidates.append(spec)
				total += float(rule["weight"])
			if candidates.is_empty(): continue
			var roll := rng.randf() * total
			var selected: Dictionary = candidates.back()
			for spec in candidates:
				roll -= float(spec["placement"]["weight"])
				if roll <= 0.0:
					selected = spec
					break
			var selected_rule: Dictionary = selected["placement"]
			if rng.randf() > float(selected_rule.get("occurrence", 1.0)): continue
			var family := String(selected_rule.get("budget_family", selected["key"]))
			var budget := maxi(1, land_cells / int(selected_rule.get("area_per_item", 1)))
			if int(family_counts.get(family, 0)) >= budget: continue
			var position := Vector2(cell) + Vector2(0.5, 0.5)
			if pass_index != 0: position += Vector2(rng.randf_range(-0.32, 0.32), rng.randf_range(-0.32, 0.32))
			var spacing := float(selected["placement"]["spacing"])
			var buckets: Dictionary = ground if selected["role"] == "decal" else props
			if not _room(position, spacing, buckets): continue
			var chosen := -1
			for attempt in range(selected["frames"].size()):
				var variant: int = (int(cursors[selected["key"]]) + attempt) % selected["frames"].size()
				if fits(selected, variant, position, ctx):
					chosen = variant
					break
			if chosen < 0: continue
			cursors[selected["key"]] = (chosen + 1) % selected["frames"].size()
			_remember(position, spacing, buckets)
			family_counts[family] = int(family_counts.get(family, 0)) + 1
			var key: String = selected["key"]
			var source: String = selected.get("source_game", "aoe2")
			result.append({"id": -800000 - result.size(), "position": position, "asset_name": "aoe2_temperate:" + key,
				"source_frame": chosen, "ambient": true, "presentation_bounds": selected["ground_bounds"][chosen].duplicate(), "presentation_layer": "decal" if selected["role"] == "decal" else "scenery",
				"decoration_key": key, "source_game": source, "feature_family": key, "ecology_role": "route_detail" if pass_index == 0 else "habitat_detail",
				"route_id": ctx["route_ids"].get(cell, -1) if pass_index == 0 else -1})
	for i in range(result.size()): result[i]["id"] = -800000 - i
	data["decoration_summary"] = summarize(result)
	return result

static func summarize(items: Array) -> Dictionary:
	var result := {"total": items.size(), "decals": 0, "sources": {"ror": 0, "aoe2": 0}, "families": {}, "variants": {}}
	for item in items:
		var key: String = item["decoration_key"]
		result["decals"] += int(item["presentation_layer"] == "decal")
		result["sources"][item["source_game"]] += 1
		result["families"][key] = int(result["families"].get(key, 0)) + 1
		if not result["variants"].has(key): result["variants"][key] = []
		if not result["variants"][key].has(item["source_frame"]): result["variants"][key].append(item["source_frame"])
	return result


static func connected_routes(items: Array) -> Array:
	# Single paving slabs in a meadow read as random debris. Keep only runs of
	# three or more stamps; a worn trail may have a one-cell gap.
	var cells: Dictionary = {}
	for i in range(items.size()): cells[Vector2i(items[i]["position"])] = i
	var seen: Dictionary = {}
	var keep: Dictionary = {}
	for origin in range(items.size()):
		if seen.has(origin): continue
		var queue: Array[int] = [origin]
		seen[origin] = true
		var cursor := 0
		while cursor < queue.size():
			var current := queue[cursor]
			cursor += 1
			var at: Vector2 = items[current]["position"]
			var cell := Vector2i(at)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var next := int(cells.get(cell + Vector2i(dx, dy), -1))
					if next < 0 or seen.has(next): continue
					if at.distance_squared_to(items[next]["position"]) > 4.01: continue
					seen[next] = true
					queue.append(next)
		if queue.size() >= 3:
			for index in queue: keep[index] = true
	var result: Array = []
	for i in range(items.size()):
		if keep.has(i): result.append(items[i])
	return result
