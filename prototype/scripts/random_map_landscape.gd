class_name RoRRandomMapLandscape
extends RefCounted

const CliffChain := preload("res://scripts/cliff_chain.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Decorations := preload("res://scripts/random_map_decorations.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const THEME_PATH := "res://data/random_maps/temperate_v2.json"
const VERSION := 2
const TYPE := "landscape_skirmish_v2"
const WATER := [1, 2, 4, 22]
# Green families and rare autumn/dry accents are selected separately.
static var _theme_cache: Dictionary = {}


static func theme() -> Dictionary:
	if _theme_cache.is_empty():
		_theme_cache = JSON.parse_string(FileAccess.get_file_as_string(THEME_PATH).trim_prefix("\ufeff"))
	return _theme_cache


static func candidate_count(size: Vector2i) -> int:
	return 1 if size.x * size.y >= 90000 else 2 if size.x * size.y >= 16000 else 3


static func select_fields(size: Vector2i, terrain: Array[int], starts: Array[Vector2], profile: String, seed: int) -> Dictionary:
	var recipe: Dictionary = theme()["profiles"].get(profile, theme()["profiles"]["grasslands"])
	var coast := coast_distances(size, terrain)
	var scores: Array = []
	var selected: Dictionary = {}
	var best := -INF
	var winner := 0
	for candidate in range(candidate_count(size)):
		var candidate_seed := seed ^ (0x2A63B91 + candidate * 104729)
		var fields := build_fields(size, terrain, starts, recipe, coast, candidate_seed)
		# Score forest opportunities around every base, not decorative coverage.
		var opportunities: Array[int] = []
		for start in starts:
			var count := 0
			for y in range(maxi(0, int(start.y) - 18), mini(size.y, int(start.y) + 19)):
				for x in range(maxi(0, int(start.x) - 18), mini(size.x, int(start.x) + 19)):
					var distance := start.distance_to(Vector2(x + 0.5, y + 0.5))
					if distance >= 9.0 and distance <= 18.0 and int(fields["forest_potential"][y * size.x + x]) != 0: count += 1
			opportunities.append(count)
		var minimum := int(opportunities.min()) if not opportunities.is_empty() else 0
		var maximum := int(opportunities.max()) if not opportunities.is_empty() else 0
		var score := float(minimum) - float(maximum - minimum) * 0.4
		scores.append({"index": candidate, "seed": candidate_seed, "score": score, "forest_opportunities": opportunities})
		if selected.is_empty() or score > best:
			best = score
			selected = fields
			winner = candidate
	selected["generation_candidates"] = {"scope": "relief_and_ecology", "candidate_count": scores.size(), "scores": scores,
		"selected_candidate_index": winner, "selected_candidate_seed": int(scores[winner]["seed"])}
	return selected


static func build_fields(size: Vector2i, terrain: Array[int], starts: Array[Vector2], recipe: Dictionary, coast: PackedInt32Array, seed: int) -> Dictionary:
	var scale := clampf(float(mini(size.x, size.y)) * 0.15, 9.0, 24.0)
	var macro := noise_field(size, scale * 1.8, seed)
	var detail := noise_field(size, scale * 0.62, seed ^ 0x732AF)
	var moisture := noise_field(size, scale * 1.25, seed ^ 0x793D15)
	var woodland := noise_field(size, scale * 0.85, seed ^ 0xBAC712)
	var geology := noise_field(size, scale * 0.66, seed ^ 0x72623)
	var potential := PackedByteArray()
	potential.resize(terrain.size())
	var cell_levels := PackedInt32Array()
	cell_levels.resize(terrain.size())
	for i in range(terrain.size()):
		if int(terrain[i]) in WATER: continue
		var point := Vector2(i % size.x + 0.5, i / size.x + 0.5)
		var start_distance := INF
		for start in starts: start_distance = minf(start_distance, point.distance_to(start))
		var ridge := clampf((macro[i] * 0.82 + detail[i] * 0.18 - 0.24) * 1.8, 0.0, 1.0)
		var height := mini(int(recipe["relief"]), floori(ridge * (float(recipe["relief"]) + 0.7)))
		# Distance to the actual shoreline replaces the old all-dry bounding-box test.
		height = mini(height, maxi(0, (coast[i] - 2) / 3))
		if not is_inf(start_distance): height = mini(height, maxi(0, floori((start_distance - 5.0) / 3.0)))
		cell_levels[i] = height
		moisture[i] = clampf(moisture[i] + float(recipe["moisture_bias"]) + maxf(0.0, 0.16 - float(coast[i]) * 0.012), 0.0, 1.0)
		var suitability := woodland[i] * 0.78 + moisture[i] * 0.22
		potential[i] = int(suitability > float(recipe["forest_threshold"]) and start_distance > 6.0 and coast[i] > 1)
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	for y in range(size.y + 1):
		for x in range(size.x + 1):
			var height := int(recipe["relief"])
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					var cell := Vector2i(clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1))
					height = mini(height, cell_levels[cell.y * size.x + cell.x])
			levels[y * (size.x + 1) + x] = height
	relax_heights(levels, size)
	return {"moisture": moisture, "woodland": woodland, "geology": geology, "coast_distance": coast,
		"forest_potential": potential, "vertex_levels": levels, "recipe": recipe}


