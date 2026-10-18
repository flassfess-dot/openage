class_name RoRRandomMapNaturalLandscape
extends RefCounted

const Base := preload("res://scripts/random_map_landscape.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const THEME_PATH := "res://data/random_maps/temperate_v3.json"
const VERSION := 3
static var _theme: Dictionary = {}

static func theme() -> Dictionary:
	if _theme.is_empty(): _theme = JSON.parse_string(FileAccess.get_file_as_string(THEME_PATH))
	return _theme

static func fields(size: Vector2i, terrain: Array[int], starts: Array[Vector2], profile: String, seed: int) -> Dictionary:
	var recipe: Dictionary = theme()["profiles"].get(profile, theme()["profiles"]["grasslands"])
	var span := float(mini(size.x, size.y))
	var macro := noise_field(size, span * 0.46, seed)
	var regional := noise_field(size, clampf(span * 0.18, 9.0, 42.0), seed ^ 0x732AF)
	var detail := noise_field(size, 8.0, seed ^ 0x73917)
	var moisture := noise_field(size, maxf(12.0, span * 0.27), seed ^ 0x793D15)
	var woodland := noise_field(size, clampf(span * 0.20, 10.0, 38.0), seed ^ 0xBAC712)
	var geology := noise_field(size, clampf(span * 0.15, 9.0, 30.0), seed ^ 0x72623)
	var coast := Base.coast_distances(size, terrain)
	var potential := PackedByteArray()
	var strength := PackedFloat32Array()
	var heights := PackedFloat32Array()
	potential.resize(terrain.size())
	strength.resize(terrain.size())
	heights.resize(terrain.size())
	for i in range(terrain.size()):
		if int(terrain[i]) in Base.WATER: continue
		var uplift := smoothstep(0.30, 0.79, macro[i] * 0.60 + regional[i] * 0.32 + detail[i] * 0.08)
		heights[i] = minf(uplift * float(recipe["relief"]), float(maxi(0, coast[i] - 1)))
		# Wet regions follow broad drainage depressions, with their own weather
		# variation. Tree species still depend on habitat rather than height.
		moisture[i] = clampf(moisture[i] + float(recipe["moisture_bias"]) + (0.5 - macro[i]) * 0.18 + maxf(0.0, 0.12 - coast[i] * 0.012), 0.0, 1.0)
		strength[i] = woodland[i] * 0.62 + moisture[i] * 0.28 + regional[i] * 0.10
	# Towns occupy a small terrace at the local elevation. Forcing all towns
	# down to sea level erased the entire interior of small islands.
	for start in starts:
		var at := Vector2i(start)
		var base_height := floorf(heights[at.y * size.x + at.x] + 0.45)
		for y in range(maxi(0, at.y - 9), mini(size.y, at.y + 10)):
			for x in range(maxi(0, at.x - 9), mini(size.x, at.x + 10)):
				var i := y * size.x + x
				if int(terrain[i]) in Base.WATER: continue
				var distance := start.distance_to(Vector2(x + 0.5, y + 0.5))
				heights[i] = lerpf(base_height, heights[i], smoothstep(4.0, 8.5, distance))
	var cells := PackedInt32Array()
	cells.resize(terrain.size())
	for i in range(terrain.size()):
		if int(terrain[i]) in Base.WATER: continue
		cells[i] = floori(heights[i] + 0.18)
		var point := Vector2(i % size.x + 0.5, i / size.x + 0.5)
		var near_town := false
		for start in starts:
			if point.distance_squared_to(start) < 5.5 * 5.5: near_town = true
		potential[i] = int(not near_town and coast[i] > 1 and strength[i] > float(recipe["forest_threshold"]))
	var levels: Array[int] = []
	levels.resize((size.x + 1) * (size.y + 1))
	for y in range(size.y + 1):
		for x in range(size.x + 1):
			var height := int(recipe["relief"])
			for dy in [-1, 0]:
				for dx in [-1, 0]:
					var cell := Vector2i(clampi(x + dx, 0, size.x - 1), clampi(y + dy, 0, size.y - 1))
					height = mini(height, cells[cell.y * size.x + cell.x])
			levels[y * (size.x + 1) + x] = height
	Base.relax_heights(levels, size)
	return {"moisture": moisture, "woodland": woodland, "geology": geology, "coast_distance": coast,
		"forest_potential": potential, "forest_strength": strength, "vertex_levels": levels, "recipe": recipe}

static func noise_field(size: Vector2i, period: float, seed: int) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = int(seed & 0x7fffffff)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / maxf(1.0, period)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.35
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = period * 0.28
	noise.domain_warp_frequency = 0.65 / period
	var result := PackedFloat32Array()
	result.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x): result[y * size.x + x] = clampf(0.5 + noise.get_noise_2d(x, y) * 0.90, 0.0, 1.0)
	return result

