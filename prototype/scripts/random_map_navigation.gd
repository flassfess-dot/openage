class_name RoRRandomMapNavigation
extends RefCounted

const TerrainRules := preload("res://scripts/terrain_rules.gd")
const Footprint := preload("res://scripts/footprint.gd")
const SceneryObstructions := preload("res://scripts/scenery_obstructions.gd")

# Cell occupancy is the same conservative raster used for harvesting targets.
# Moving wildlife is deliberately excluded: it is not a permanent obstruction.
static func mask(map_data: Dictionary, definition: Dictionary = {}, include_resources: bool = true) -> PackedByteArray:
	var size: Vector2i = map_data["size"]
	var terrain: Array = map_data["terrain_ids"]
	var result := PackedByteArray()
	result.resize(size.x * size.y)
	for i in range(result.size()):
		result[i] = int(TerrainRules.is_land_walkable(TerrainRules.logical_for_terrain_id(int(terrain[i]))))
	for cell in map_data.get("cliff_cells", []):
		_block(result, size, Vector2i(cell))
	for obstruction in SceneryObstructions.collect(map_data.get("scenery", [])):
		for cell in obstruction["occupied_cells"]: _block(result, size, cell)
	for item in definition.get("entities", []):
		if String(item.get("category", "")) == "building":
			# The generated town centre has a 3 x 3 obstruction footprint.
			for cell in Footprint.occupied_cells(Vector2(item["position"]), Vector2(1.5, 1.5)):
				_block(result, size, cell)
	if include_resources:
		for resource in map_data.get("resources", []):
			if String(resource.get("category", "resource")) == "resource" and String(resource.get("placement_domain", "land")) == "land":
				_block(result, size, Vector2i(resource["position"]))
	return result


static func neighbors(index: int, size: Vector2i) -> PackedInt32Array:
	var result := PackedInt32Array()
	var x := index % size.x
	if x > 0: result.append(index - 1)
	if x + 1 < size.x: result.append(index + 1)
	if index >= size.x: result.append(index - size.x)
	if index + size.x < size.x * size.y: result.append(index + size.x)
	return result


static func flood(size: Vector2i, walkable: PackedByteArray, origin: Vector2i) -> Dictionary:
	var distances := PackedInt32Array()
	var parents := PackedInt32Array()
	distances.resize(walkable.size())
	parents.resize(walkable.size())
	distances.fill(-1)
	parents.fill(-1)
	var start := nearest_open(size, walkable, origin)
	if start < 0: return {"distances": distances, "parents": parents, "start": -1}
	var queue := PackedInt32Array([start])
	distances[start] = 0
	var cursor := 0
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		for next in neighbors(current, size):
			if walkable[next] == 0 or distances[next] >= 0: continue
			distances[next] = distances[current] + 1
			parents[next] = current
			queue.append(next)
	return {"distances": distances, "parents": parents, "start": start}


static func nearest_open(size: Vector2i, walkable: PackedByteArray, origin: Vector2i) -> int:
	for radius in range(7):
		for y in range(maxi(0, origin.y - radius), mini(size.y, origin.y + radius + 1)):
			for x in range(maxi(0, origin.x - radius), mini(size.x, origin.x + radius + 1)):
				if maxi(absi(x - origin.x), absi(y - origin.y)) == radius and walkable[y * size.x + x] != 0:
					return y * size.x + x
	return -1


static func routes(definition: Dictionary, map_data: Dictionary) -> Dictionary:
	var size: Vector2i = map_data["size"]
	var walkable := mask(map_data, {}, false)
	var players: Array = definition.get("players", [])
	var reserved: Dictionary = {}
	var edges: Array = []
	# A ring plus a reachable central expansion creates alternate approaches.
	# On islands only edges within a connected landmass are admitted.
	for i in range(players.size()):
		var start := Vector2i(players[i]["start"])
		var field := flood(size, walkable, start)
		var destinations: Array = [Vector2i(players[(i + 1) % players.size()]["start"]), size / 2]
		for j in range(destinations.size()):
			var target := nearest_open(size, walkable, destinations[j])
			if target < 0 or int(field["distances"][target]) < 0: continue
			var path := trace(field, target)
			reserve_path(reserved, path, size, walkable, 2)
			edges.append({"from_team": int(players[i]["team"]), "to_team": int(players[(i + 1) % players.size()]["team"]) if j == 0 else 0,
				"role": ("ally_link" if int(players[i].get("alliance_id", players[i]["team"])) == int(players[(i + 1) % players.size()].get("alliance_id", players[(i + 1) % players.size()]["team"])) else "front") if j == 0 else "expansion",
				"width_cells": 5, "path": path})
	return {"reserved": reserved, "edges": edges}