static func rock_ridges(size: Vector2i, terrain: Array[int], starts: Array[Vector2], fields: Dictionary, existing_cells: Array, seed: int) -> Dictionary:
	var cells: Dictionary = {}
	for cell in existing_cells:
		var safe := true
		for start in starts:
			if start.distance_squared_to(Vector2(cell)) < 10.0 * 10.0: safe = false
		if safe: cells[cell] = true
	var scenery: Array = []
	var used: Dictionary = {}
	var levels: Array[int] = fields["vertex_levels"]
	# Native RoR cliff strips occupy three cells along their axis. Lay whole
	# connected strips, reserving their complete footprint before placing economy.
	# Determine direction from the original centreline, before expanding any
	# sprite footprint. Expanded 3x3 cells used to turn X ridges into Y sprites.
	for run in _source_ridge_runs(cells):
		var axis: Vector2i = run["axis"]
		for center in run["centers"]:
			var near_start := false
			for start in starts:
				if start.distance_squared_to(Vector2(center)) < 12.0 * 12.0: near_start = true
			if near_start or used.has(center): continue
			_append_cliff_strip(scenery, cells, used, center, axis, size, terrain, levels, seed)
	# Sparse, reproducible geological ridges on raised inland ground. A short
	# chain always has open ends; starting areas and shore approaches stay clear.
	var spacing := 24
	for y in range(12, size.y - 12, spacing):
		for x in range(12, size.x - 12, spacing):
			var anchor := Vector2i(x, y)
			if random_at(anchor, seed ^ 0xAF415) > 0.55: continue
			if int(levels[y * (size.x + 1) + x]) < 2 or int(fields["coast_distance"][y * size.x + x]) < 10: continue
			var axis := Vector2i.RIGHT if random_at(anchor, seed ^ 0xCD662) > 0.5 else Vector2i.DOWN
			var count := 3 + int(random_at(anchor, seed ^ 0xE139) * 3.0)
			var chain: Array[Vector2i] = [anchor]
			var bend := count >= 4 and random_at(anchor, seed ^ 0x7135B) > 0.5
			for step in range(1, count):
				# An optional stair turn uses both native corner pieces. Validate
				# the whole bent footprint before reserving any of its cells.
				var direction := (Vector2i.UP if axis == Vector2i.RIGHT else Vector2i.LEFT) if bend and step == 2 else axis
				chain.append(chain.back() + direction * CliffChain.STRIDE)
			var valid := true
			for center in chain:
				for start in starts:
					if start.distance_squared_to(Vector2(center)) < 26.0 * 26.0: valid = false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var cell := center + Vector2i(dx, dy)
						if cell.x < 2 or cell.y < 2 or cell.x >= size.x - 2 or cell.y >= size.y - 2:
							valid = false
						elif terrain[cell.y * size.x + cell.x] in WATER or cells.has(cell): valid = false
			if not valid: continue
			for center in chain:
				_append_cliff_strip(scenery, cells, used, center, axis, size, terrain, levels, seed)
	var variations: Dictionary = {}
	for item in scenery:
		var center := Vector2i(Vector2(item["position"]).floor())
		variations[center] = int(random_at(center, seed) * 10000.0)
	CliffChain.apply(scenery, variations)
	var ordered: Array[Vector2i] = []
	ordered.assign(cells.keys())
	ordered.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return {"cells": ordered, "scenery": scenery}


