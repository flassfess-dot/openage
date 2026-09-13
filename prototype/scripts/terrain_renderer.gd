class_name RoRTerrainRenderer

const Coordinates := preload("res://scripts/coordinates.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")


static func tile_drawable(cell: Vector2i, terrain_id: int, terrain_provider: Callable, resource_catalog, terrain_elevation, zoom: float, view_offset: Vector2, map_seed: int) -> Dictionary:
	var terrain_kind := TerrainRules.base_texture_kind(terrain_id, resource_catalog.terrain_catalog_data)
	var source_terrain_id := int(TerrainRules.TERRAIN_IDS.get(terrain_kind, 0))
	var terrain_record: Dictionary = resource_catalog.terrain_catalog_data.get("terrains", {}).get(str(source_terrain_id), {})
	var profile: Dictionary = terrain_elevation.cell_profile(cell)
	var frames: Array = resource_catalog.terrain_all_textures.get(terrain_kind, [])
	if frames.is_empty():
		return {}
	var frame_index: int = terrain_elevation.terrain_frame(terrain_record, profile, cell, map_seed)
	frame_index = clampi(frame_index, 0, frames.size() - 1)
	var texture: Texture2D = frames[frame_index]
	var flat_center := Coordinates.world_to_screen(Vector2(cell) + Vector2(0.5, 0.5), zoom, view_offset)
	var tile_origin: Vector2 = terrain_elevation.tile_screen_origin(flat_center, texture.get_size(), profile, zoom)
	return {
		"cell": cell,
		"terrain_id": terrain_id,
		"terrain_kind": terrain_kind,
		"texture": texture,
		"frame": frame_index,
		"position": tile_origin,
		"size": texture.get_size() * zoom,
		"profile": profile,
		"borders": TerrainRules.border_layers(cell, terrain_provider, resource_catalog.terrain_catalog_data, map_seed),
	}