static func protect_economy(definition: Dictionary, map_data: Dictionary, reserved: Dictionary) -> void:
	var size: Vector2i = map_data["size"]
	var walkable := mask(map_data, definition)
	var repairs: Array = []
	var required: Dictionary = definition.get("map", {}).get("generator", {}).get("quality_contract", {}).get("resource_counts", {})
	var occupied: Dictionary = {}
	for resource in map_data.get("resources", []): occupied[Vector2i(resource["position"])] = true
	for player in definition.get("players", []):
		var start := Vector2(player["start"])
		var field := flood(size, walkable, Vector2i(start))
		var accessible_counts: Dictionary = {}
		# Preserve existing useful paths first; repair only a missing opening quota.
		for resource in map_data.get("resources", []):
			var owner: Array = resource.get("owner_start", [])
			if owner.size() < 2 or not start.is_equal_approx(Vector2(owner[0], owner[1])): continue
			var access := adjacent_reachable(size, field["distances"], Vector2i(resource["position"]))
			if access < 0: continue
			reserve_path(reserved, trace(field, access), size, walkable, 0)
			if start.distance_to(resource["position"]) <= 20.0:
				var kind := String(resource.get("kind", ""))
				accessible_counts[kind] = int(accessible_counts.get(kind, 0)) + 1
		# Relocating one tree can change access to another. Recount the current
		# flood after each move instead of relying on a stale opening quota.
		for repair_pass in range(32):
			accessible_counts.clear()
			for resource in map_data.get("resources", []):
				var owner: Array = resource.get("owner_start", [])
				if owner.size() < 2 or not start.is_equal_approx(Vector2(owner[0], owner[1])) or start.distance_to(resource["position"]) > 20.0: continue
				if adjacent_reachable(size, field["distances"], Vector2i(resource["position"])) < 0: continue
				var kind := String(resource.get("kind", ""))
				accessible_counts[kind] = int(accessible_counts.get(kind, 0)) + 1
			var repaired := false
			for resource in map_data.get("resources", []):
				var owner: Array = resource.get("owner_start", [])
				if owner.size() < 2 or not start.is_equal_approx(Vector2(owner[0], owner[1])) or start.distance_to(resource["position"]) > 20.0: continue
				var kind := String(resource.get("kind", ""))
				if int(accessible_counts.get(kind, 0)) >= int(required.get(kind, 0)): continue
				var original := Vector2i(resource["position"])
				if adjacent_reachable(size, field["distances"], original) >= 0: continue
				var replacement := _repair_cell(size, map_data["terrain_ids"], walkable, field["distances"], original, start, reserved, occupied)
				if replacement < 0: continue
				resource["position"] = Vector2(replacement % size.x + 0.5, replacement / size.x + 0.5)
				occupied.erase(original)
				occupied[Vector2i(resource["position"])] = true
				walkable[original.y * size.x + original.x] = 1
				walkable[replacement] = 0
				field = flood(size, walkable, Vector2i(start))
				var access := adjacent_reachable(size, field["distances"], Vector2i(resource["position"]))
				if access >= 0: reserve_path(reserved, trace(field, access), size, walkable, 0)
				repairs.append({"kind": resource["kind"], "team": int(player["team"]), "from": original, "to": Vector2i(resource["position"]), "reason": "blocked_gather_approach"})
				repaired = true
				break
			if not repaired: break
		for resource in map_data.get("resources", []):
			var owner: Array = resource.get("owner_start", [])
			if owner.size() < 2 or not start.is_equal_approx(Vector2(owner[0], owner[1])): continue
			var access := adjacent_reachable(size, field["distances"], Vector2i(resource["position"]))
			if access >= 0: reserve_path(reserved, trace(field, access), size, walkable, 0)
		# Keep routes to the closest expansion mines open when the forest is planted.
		var expansions: Array = map_data.get("resources", []).filter(func(resource): return resource.get("owner_start", []).is_empty() and String(resource.get("kind", "")) in ["gold_mine", "stone_mine"])
		expansions.sort_custom(func(left, right): return start.distance_squared_to(Vector2(left["position"])) < start.distance_squared_to(Vector2(right["position"])))
		var expansion_counts := {"gold_mine": 0, "stone_mine": 0}
		for resource in expansions:
			var kind := String(resource["kind"])
			if int(expansion_counts[kind]) >= 4:
				continue
			var access := adjacent_reachable(size, field["distances"], Vector2i(resource["position"]))
			if access >= 0:
				reserve_path(reserved, trace(field, access), size, walkable, 0)
				expansion_counts[kind] = int(expansion_counts[kind]) + 1
		for zone in map_data.get("naval_start_zones", []):
			if int(zone.get("team", -1)) != int(player["team"]): continue
			var index := nearest_open(size, walkable, Vector2i(zone["land_staging"]))
			if index >= 0 and int(field["distances"][index]) >= 0:
				reserve_path(reserved, trace(field, index), size, walkable, 1)

	map_data["generation_repairs"] = repairs


