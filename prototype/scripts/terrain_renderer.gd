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
		"underlays": _slope_underlays(cell, terrain_kind, terrain_record, profile, frames, flat_center, tile_origin, zoom, map_seed),
		"borders": TerrainRules.border_layers(cell, terrain_provider, resource_catalog.terrain_catalog_data, map_seed),
	}


static func _slope_underlays(cell: Vector2i, terrain_kind: String, terrain_record: Dictionary, profile: Dictionary, frames: Array, flat_center: Vector2, tile_origin: Vector2, zoom: float, map_seed: int) -> Array:
	# Genie's two-corner slope sprites (TOP|RIGHT and friends) are sheared
	# half-cliffs: their alpha leaves a transparent notch over part of the cell
	# that the original engine covers with neighbouring tiles. Rendering the
	# cell's flat variant beneath the slope closes that notch with base terrain
	# instead of the black canvas background.
	var slope_index := int(profile.get("slope_index", -1))
	if slope_index <= 0:
		return []
	var base_elevation := int(profile.get("base_elevation", 0))
	var flat_frame: int = terrain_elevation_flat_frame(terrain_record, cell, map_seed)
	flat_frame = clampi(flat_frame, 0, frames.size() - 1)
	var texture: Texture2D = frames[flat_frame]
	if texture == null:
		return []
	var flat_origin: Vector2 = flat_center - Vector2(texture.get_size().x * 0.5, Coordinates.TILE_HEIGHT * 0.5 + float(base_elevation) * RoRTerrainElevation.ELEVATION_PIXEL_STEP) * zoom
	var first := {
		"texture": texture,
		"frame": flat_frame,
		"position": flat_origin,
		"size": texture.get_size() * zoom,
	}
	if flat_origin.is_equal_approx(tile_origin):
		return [first]
	return [
		first,
		{
			"texture": texture,
			"frame": flat_frame,
			"position": tile_origin,
			"size": texture.get_size() * zoom,
		},
	]


static func terrain_elevation_flat_frame(terrain_record: Dictionary, cell: Vector2i, map_seed: int) -> int:
	var elevation_graphics: Array = terrain_record.get("elevation_graphics", [])
	if elevation_graphics.is_empty():
		return 0
	var graphic: Dictionary = elevation_graphics[0]
	var frame_count := int(graphic.get("frame_count", 0))
	if frame_count <= 0:
		return 0
	return int(graphic.get("shape_id", 0)) + TerrainRules.tile_variant(cell, "terrain", map_seed, frame_count)
