class_name RoRRandomMapBuildingSpace
extends RefCounted

const Base := preload("res://scripts/random_map_landscape.gd")
const Navigation := preload("res://scripts/random_map_navigation.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Footprint := preload("res://scripts/footprint.gd")

# Reserve an expansion meadow before economy placement and the forest pass.
# Select existing level ground; never flatten a river or lower a mountain lake.
static func reserve(definition: Dictionary, data: Dictionary, fields: Dictionary, reserved: Dictionary, exclusions: Dictionary) -> void:
	var size: Vector2i = data["size"]
	var blocked := _occupied(data)
	blocked.merge(exclusions, true)
	for entity in definition.get("entities", []):
		if entity.get("category", "") != "building": continue
		for cell in Footprint.occupied_cells(Vector2(entity["position"]),Vector2(1.5,1.5)): blocked[cell] = true
	var walkable := Navigation.mask(data, definition)
	var clearings: Array = []
	for player in definition.get("players", []):
		var start := Vector2i(Vector2(player["start"]))
		var field := Navigation.flood(size, walkable, start)
		var distances: PackedInt32Array = field["distances"]
		var best := Vector2i(-1, -1)
		var width := 0
		# A narrow cape may need an expansion farther along the same landmass.
		# Keep nearby choices stable and extend only a failed local search.
		for reach in [18, 28]:
			for candidate_width in [5, 3]:
				best = _find(data, fields, blocked, distances, start, candidate_width, reach)
				if best.x >= 0:
					width = candidate_width
					break
			if width > 0: break
		if width == 0: continue
		var target := best + Vector2i(width / 2, width / 2)
		Navigation.reserve_path(reserved, Navigation.trace(field, target.y * size.x + target.x), size, walkable, 0)
		for y in range(maxi(0, best.y - 1), mini(size.y, best.y + width + 1)):
			for x in range(maxi(0, best.x - 1), mini(size.x, best.x + width + 1)):
				reserved[Vector2i(x, y)] = true
				blocked[Vector2i(x, y)] = true
		clearings.append({"team":int(player["team"]), "origin":best, "width":width})
	data["building_clearings"] = clearings

static func _find(data: Dictionary, fields: Dictionary, blocked: Dictionary, distances: PackedInt32Array, start: Vector2i, width: int, reach: int) -> Vector2i:
	var size: Vector2i = data["size"]
	var best := Vector2i(-1, -1)
	var score := INF
	for y in range(maxi(0, start.y - reach), mini(size.y - width + 1, start.y + reach + 1)):
		for x in range(maxi(0, start.x - reach), mini(size.x - width + 1, start.x + reach + 1)):
			var center := Vector2i(x + width / 2, y + width / 2)
			var distance := distances[center.y * size.x + center.x]
			if distance < 0 or distance > reach * 4 / 3: continue
			var candidate := float(distance) + float(fields["forest_strength"][center.y * size.x + center.x]) * 12.0
			if candidate >= score or not _fits(data, Vector2i(x, y), width, blocked): continue
			best = Vector2i(x, y)
			score = candidate
	return best

static func _fits(data: Dictionary, origin: Vector2i, width: int, blocked: Dictionary) -> bool:
	var size: Vector2i = data["size"]
	for y in range(origin.y, origin.y + width):
		for x in range(origin.x, origin.x + width):
			var cell := Vector2i(x, y)
			if blocked.has(cell) or data["terrain_ids"][y * size.x + x] in Rules.WATER_TERRAIN_IDS or not Base.flat_cell(cell, size, data["vertex_levels"]): return false
	return true

static func _occupied(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for cell in data.get("cliff_cells", []): result[cell] = true
	for item in data.get("resources", []): result[Vector2i(item["position"])] = true
	return result

static func measure(data: Dictionary) -> Dictionary:
	var size: Vector2i = data["size"]
	var occupied := _occupied(data)
	var stride := size.x + 1
	var terrain_bad := PackedInt32Array()
	var occupied_bad := PackedInt32Array()
	terrain_bad.resize(stride * (size.y + 1))
	occupied_bad.resize(terrain_bad.size())
	var dry := 0
	var flat := 0
	for y in range(size.y):
		for x in range(size.x):
			var cell := Vector2i(x, y)
			var land: bool = data["terrain_ids"][y * size.x + x] not in Rules.WATER_TERRAIN_IDS
			var level: bool = land and Base.flat_cell(cell, size, data["vertex_levels"])
			dry += int(land)
			flat += int(level)
			var i := (y + 1) * stride + x + 1
			terrain_bad[i] = int(not level) + terrain_bad[i - 1] + terrain_bad[i - stride] - terrain_bad[i - stride - 1]
			occupied_bad[i] = int(not level or occupied.has(cell)) + occupied_bad[i - 1] + occupied_bad[i - stride] - occupied_bad[i - stride - 1]
	var sites := 0
	var clear := 0
	for y in range(maxi(0, size.y - 4)):
		for x in range(maxi(0, size.x - 4)):
			var a := y * stride + x
			var b := a + 5
			var c := a + 5 * stride
			var d := c + 5
			sites += int(terrain_bad[d] - terrain_bad[c] - terrain_bad[b] + terrain_bad[a] == 0)
			clear += int(occupied_bad[d] - occupied_bad[c] - occupied_bad[b] + occupied_bad[a] == 0)
	return {"flat_land_fraction":float(flat) / maxi(1, dry), "level_5x5_positions":sites, "unoccupied_5x5_positions":clear, "protected_clearings":data.get("building_clearings", []).size()}
