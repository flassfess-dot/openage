class_name RoRTerrainRules

const TERRAIN_FRAME_COUNTS := {
	"grass": 9,
	"sand": 9,
	"water": 4,
}

const TERRAIN_IDS := {"grass": 0, "water": 1, "sand": 6, "forest_floor": 10}
const WATER_TERRAIN_IDS := [1, 4, 22]
const OPEN_WATER_TERRAIN_IDS := [1, 22]
const SOURCE_FOREST_TERRAIN_IDS := [10, 13, 19, 20]

const EDGE_NEGATIVE_X := 1
const EDGE_NEGATIVE_Y := 2
const EDGE_POSITIVE_X := 4
const EDGE_POSITIVE_Y := 8
const EDGE_DIRECTIONS := [
	{"offset": Vector2i(-1, 0), "bit": EDGE_NEGATIVE_X},
	{"offset": Vector2i(0, -1), "bit": EDGE_NEGATIVE_Y},
	{"offset": Vector2i(1, 0), "bit": EDGE_POSITIVE_X},
	{"offset": Vector2i(0, 1), "bit": EDGE_POSITIVE_Y},
]

const BORDER_ASSET_NAMES := {
	2: "border_desert_water",
	3: "border_grass_water",
	4: "border_grass_desert",
	5: "border_grass_forest",
	6: "border_grass_desert2",
}
const BORDER_DESERT_WATER := 2
const BORDER_GRASS_WATER := 3
const STYLE0_CORNER_MASKS := [
	EDGE_NEGATIVE_X | EDGE_NEGATIVE_Y,
	EDGE_NEGATIVE_Y | EDGE_POSITIVE_X,
	EDGE_POSITIVE_X | EDGE_POSITIVE_Y,
	EDGE_POSITIVE_Y | EDGE_NEGATIVE_X,
]


static func terrain_at(cell: Vector2i) -> String:
	if cell.x <= 1 or cell.y <= 0:
		return "water"
	if cell.x == 2 or cell.y == 1:
		return "shore"
	return "land"


static func is_land_walkable(terrain: String) -> bool:
	return terrain in ["land", "shore", "grass", "sand"]


static func is_water_navigable(terrain: String) -> bool:
	return terrain in ["water", "dark_water"]


static func is_terrain_accessible(restrictions: Array, restriction_id: int, terrain_id: int) -> bool:
	if restriction_id < 0 or restriction_id >= restrictions.size():
		return false
	var values: Array = restrictions[restriction_id].get("accessible_damage_multiplier", [])
	return terrain_id >= 0 and terrain_id < values.size() and float(values[terrain_id]) > 0.05


static func frame_count(terrain_kind: String) -> int:
	return int(TERRAIN_FRAME_COUNTS.get(terrain_kind, 0))


static func tile_variant(cell: Vector2i, terrain_kind: String, map_seed: int, available_frames: int = -1) -> int:
	var count := available_frames if available_frames > 0 else frame_count(terrain_kind)
	if count <= 1:
		return 0
	# Two-dimensional integer mixing prevents the diagonal bands produced by
	# simple x/y linear combinations while staying deterministic on every run.
	var value := int(cell.x) * 73856093
	value = value ^ (int(cell.y) * 19349663)
	value = value ^ (map_seed * 83492791)
	value = value ^ (String(terrain_kind).hash() * 2654435761)
	value = value ^ (value >> 13)
	value *= 1274126177
	value = value ^ (value >> 16)
	return posmod(value, count)


static func terrain_id_for_logical(terrain_kind: String) -> int:
	match terrain_kind:
		"water": return 1
		"shore": return 2
		"forest", "forest_floor": return 10
		"sand", "desert": return 6
		_: return 0


static func logical_for_terrain_id(terrain_id: int) -> String:
	match terrain_id:
		1, 4, 22: return "water"
		2: return "shore"
		6: return "sand"
		10, 19, 20: return "forest_floor"
		13: return "sand"
		_: return "grass"


static func base_texture_kind(terrain_id: int, terrain_catalog: Dictionary) -> String:
	var current_id := terrain_id
	var visited := {}
	while not visited.has(current_id):
		visited[current_id] = true
		match current_id:
			0: return "grass"
			1, 22: return "water"
			4: return "sand"
			6: return "sand"
		var record: Dictionary = terrain_catalog.get("terrains", {}).get(str(current_id), {})
		var replacement_id := int(record.get("replacement_terrain_id", -1))
		if replacement_id < 0:
			break
		current_id = replacement_id
	return "grass"