static func _append_cliff_strip(scenery: Array, cells: Dictionary, used: Dictionary, center: Vector2i, axis: Vector2i, size: Vector2i, terrain: Array[int], levels: Array[int], seed: int) -> void:
	var variants := [1, 2] if axis == Vector2i.RIGHT else [4, 5]
	var frame := int(variants[int(random_at(center, seed) * 10000.0) % variants.size()])
	var occupied: Array[Vector2i] = []
	scenery.append({"id": -700000 - scenery.size(), "kind": "cliff", "position": Vector2(center) + Vector2(0.5, 0.5),
		"source_unit_id": 264, "graphic_id": 107, "asset_name": "cliff_grounded", "source_frame": frame,
		"presentation_layer": "scenery", "presentation_bounds": [-2.0, -2.0, 2.0, 2.0], "cliff_axis": axis, "occupied_cells": occupied})
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := center + Vector2i(dx, dy)
			if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y: continue
			if terrain[cell.y * size.x + cell.x] in WATER: continue
			cells[cell] = true
			used[cell] = true
			occupied.append(cell)


static func paint_ground(map_data: Dictionary, fields: Dictionary) -> void:
	var terrain: Array[int] = map_data["terrain_ids"]
	for i in range(terrain.size()):
		if int(terrain[i]) in WATER: continue
		var moisture := float(fields["moisture"][i])
		var rock := float(fields["geology"][i])
		# Sparse exposed patches depend on soil and moisture, never elevation.
		if rock > maxf(0.86, float(fields["recipe"]["rock_threshold"])) and moisture < 0.38:
			terrain[i] = 1000
		elif moisture < 0.24 and rock > 0.72:
			terrain[i] = 1002
		elif moisture < 0.32 and rock > 0.78:
			terrain[i] = 1001
		else:
			terrain[i] = 0


static func forests(map_data: Dictionary, fields: Dictionary, exclusions: Dictionary, seed: int) -> void:
	var size: Vector2i = map_data["size"]
	var terrain: Array[int] = map_data["terrain_ids"]
	var levels: Array[int] = map_data["vertex_levels"]
	var resources: Array = map_data["resources"]
	var occupied := exclusions.duplicate()
	for resource in resources:
		occupied[Vector2i(resource["position"])] = true
		if String(resource.get("kind", "")) == "tree":
			bind_tree(resource, fields, size, seed)
	var forest_mask := PackedByteArray()
	forest_mask.resize(terrain.size())
	for i in range(terrain.size()):
		if fields["forest_potential"][i] == 0: continue
		var cell := Vector2i(i % size.x, i / size.x)
		if occupied.has(cell) or not flat_cell(cell, size, levels): continue
		var edge := false
		for next in Navigation.neighbors(i, size):
			if fields["forest_potential"][next] == 0: edge = true
		var density := 0.38 if edge else 0.80
		# Shared low-frequency holes create clearings, with a few loose edge trees.
		if float(fields["geology"][i]) < 0.20: continue
		if random_at(cell, seed ^ 0x737AE) > density: continue
		var resource := {"category": "resource", "kind": "tree", "amount": 75, "position": Vector2(cell) + Vector2(0.5, 0.5),
			"placement_domain": "land", "source_unit_id": 134, "source_graphic_id": 601, "source_graphic_asset_name": "graphic_601",
			"ecology_role": "forest_edge" if edge else "forest_core", "strategic_zone": _zone(map_data, i)}
		bind_tree(resource, fields, size, seed)
		resources.append(resource)
		occupied[cell] = true
	forest_accents(map_data, fields, occupied, seed)
	for resource in resources:
		if String(resource.get("kind", "")) != "tree": continue
		var cell := Vector2i(resource["position"])
		forest_mask[cell.y * size.x + cell.x] = 1
	# Paint the forest that actually exists, not a disconnected source terrain mask.
	for i in range(forest_mask.size()):
		if forest_mask[i] == 0: continue
		var cell := Vector2i(i % size.x, i / size.x)
		for y in range(maxi(0, cell.y - 1), mini(size.y, cell.y + 2)):
			for x in range(maxi(0, cell.x - 1), mini(size.x, cell.x + 2)):
				var index := y * size.x + x
				if int(terrain[index]) in WATER: continue
				var light_woodland := float(fields["woodland"][index]) * 0.7 + float(fields["moisture"][index]) * 0.3 < 0.63
				# Ground follows canopy density, independently of the game a tree came from.
				terrain[index] = (10 if light_woodland else 1003) if forest_mask[index] != 0 else (0 if light_woodland else 1001)
	map_data["forest_mask"] = forest_mask