static func _repair_cell(size: Vector2i, terrain: Array, walkable: PackedByteArray, distances: PackedInt32Array, origin: Vector2i, start: Vector2, reserved: Dictionary, occupied: Dictionary) -> int:
	# Bounded local relocation; it cannot consume an already protected route.
	for radius in range(1, 21):
		for y in range(maxi(0, origin.y - radius), mini(size.y, origin.y + radius + 1)):
			for x in range(maxi(0, origin.x - radius), mini(size.x, origin.x + radius + 1)):
				var cell := Vector2i(x, y)
				var i := y * size.x + x
				if maxi(absi(x - origin.x), absi(y - origin.y)) != radius or reserved.has(cell) or occupied.has(cell) or walkable[i] == 0 or distances[i] < 0 or int(terrain[i]) in [1, 4, 22]: continue
				if start.distance_to(Vector2(cell) + Vector2(0.5, 0.5)) > 19.5: continue
				var open_neighbors := 0
				for next in neighbors(i, size):
					if walkable[next] != 0: open_neighbors += 1
				if open_neighbors >= 3: return i
	return -1


static func trace(field: Dictionary, target: int) -> PackedInt32Array:
	var path := PackedInt32Array()
	var current := target
	while current >= 0:
		path.append(current)
		current = int(field["parents"][current])
	return path


static func reserve_path(reserved: Dictionary, path: PackedInt32Array, size: Vector2i, walkable: PackedByteArray, radius: int) -> void:
	for index in path:
		var cell := Vector2i(index % size.x, index / size.x)
		for y in range(maxi(0, cell.y - radius), mini(size.y, cell.y + radius + 1)):
			for x in range(maxi(0, cell.x - radius), mini(size.x, cell.x + radius + 1)):
				if walkable[y * size.x + x] != 0: reserved[Vector2i(x, y)] = true


static func adjacent_reachable(size: Vector2i, distances: PackedInt32Array, cell: Vector2i) -> int:
	if not inside(cell, size): return -1
	var best := -1
	for index in neighbors(cell.y * size.x + cell.x, size):
		if distances[index] >= 0 and (best < 0 or distances[index] < distances[best]): best = index
	return best


static func inspect(definition: Dictionary, map_data: Dictionary) -> Dictionary:
	var size: Vector2i = map_data["size"]
	var walkable := mask(map_data, definition)
	var errors: Array[String] = []
	var by_team: Dictionary = {}
	var reachable_starts: Array[int] = []
	var required: Dictionary = definition.get("map", {}).get("generator", {}).get("quality_contract", {}).get("resource_counts", {})
	for player in definition.get("players", []):
		var start := Vector2(player["start"])
		var team := int(player["team"])
		var field := flood(size, walkable, Vector2i(start))
		var distances: PackedInt32Array = field["distances"]
		var counts: Dictionary = {}
		var route_costs: Dictionary = {}
		for resource in map_data.get("resources", []):
			var owner: Array = resource.get("owner_start", [])
			if owner.size() < 2 or not start.is_equal_approx(Vector2(owner[0], owner[1])): continue
			if start.distance_to(Vector2(resource["position"])) > 20.0: continue
			var kind := String(resource.get("kind", ""))
			var access := adjacent_reachable(size, distances, Vector2i(resource["position"]))
			if access < 0: continue
			counts[kind] = int(counts.get(kind, 0)) + 1
			route_costs[kind] = mini(int(route_costs.get(kind, 1000000)), distances[access])
		for kind in required:
			if int(counts.get(kind, 0)) < int(required[kind]): errors.append("random_map_final_resource_unreachable:%d:%s" % [team, kind])
		if reachable_starts.is_empty():
			for other in definition.get("players", []):
				var target := nearest_open(size, walkable, Vector2i(other["start"]))
				reachable_starts.append(int(target >= 0 and distances[target] >= 0))
		by_team[str(team)] = {"accessible_nearby": counts, "nearest_gather_path_cells": route_costs}
	if bool(definition.get("map", {}).get("generator", {}).get("requires_shared_land", false)) and reachable_starts.has(0):
		errors.append("random_map_final_shared_land_disconnected")
	return {"valid": errors.is_empty(), "errors": errors, "by_team": by_team, "walkable_cells": walkable.count(1)}


static func inside(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


static func _block(walkable: PackedByteArray, size: Vector2i, cell: Vector2i) -> void:
	if inside(cell, size): walkable[cell.y * size.x + cell.x] = 0