static func border_layers(cell: Vector2i, terrain_provider: Callable, terrain_catalog: Dictionary, map_seed: int) -> Array:
	if not terrain_provider.is_valid():
		return []
	var current_id := int(terrain_provider.call(cell))
	var current: Dictionary = terrain_catalog.get("terrains", {}).get(str(current_id), {})
	var border_table: Array = current.get("borders", [])
	var masks_by_border := {}
	for edge in EDGE_DIRECTIONS:
		var neighbor_id := int(terrain_provider.call(cell + edge["offset"]))
		if neighbor_id == current_id or neighbor_id < 0 or neighbor_id >= border_table.size():
			continue
		var border_id := int(border_table[neighbor_id])
		if border_id <= 0 or not BORDER_ASSET_NAMES.has(border_id):
			continue
		masks_by_border[border_id] = int(masks_by_border.get(border_id, 0)) | int(edge["bit"])

	var border_ids: Array = masks_by_border.keys()
	border_ids.sort()
	var layers: Array = []
	for border_id_value in border_ids:
		var border_id := int(border_id_value)
		var border: Dictionary = terrain_catalog.get("borders", {}).get(str(border_id), {})
		var mask := int(masks_by_border[border_id])
		var style := int(border.get("border_style", 0))
		if style == 1:
			for edge in EDGE_DIRECTIONS:
				var bit := int(edge["bit"])
				if mask & bit:
					layers.append(make_border_layer(border_id, style1_frame_for_edge(bit), mask))
		else:
			var diagonal_neighbor_id := corner_diagonal_neighbor_id(cell, mask, terrain_provider)
			var frame := style0_frame_for_mask(mask, cell, map_seed, current_id, diagonal_neighbor_id, border_id, terrain_catalog)
			if frame >= 0:
				layers.append(make_border_layer(style0_sprite_border_id(border_id, mask), frame, mask))
	return layers


static func make_border_layer(border_id: int, frame: int, neighbor_mask: int) -> Dictionary:
	return {
		"border_id": border_id,
		"asset_name": BORDER_ASSET_NAMES[border_id],
		"frame": frame,
		"neighbor_mask": neighbor_mask,
	}


static func style1_frame_for_edge(edge_bit: int) -> int:
	match edge_bit:
		EDGE_NEGATIVE_X: return 0
		EDGE_NEGATIVE_Y: return 1
		EDGE_POSITIVE_X: return 3
		EDGE_POSITIVE_Y: return 2
	return -1


static func style0_sprite_border_id(border_id: int, mask: int) -> int:
	# Grass/water's flat corner pairs are byte-identical in the source SLP, so
	# they cannot distinguish a small cape from a small bay. Desert/water uses
	# the same shoreline palette and contains the intended convex/concave pair.
	if border_id == BORDER_GRASS_WATER and mask in STYLE0_CORNER_MASKS:
		return BORDER_DESERT_WATER
	return border_id


static func style0_frame_for_mask(mask: int, cell: Vector2i, map_seed: int, current_id: int = -1, diagonal_neighbor_id: int = -1, border_id: int = -1, terrain_catalog: Dictionary = {}) -> int:
	match mask:
		EDGE_NEGATIVE_X: return 8
		EDGE_NEGATIVE_Y: return 11
		EDGE_POSITIVE_X: return 9
		EDGE_POSITIVE_Y: return 10
		EDGE_NEGATIVE_X | EDGE_NEGATIVE_Y:
			return 1 if _style0_corner_is_external(current_id, diagonal_neighbor_id, border_id, terrain_catalog) else 6
		EDGE_NEGATIVE_Y | EDGE_POSITIVE_X:
			return 3 if _style0_corner_is_external(current_id, diagonal_neighbor_id, border_id, terrain_catalog) else 4
		EDGE_POSITIVE_X | EDGE_POSITIVE_Y:
			return 2 if _style0_corner_is_external(current_id, diagonal_neighbor_id, border_id, terrain_catalog) else 5
		EDGE_POSITIVE_Y | EDGE_NEGATIVE_X:
			return 0 if _style0_corner_is_external(current_id, diagonal_neighbor_id, border_id, terrain_catalog) else 7
	# Opposite and three-sided cases are split into stable single-edge masks.
	# Valid RoR map tiles normally resolve these by choosing the other underlay.
	for edge in EDGE_DIRECTIONS:
		if mask & int(edge["bit"]):
			return style0_frame_for_mask(int(edge["bit"]), cell, map_seed, current_id, diagonal_neighbor_id, border_id, terrain_catalog)
	return -1


static func corner_diagonal_neighbor_id(cell: Vector2i, mask: int, terrain_provider: Callable) -> int:
	if not terrain_provider.is_valid():
		return -1
	var offset := Vector2i.ZERO
	match mask:
		EDGE_NEGATIVE_X | EDGE_NEGATIVE_Y:
			offset = Vector2i(-1, -1)
		EDGE_NEGATIVE_Y | EDGE_POSITIVE_X:
			offset = Vector2i(1, -1)
		EDGE_POSITIVE_X | EDGE_POSITIVE_Y:
			offset = Vector2i(1, 1)
		EDGE_POSITIVE_Y | EDGE_NEGATIVE_X:
			offset = Vector2i(-1, 1)
		_:
			return -1
	return int(terrain_provider.call(cell + offset))


static func _style0_corner_is_external(current_id: int, diagonal_neighbor_id: int, border_id: int, terrain_catalog: Dictionary) -> bool:
	if current_id < 0 or diagonal_neighbor_id < 0 or border_id < 0:
		return true
	if diagonal_neighbor_id == current_id:
		return false
	var current: Dictionary = terrain_catalog.get("terrains", {}).get(str(current_id), {})
	var border_table: Array = current.get("borders", [])
	if diagonal_neighbor_id >= border_table.size():
		return true
	return int(border_table[diagonal_neighbor_id]) == border_id


static func is_source_forest_terrain_id(terrain_id: int) -> bool:
	return terrain_id in SOURCE_FOREST_TERRAIN_IDS