static func paint_ground(data: Dictionary, landscape: Dictionary) -> void:
	var terrain: Array[int] = data["terrain_ids"]
	var threshold := float(landscape["recipe"]["rock_threshold"])
	for i in range(terrain.size()):
		if int(terrain[i]) in Base.WATER: continue
		var moisture := float(landscape["moisture"][i])
		var rock := float(landscape["geology"][i])
		if rock > threshold and moisture < 0.36: terrain[i] = 1000
		elif moisture < 0.29 and rock > 0.52: terrain[i] = 1002
		elif moisture < 0.43 and rock > 0.57: terrain[i] = 1001
		else: terrain[i] = 0

static func forests(data: Dictionary, landscape: Dictionary, exclusions: Dictionary, seed: int, allow_slopes: bool = false) -> void:
	var size: Vector2i = data["size"]
	var terrain: Array[int] = data["terrain_ids"]
	var levels: Array[int] = data["vertex_levels"]
	var resources: Array = data["resources"]
	var occupied := exclusions.duplicate()
	for resource in resources:
		occupied[Vector2i(resource["position"])] = true
		if resource.get("kind", "") == "tree": Base.bind_tree(resource, landscape, size, seed)
	var depth := PackedInt32Array()
	depth.resize(terrain.size())
	depth.fill(999)
	var queue := PackedInt32Array()
	for i in range(terrain.size()):
		if int(landscape["forest_potential"][i]) == 0:
			depth[i] = 0
			queue.append(i)
	var cursor := 0
	while cursor < queue.size():
		var i := queue[cursor]
		cursor += 1
		for next in Navigation.neighbors(i, size):
			if depth[next] > depth[i] + 1:
				depth[next] = depth[i] + 1
				queue.append(next)
	for i in range(terrain.size()):
		if int(landscape["forest_potential"][i]) == 0: continue
		var cell := Vector2i(i % size.x, i / size.x)
		if occupied.has(cell) or (not allow_slopes and not Base.flat_cell(cell, size, levels)): continue
		var edge := depth[i] <= 2
		var density := lerpf(0.34, 0.90, smoothstep(0.0, 4.0, float(depth[i])))
		if Base.random_at(cell, seed ^ 0x737AE) > density: continue
		var resource := {"category": "resource", "kind": "tree", "amount": 75,
			"position": Vector2(cell) + Vector2(0.5, 0.5), "placement_domain": "land",
			"ecology_role": "forest_edge" if edge else "forest_core", "strategic_zone": Base._zone(data, i)}
		Base.bind_tree(resource, landscape, size, seed)
		resources.append(resource)
		occupied[cell] = true
	Base.forest_accents(data, landscape, occupied, seed)
	var mask := PackedByteArray()
	mask.resize(terrain.size())
	for resource in resources:
		if resource.get("kind", "") == "tree":
			var cell := Vector2i(resource["position"])
			mask[cell.y * size.x + cell.x] = 1
	for i in range(mask.size()):
		if mask[i] == 0: continue
		var cell := Vector2i(i % size.x, i / size.x)
		for y in range(maxi(0, cell.y - 1), mini(size.y, cell.y + 2)):
			for x in range(maxi(0, cell.x - 1), mini(size.x, cell.x + 2)):
				var at := y * size.x + x
				if terrain[at] in Base.WATER: continue
				var light := float(landscape["forest_strength"][at]) < float(landscape["recipe"]["forest_threshold"]) + 0.10
				terrain[at] = (10 if light else 1003) if mask[at] != 0 else (0 if light else 1001)
	data["forest_mask"] = mask