static func bind_tree(resource: Dictionary, fields: Dictionary, size: Vector2i, seed: int) -> void:
	var cell := Vector2i(resource["position"])
	var index := cell.y * size.x + cell.x
	var pine := float(fields["moisture"][index]) < 0.47
	var palette: Dictionary = theme()["tree_palettes"]
	var palm: Dictionary = palette["palm"]
	var coast_distances: Variant = fields.get("coast_distance", [])
	var coastal_palm: bool = coast_distances.size() > index and int(coast_distances[index]) <= int(palm["coast_distance_max"]) and float(fields["moisture"][index]) <= float(palm["moisture_max"])
	var family: Dictionary = palm if coastal_palm else palette["conifer" if pine else "broadleaf"]
	var variants: Array = family["native"]
	var native: Dictionary = variants[int(random_at(cell, seed ^ 0x73814) * 10000.0) % variants.size()]
	# Both sources share native gameplay; art is selected once and survives saves.
	_bind_native_tree(resource, native)
	var native_share := lerpf(float(palette["native_share_min"]), float(palette["native_share_max"]), float(fields["geology"][index]))
	resource.erase("environment_asset")
	resource.erase("environment_variant")
	resource.erase("tree_condition")
	if family.has("imported") and random_at(cell, seed ^ 0x421CDF) >= native_share:
		resource["environment_asset"] = family["imported"]
		resource["environment_variant"] = int(random_at(cell, seed ^ 0x71873) * 10000.0) % int(family["imported_variants"])
	resource["visible_when_depleted"] = true
	resource["position"] = Vector2(cell) + Vector2(0.5, 0.5) + Vector2(random_at(cell, seed ^ 0xAF52) - 0.5, random_at(cell, seed ^ 0x7541) - 0.5) * 0.36


static func is_palm(resource: Dictionary) -> bool:
	var graphic_id := int(resource.get("source_graphic_id", -1))
	for native in theme()["tree_palettes"]["palm"]["native"]:
		if graphic_id == int(native["graphic_id"]): return true
	return false


static func _bind_native_tree(resource: Dictionary, native: Dictionary) -> void:
	resource["source_unit_id"] = int(native["unit_id"])
	resource["source_graphic_id"] = int(native["graphic_id"])
	resource["source_graphic_asset_name"] = "graphic_%d" % int(native["graphic_id"])
	resource["source_frame"] = 0 # Native multi-frame trees include felled states.
	resource["source_depleted_graphic_id"] = 600
	resource["source_depleted_asset_name"] = "tree_stump"


static func forest_accents(map_data: Dictionary, fields: Dictionary, occupied: Dictionary, seed: int) -> void:
	var size: Vector2i = map_data["size"]
	var resources: Array = map_data["resources"]
	var accents: Dictionary = theme()["tree_palettes"]["accents"]
	var spacing := int(accents["minimum_spacing"])
	var accent_cells: Dictionary = {}
	# Sparse exceptions within green broadleaf woods, never whole yellow groves.
	for resource in resources:
		if resource.get("kind", "") != "tree": continue
		var cell := Vector2i(resource["position"])
		var i := cell.y * size.x + cell.x
		if float(fields["moisture"][i]) < 0.47 or is_palm(resource): continue
		if random_at(cell, seed ^ 0x251AD) >= float(accents["forest_chance"]) or not _clear_neighborhood(cell, accent_cells, spacing): continue
		_bind_accent(resource, accents, seed)
		accent_cells[cell] = true
	# A few isolated specimens occupy open, flat ground away from all reserved routes.
	var candidates: Array = []
	var terrain: Array[int] = map_data["terrain_ids"]
	for by in range(5, size.y - 5, 12):
		for bx in range(5, size.x - 5, 12):
			var anchor := Vector2i(bx, by)
			var cell := anchor + Vector2i(int(random_at(anchor, seed ^ 0x523E) * 7.0) - 3, int(random_at(anchor, seed ^ 0x635F) * 7.0) - 3)
			var i := cell.y * size.x + cell.x
			if terrain[i] in WATER or fields["forest_potential"][i] != 0 or _zone(map_data, i) in ["sanctuary", "blocked"]: continue
			if fields["coast_distance"][i] <= 2 or not flat_cell(cell, size, map_data["vertex_levels"]): continue
			if _clear_neighborhood(cell, occupied, 2): candidates.append(cell)
	candidates.sort_custom(func(a, b): return random_at(a, seed ^ 0x123A) < random_at(b, seed ^ 0x123A))
	var dry_land := terrain.size()
	for water_id in WATER: dry_land -= terrain.count(water_id)
	var budget := maxi(1, dry_land / int(accents["solitary_area_per_tree"]))
	for cell in candidates:
		if budget <= 0: break
		if not _clear_neighborhood(cell, accent_cells, spacing): continue
		var resource := {"category": "resource", "kind": "tree", "amount": 75, "position": Vector2(cell) + Vector2(0.5, 0.5),
			"placement_domain": "land", "ecology_role": "solitary_tree", "strategic_zone": _zone(map_data, cell.y * size.x + cell.x)}
		bind_tree(resource, fields, size, seed)
		_bind_accent(resource, accents, seed)
		resources.append(resource)
		occupied[cell] = true
		accent_cells[cell] = true
		budget -= 1


static func _bind_accent(resource: Dictionary, accents: Dictionary, seed: int) -> void:
	var cell := Vector2i(resource["position"])
	var variants: Array = accents["variants"]
	var variant: Dictionary = variants[int(random_at(cell, seed ^ 0x82E1) * 10000.0) % variants.size()]
	resource.erase("environment_asset")
	resource.erase("environment_variant")
	_bind_native_tree(resource, variant)
	resource["tree_condition"] = variant["condition"]


static func _clear_neighborhood(cell: Vector2i, occupied: Dictionary, radius: int) -> bool:
	for y in range(cell.y - radius, cell.y + radius + 1):
		for x in range(cell.x - radius, cell.x + radius + 1):
			if occupied.has(Vector2i(x, y)): return false
	return true


static func scenery(map_data: Dictionary, fields: Dictionary, reserved: Dictionary, seed: int, density_scale: float = 1.0, foundations: Dictionary = {}) -> Array:
	return Decorations.generate(map_data, fields, reserved, seed, density_scale, foundations)


static func flat_cell(cell: Vector2i, size: Vector2i, levels: Array) -> bool:
	var index := cell.y * (size.x + 1) + cell.x
	return levels[index] == levels[index + 1] and levels[index] == levels[index + size.x + 1] and levels[index] == levels[index + size.x + 2]


static func relax_heights(levels: Array[int], size: Vector2i, flat_cells: Dictionary = {}) -> void:
	# A cell's four corners may differ by at most one level, including diagonals.
	var width := size.x + 1
	var flat_links: Dictionary = {}
	for cell in flat_cells:
		var i := int(cell.y) * width + int(cell.x)
		var corners := PackedInt32Array([i, i + 1, i + width, i + width + 1])
		for corner in corners:
			if not flat_links.has(corner): flat_links[corner] = PackedInt32Array()
			flat_links[corner].append_array(corners)
	var queue := PackedInt32Array()
	for i in range(levels.size()): queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		var x := index % width
		var y := index / width
		for next in flat_links.get(index, PackedInt32Array()):
			if levels[next] > levels[index]:
				levels[next] = levels[index]
				queue.append(next)
		for dy in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if x + dx < 0 or y + dy < 0 or x + dx > size.x or y + dy > size.y: continue
				var next: int = (y + dy) * width + x + dx
				if levels[next] > levels[index] + 1:
					levels[next] = levels[index] + 1
					queue.append(next)


static func coast_distances(size: Vector2i, terrain: Array[int]) -> PackedInt32Array:
	var distances := PackedInt32Array()
	distances.resize(terrain.size())
	distances.fill(size.x + size.y)
	var queue := PackedInt32Array()
	for i in range(terrain.size()):
		if int(terrain[i]) in WATER:
			distances[i] = 0
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var index := queue[cursor]
		cursor += 1
		for next in Navigation.neighbors(index, size):
			if distances[next] > distances[index] + 1:
				distances[next] = distances[index] + 1
				queue.append(next)
	return distances