static func composition(data: Dictionary) -> Dictionary:
	var size: Vector2i = data["size"]
	var forest: PackedByteArray = data["forest_mask"]
	var terrain: Array[int] = data["terrain_ids"]
	var seen := PackedByteArray()
	seen.resize(forest.size())
	var land := terrain.size()
	for water_id in Base.WATER: land -= terrain.count(water_id)
	var grove_minimum := clampi(roundi(float(land) * 0.01), 4, 12)
	var fragments := 0
	var largest := 0
	var groves := 0
	for i in range(forest.size()):
		if forest[i] == 0 or seen[i] != 0: continue
		var queue := PackedInt32Array([i])
		seen[i] = 1
		var cursor := 0
		while cursor < queue.size():
			var at := queue[cursor]
			cursor += 1
			var x := at % size.x
			var y := at / size.x
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if x + dx < 0 or y + dy < 0 or x + dx >= size.x or y + dy >= size.y: continue
					var next := (y + dy) * size.x + x + dx
					if forest[next] == 0 or seen[next] != 0: continue
					seen[next] = 1
					queue.append(next)
		largest = maxi(largest, queue.size())
		if queue.size() >= grove_minimum: groves += 1
		elif queue.size() <= 3: fragments += queue.size()
	var trees := forest.count(1)
	return {"forest_fraction": float(trees) / maxi(1, land), "largest_grove_cells": largest,
		"substantial_grove_count": groves, "minimum_grove_cells": grove_minimum, "fragmented_tree_fraction": float(fragments) / maxi(1, trees),
		"elevated_vertices": data["vertex_levels"].filter(func(v): return int(v) > 0).size(), "land_cells": land}

static func evaluate(definition: Dictionary, data: Dictionary) -> Dictionary:
	var metrics := composition(data)
	var size: Vector2i = data["size"]
	var opportunities: Array[int] = []
	var walkable := Navigation.mask(data, definition)
	for player in definition.get("players", []):
		var start := Vector2(player["start"])
		var field := Navigation.flood(size, walkable, Vector2i(start))
		var count := 0
		for tree in data["resources"]:
			if tree.get("kind", "") != "tree" or start.distance_squared_to(tree["position"]) > 22.0 * 22.0: continue
			var access := Navigation.adjacent_reachable(size, field["distances"], Vector2i(tree["position"]))
			if access >= 0 and int(field["distances"][access]) <= 30: count += 1
		opportunities.append(count)
	var minimum := mini(80, int(opportunities.min())) if not opportunities.is_empty() else 0
	var maximum := mini(80, int(opportunities.max())) if not opportunities.is_empty() else 0
	var score := minimum - float(maximum - minimum) * 0.35
	score -= absf(float(metrics["forest_fraction"]) - 0.24) * 130.0
	score -= float(metrics["fragmented_tree_fraction"]) * 45.0
	score += minf(0.12, float(metrics["largest_grove_cells"]) / maxi(1, int(metrics["land_cells"]))) * 100.0
	var navigation := Navigation.inspect(definition, data)
	var errors: Array = navigation["errors"].duplicate()
	errors.append_array(composition_errors(metrics))
	if not errors.is_empty(): score -= 100000.0
	metrics["accessible_forest_opportunities"] = opportunities
	return {"score": score, "valid": errors.is_empty(), "errors": errors, "composition": metrics}

static func composition_errors(metrics: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if float(metrics["forest_fraction"]) < 0.035: errors.append("random_map_landscape_woodland_missing")
	if float(metrics["forest_fraction"]) > 0.60: errors.append("random_map_landscape_open_ground_missing")
	if int(metrics["largest_grove_cells"]) < int(metrics["minimum_grove_cells"]): errors.append("random_map_landscape_groves_fragmented")
	if float(metrics["fragmented_tree_fraction"]) > 0.65: errors.append("random_map_landscape_groves_fragmented")
	return errors

static func fingerprint(data: Dictionary) -> String:
	return (str(VERSION) + ":" + Base.fingerprint(data)).sha256_text()