static func noise_field(size: Vector2i, period: float, seed: int) -> PackedFloat32Array:
	var grid_width := ceili(float(size.x) / period) + 2
	var grid_height := ceili(float(size.y) / period) + 2
	var grid := PackedFloat32Array()
	grid.resize(grid_width * grid_height)
	for y in range(grid_height):
		for x in range(grid_width): grid[y * grid_width + x] = random_at(Vector2i(x, y), seed)
	var result := PackedFloat32Array()
	result.resize(size.x * size.y)
	for y in range(size.y):
		var gy := floori(float(y) / period)
		var ty := fposmod(float(y), period) / period
		ty = ty * ty * (3.0 - 2.0 * ty)
		for x in range(size.x):
			var gx := floori(float(x) / period)
			var tx := fposmod(float(x), period) / period
			tx = tx * tx * (3.0 - 2.0 * tx)
			result[y * size.x + x] = lerpf(lerpf(grid[gy * grid_width + gx], grid[gy * grid_width + gx + 1], tx), lerpf(grid[(gy + 1) * grid_width + gx], grid[(gy + 1) * grid_width + gx + 1], tx), ty)
	return result


static func random_at(cell: Vector2i, seed: int) -> float:
	var value := (cell.x * 374761393 + cell.y * 668265263 + seed * 69069) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return float(value ^ (value >> 16)) / 2147483647.0


static func fingerprint(map_data: Dictionary) -> String:
	var stable: Array = [VERSION, map_data.get("size"), map_data.get("seed"), map_data.get("terrain_ids"), map_data.get("vertex_levels"),
		map_data.get("cliff_cells", []), map_data.get("cliff_obstructions", []), map_data.get("resources", []), map_data.get("scenery", []), map_data.get("naval_start_zones", [])]
	return JSON.stringify(Replay.new().encode_variant(stable)).sha256_text()


static func _zone(map_data: Dictionary, index: int) -> String:
	var names := ["blocked", "sanctuary", "territory", "contested", "frontier"]
	return names[int(map_data["strategic_zones"]["zone_ids"][index])]


static func paint_resource_grounds(map_data: Dictionary) -> void:
	var size: Vector2i = map_data["size"]
	var terrain: Array[int] = map_data["terrain_ids"]
	var forest: PackedByteArray = map_data["forest_mask"]
	for resource in map_data["resources"]:
		if resource.get("kind", "") not in ["stone_mine", "gold_mine"]: continue
		var cell := Vector2i(resource["position"])
		for y in range(maxi(0, cell.y - 1), mini(size.y, cell.y + 2)):
			for x in range(maxi(0, cell.x - 1), mini(size.x, cell.x + 2)):
				var i := y * size.x + x
				if terrain[i] in WATER or forest[i] != 0: continue
				terrain[i] = 1000 if Vector2i(x, y) == cell else 1001


static func _source_ridge_runs(source_cells: Dictionary) -> Array:
	var pending := source_cells.duplicate()
	var result: Array = []
	var origins: Array = source_cells.keys()
	origins.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	for origin in origins:
		if not pending.has(origin): continue
		var group: Array[Vector2i] = [origin]
		pending.erase(origin)
		var cursor := 0
		while cursor < group.size():
			var cell := group[cursor]
			cursor += 1
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var next := cell + Vector2i(dx, dy)
					if pending.has(next):
						pending.erase(next)
						group.append(next)
		var xs: Array[int] = []
		var ys: Array[int] = []
		for cell in group:
			xs.append(cell.x)
			ys.append(cell.y)
		xs.sort()
		ys.sort()
		var along_x: bool = xs.back() - xs.front() >= ys.back() - ys.front()
		var axis := Vector2i.RIGHT if along_x else Vector2i.DOWN
		var along: Array[int] = xs if along_x else ys
		var across: Array[int] = ys if along_x else xs
		var normal: int = across[across.size() / 2]
		var first: int = along.front() + posmod(1 - along.front(), 3)
		var centers: Array[Vector2i] = []
		for value in range(first, along.back() + 1, 3):
			centers.append(Vector2i(value, normal) if along_x else Vector2i(normal, value))
		if not centers.is_empty(): result.append({"axis": axis, "centers": centers})
	return result


static func paint_cliff_grounds(map_data: Dictionary) -> void:
	var size: Vector2i = map_data["size"]
	var terrain: Array[int] = map_data["terrain_ids"]
	var occupied: Dictionary = {}
	for cell in map_data.get("cliff_cells", []): occupied[cell] = true
	for cell in occupied:
		if terrain[cell.y * size.x + cell.x] in WATER: continue
		var interior := true
		for neighbor in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if not occupied.has(cell + neighbor): interior = false
		# Local scree beneath the native footprint, blended by terrain borders.
		terrain[cell.y * size.x + cell.x] = 1000 if interior else 1001
