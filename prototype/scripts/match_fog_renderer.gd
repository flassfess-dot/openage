extends RefCounted

# Scene access is scoped to each call; this owner never retains the scene.
const Coordinates := preload("res://scripts/coordinates.gd")
const CacheDependency := preload("res://scripts/cache_dependency.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")
const ViewportCulling := preload("res://scripts/viewport_culling.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const FogPresentation := preload("res://scripts/fog_presentation.gd")
const WORLD_FOG_GEOMETRY_CHUNK_SIZE := 16
const WORLD_FOG_GEOMETRY_RETAIN_MARGIN := 1

var cached_fog_revision: int = -1
var cached_fog_runs: Array = []
var cached_world_fog_meshes: Dictionary = {}
var cached_world_fog_mesh_terrain_revision: int = -1
var cached_world_fog_texture: ImageTexture
var cached_world_fog_texture_data := PackedByteArray()
var cached_world_fog_texture_revision: int = -1
var cached_world_fog_stamp: Dictionary = {}
var cached_fog_slope_neighbor_cells := PackedByteArray()
var cached_fog_slope_neighbor_terrain_revision: int = -1
var cached_map_edge_chains: Array[PackedVector2Array] = []
var cached_map_edge_fog_meshes: Dictionary = {}
var cached_map_edge_fog_revision := -1
var cached_map_edge_zoom := -1.0
var cached_map_edge_terrain_revision := -1

func _terrain_geometry_revision(game) -> int:
	if game._render_terrain() == null:
		return -1
	var elevation = game._render_terrain().terrain_elevation
	return CacheDependency.geometry_key(game.map_size, elevation)


func _sync_fog_geometry_revision(game) -> void:
	var geometry_revision = game._terrain_geometry_revision()
	if cached_fog_slope_neighbor_terrain_revision != geometry_revision:
		cached_fog_slope_neighbor_cells.resize(0)
		cached_fog_slope_neighbor_terrain_revision = geometry_revision
		cached_world_fog_meshes.clear()
		cached_world_fog_mesh_terrain_revision = -1
		cached_world_fog_texture_revision = -1
	if cached_world_fog_mesh_terrain_revision != geometry_revision:
		cached_world_fog_meshes.clear()
		cached_world_fog_mesh_terrain_revision = geometry_revision


func draw_fog_overlay(game) -> void:
	if game.presentation_snapshot.is_empty():
		return
	var probe: Variant = game._presentation_probe()
	var cells: Variant = game.presentation_snapshot.get("fog", {}).get("cells", [])
	if cells.size() < game.map_size.x * game.map_size.y:
		return
	var fog_revision = int(game.presentation_snapshot.get("fog_revision", -1))
	var prepare_started = Time.get_ticks_usec() if probe != null else 0
	game._sync_fog_geometry_revision()
	game._sync_world_fog_texture(cells, fog_revision, probe)
	var visible_meshes: Array[ArrayMesh] = []
	var bounds = game._expanded_tile_bounds(game.visible_tile_bounds(), 12)
	var first_chunk = Vector2i(
		floori(float(bounds.position.x) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE)),
		floori(float(bounds.position.y) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE))
	)
	var last_chunk = Vector2i(
		floori(float(maxi(bounds.position.x, bounds.end.x - 1)) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE)),
		floori(float(maxi(bounds.position.y, bounds.end.y - 1)) / float(WORLD_FOG_GEOMETRY_CHUNK_SIZE))
	)
	var built_meshes = 0
	for chunk_y in range(first_chunk.y, last_chunk.y + 1):
		for chunk_x in range(first_chunk.x, last_chunk.x + 1):
			var chunk_key = Vector2i(chunk_x, chunk_y)
			var mesh: Variant = cached_world_fog_meshes.get(chunk_key)
			if not mesh is ArrayMesh:
				mesh = game._build_world_fog_mesh(game._world_fog_geometry_chunk_bounds(chunk_key))
				if mesh is ArrayMesh:
					cached_world_fog_meshes[chunk_key] = mesh
					built_meshes += 1
			if mesh is ArrayMesh:
				visible_meshes.append(mesh)
	var retained_bounds = Rect2i(
		first_chunk - Vector2i.ONE * WORLD_FOG_GEOMETRY_RETAIN_MARGIN,
		(last_chunk - first_chunk) + Vector2i.ONE * (WORLD_FOG_GEOMETRY_RETAIN_MARGIN * 2 + 1)
	)
	var evicted_meshes = game._prune_world_fog_geometry_cache(retained_bounds)
	if probe != null:
		probe.observe_microseconds("presentation.fog.prepare", Time.get_ticks_usec() - prepare_started)
		if built_meshes > 0:
			probe.increment("presentation.fog.geometry_chunks_built", built_meshes)
		if evicted_meshes > 0:
			probe.increment("presentation.fog.geometry_chunks_evicted", evicted_meshes)
	if visible_meshes.is_empty() or cached_world_fog_texture == null:
		return
	var submit_started = Time.get_ticks_usec() if probe != null else 0
	game.draw_set_transform(PixelScaling.snap_screen(game.view_offset), 0.0, Vector2(game.view_zoom, game.view_zoom))
	for mesh in visible_meshes:
		game.draw_mesh(mesh, cached_world_fog_texture)
	game.draw_set_transform(Vector2.ZERO)
	game.draw_map_edge_fog_overlay()
	if probe != null:
		probe.observe_microseconds("presentation.fog.mesh_submit", Time.get_ticks_usec() - submit_started)


func _world_fog_geometry_chunk_bounds(game, chunk_key: Vector2i) -> Rect2i:
	var start = chunk_key * WORLD_FOG_GEOMETRY_CHUNK_SIZE
	var finish = Vector2i(
		mini(game.map_size.x, start.x + WORLD_FOG_GEOMETRY_CHUNK_SIZE),
		mini(game.map_size.y, start.y + WORLD_FOG_GEOMETRY_CHUNK_SIZE)
	)
	start.x = maxi(0, start.x)
	start.y = maxi(0, start.y)
	return Rect2i(start, Vector2i(maxi(0, finish.x - start.x), maxi(0, finish.y - start.y)))


func _prune_world_fog_geometry_cache(game, retained_bounds: Rect2i) -> int:
	var removed = 0
	for chunk_key_value in cached_world_fog_meshes.keys():
		var chunk_key: Vector2i = chunk_key_value
		if retained_bounds.has_point(chunk_key):
			continue
		cached_world_fog_meshes.erase(chunk_key)
		removed += 1
	return removed


func _build_world_fog_mesh(game, bounds: Rect2i) -> ArrayMesh:
	# Geometry never depends on fog state. Chunks are created only as the camera
	# reaches them and retained for the current viewport plus one surrounding
	# ring, so exploration cannot grow a history of GPU objects.
	if game._render_terrain() == null or bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var lattice_width = bounds.size.x + 1
	var lattice_height = bounds.size.y + 1
	var vertices = PackedVector3Array()
	var uvs = PackedVector2Array()
	vertices.resize(lattice_width * lattice_height)
	uvs.resize(vertices.size())
	for y in range(lattice_height):
		for x in range(lattice_width):
			var vertex_index = y * lattice_width + x
			var world = Vector2(bounds.position + Vector2i(x, y))
			var projected: Vector2 = game._render_terrain().terrain_elevation.world_to_screen(world, 1.0, Vector2.ZERO)
			projected = PixelScaling.snap_screen(projected)
			vertices[vertex_index] = Vector3(projected.x, projected.y, 0.0)
			uvs[vertex_index] = Vector2(clampf(world.x / float(game.map_size.x), 0.5 / game.map_size.x, 1.0 - 0.5 / game.map_size.x), clampf(world.y / float(game.map_size.y), 0.5 / game.map_size.y, 1.0 - 0.5 / game.map_size.y))
	var indices = PackedInt32Array()
	indices.resize(bounds.size.x * bounds.size.y * 6)
	var index_offset = 0
	for y in range(bounds.size.y):
		for x in range(bounds.size.x):
			var top_left = y * lattice_width + x
			var top_right = top_left + 1
			var bottom_left = top_left + lattice_width
			var bottom_right = bottom_left + 1
			indices[index_offset] = top_left
			indices[index_offset + 1] = top_right
			indices[index_offset + 2] = bottom_right
			indices[index_offset + 3] = top_left
			indices[index_offset + 4] = bottom_right
			indices[index_offset + 5] = bottom_left
			index_offset += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _sync_world_fog_texture(game, cells: Variant, fog_revision: int, probe: Variant = null) -> void:
	if game.simulation_owner.pending: return
	var expected_cells = game.map_size.x * game.map_size.y
	if cells.size() < expected_cells:
		return
	var mask_started = Time.get_ticks_usec() if probe != null else 0
	game._ensure_fog_slope_neighbor_cache()
	var change: Dictionary = {"full": true, "exact": false, "cells": [], "stamp": {}}
	if game.simulation_world != null and game.simulation_world.has_method("cache_changes"):
		change = CacheDependency.changes(game.simulation_world, CacheDependency.FOG_VISIBILITY, cached_world_fog_stamp, game.local_player_team)
	var full_refresh: bool = cached_world_fog_texture == null or cached_world_fog_texture_data.size() != expected_cells * 4 or cached_world_fog_texture_revision < 0 or bool(change["full"]) or not bool(change["exact"])
	var affected: Dictionary = {}
	if full_refresh:
		cached_world_fog_texture_data.resize(expected_cells * 4)
		for index in range(expected_cells):
			affected[index] = true
	else:
		for cell_value in change["cells"]:
			var cell = Vector2i(cell_value)
			for y_offset in range(-1, 2):
				for x_offset in range(-1, 2):
					var affected_cell = cell + Vector2i(x_offset, y_offset)
					if affected_cell.x >= 0 and affected_cell.y >= 0 and affected_cell.x < game.map_size.x and affected_cell.y < game.map_size.y:
						affected[affected_cell.y * game.map_size.x + affected_cell.x] = true
	cached_world_fog_stamp = change["stamp"]
	cached_world_fog_texture_revision = fog_revision
	# Keep the compatibility queue bounded. Independent caches use journals,
	# so consuming this queue no longer steals their invalidations.
	if game.simulation_world != null and game.simulation_world.has_method("consume_fog_presentation_dirty_cells"):
		game.simulation_world.consume_fog_presentation_dirty_cells(game.local_player_team)
	if affected.is_empty():
		return
	for cell_index_value in affected.keys():
		game._write_world_fog_pixel(int(cell_index_value), cells)
	var image = Image.create_from_data(game.map_size.x, game.map_size.y, false, Image.FORMAT_RGBA8, cached_world_fog_texture_data)
	if cached_world_fog_texture == null:
		cached_world_fog_texture = ImageTexture.create_from_image(image)
	else:
		cached_world_fog_texture.update(image)
	if probe != null:
		probe.observe_microseconds("presentation.fog.mask_update", Time.get_ticks_usec() - mask_started)
		probe.increment("presentation.fog.mask_cells_updated", affected.size())


func _write_world_fog_pixel(game, index: int, cells: Variant) -> void:
	var cell = Vector2i(index % game.map_size.x, index / game.map_size.x)
	var state = int(cells[index])
	var color = Color.TRANSPARENT
	if state != FogOfWar.VISIBLE and game._fog_cell_should_cover(cell, cells):
		color = FogPresentation.color_for_state(state)
	var byte_offset = index * 4
	cached_world_fog_texture_data[byte_offset] = clampi(roundi(color.r * 255.0), 0, 255)
	cached_world_fog_texture_data[byte_offset + 1] = clampi(roundi(color.g * 255.0), 0, 255)
	cached_world_fog_texture_data[byte_offset + 2] = clampi(roundi(color.b * 255.0), 0, 255)
	cached_world_fog_texture_data[byte_offset + 3] = clampi(roundi(color.a * 255.0), 0, 255)


func _world_to_fog_mesh(game, world: Vector2) -> Vector2:
	if game._render_terrain() != null:
		return game._render_terrain().terrain_elevation.world_to_screen(world, game.view_zoom, Vector2.ZERO)
	return Coordinates.world_to_screen(world, game.view_zoom, Vector2.ZERO)


func _fog_cell_should_cover(game, cell: Vector2i, cells: Variant) -> bool:
	var index = cell.y * game.map_size.x + cell.x
	if index < 0 or index >= cells.size() or int(cells[index]) == FogOfWar.VISIBLE:
		return false
	game._ensure_fog_slope_neighbor_cache()
	if index >= cached_fog_slope_neighbor_cells.size() or int(cached_fog_slope_neighbor_cells[index]) == 0:
		return true
	if game._fog_cell_touches_visible(cell, cells):
		return false
	return true


func _fog_cell_touches_visible(game, cell: Vector2i, cells: Variant) -> bool:
	for y_offset in range(-1, 2):
		for x_offset in range(-1, 2):
			if x_offset == 0 and y_offset == 0:
				continue
			if game._fog_state_at_cell(cells, cell + Vector2i(x_offset, y_offset)) == FogOfWar.VISIBLE:
				return true
	return false


func _fog_state_at_cell(game, cells: Variant, cell: Vector2i) -> int:
	if cell.x < 0 or cell.y < 0 or cell.x >= game.map_size.x or cell.y >= game.map_size.y:
		return FogOfWar.UNKNOWN
	var index = cell.y * game.map_size.x + cell.x
	if index < 0 or index >= cells.size():
		return FogOfWar.UNKNOWN
	return int(cells[index])


func _ensure_fog_slope_neighbor_cache(game) -> void:
	var expected_size = game.map_size.x * game.map_size.y
	if game._render_terrain() == null or cached_fog_slope_neighbor_cells.size() == expected_size:
		return
	cached_fog_slope_neighbor_cells.resize(expected_size)
	for y in range(game.map_size.y):
		for x in range(game.map_size.x):
			var cell = Vector2i(x, y)
			var profile: Dictionary = game._render_terrain().terrain_elevation.cell_profile(cell)
			var uses_slope_art = int(profile.get("slope_index", 0)) > 0 or not bool(profile.get("is_valid", true))
			if uses_slope_art:
				for y_offset in range(-1, 2):
					for x_offset in range(-1, 2):
						var neighbor = cell + Vector2i(x_offset, y_offset)
						if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < game.map_size.x and neighbor.y < game.map_size.y:
							cached_fog_slope_neighbor_cells[neighbor.y * game.map_size.x + neighbor.x] = 1


func _expanded_tile_bounds(game, bounds: Rect2i, margin: int) -> Rect2i:
	var start = Vector2i(maxi(0, bounds.position.x - margin), maxi(0, bounds.position.y - margin))
	var finish = Vector2i(mini(game.map_size.x, bounds.end.x + margin), mini(game.map_size.y, bounds.end.y + margin))
	return Rect2i(start, finish - start)


func _tile_bounds_contains(game, outer: Rect2i, inner: Rect2i) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


func draw_map_edge_guard(game) -> void:
	var terrain_revision = game._terrain_geometry_revision()
	if cached_map_edge_chains.is_empty() or not is_equal_approx(cached_map_edge_zoom, game.view_zoom) or cached_map_edge_terrain_revision != terrain_revision:
		cached_map_edge_chains = FogPresentation.map_edge_guard_chains(game.map_size, Callable(game, "_world_to_fog_mesh"))
		cached_map_edge_zoom = game.view_zoom
		cached_map_edge_terrain_revision = terrain_revision
	game.draw_set_transform(PixelScaling.snap_screen(game.view_offset))
	for chain in cached_map_edge_chains:
		if chain.size() >= 2:
			# A two-pixel centered stroke covers the one shared texel outside either
			# rasterized edge orientation while consuming at most one pixel inside.
			game.draw_polyline(chain, Color.BLACK, maxf(2.0, game.view_zoom * 2.0), false)
	game.draw_set_transform(Vector2.ZERO)


func fog_runs(game) -> Array:
	var revision = int(game.presentation_snapshot.get("fog_revision", -1))
	if revision != cached_fog_revision:
		var fog_cells: Variant = game.presentation_snapshot.get("fog", {}).get("cells", [])
		cached_fog_runs = ViewportCulling.fog_runs(fog_cells, game.map_size, FogOfWar.VISIBLE)
		cached_fog_revision = revision
	return cached_fog_runs


func draw_map_edge_fog_overlay(game) -> void:
	# Crowns can project outside the finite terrain mesh. Continue the boundary
	# cell's fog there, without tinting the black void or drawing across sprites.
	if game._render_terrain() == null or cached_world_fog_texture == null:
		return
	if cached_map_edge_fog_revision != game._terrain_geometry_revision():
		cached_map_edge_fog_meshes.clear()
		cached_map_edge_fog_revision = game._terrain_geometry_revision()
	var visible = game.visible_tile_bounds()
	var skirt = 6
	var regions = {
		"top": Rect2i(-skirt, -skirt, game.map_size.x + skirt * 2, skirt),
		"bottom": Rect2i(-skirt, game.map_size.y, game.map_size.x + skirt * 2, skirt),
		"left": Rect2i(-skirt, 0, skirt, game.map_size.y),
		"right": Rect2i(game.map_size.x, 0, skirt, game.map_size.y),
	}
	var needed = []
	if visible.position.y < skirt: needed.append("top")
	if visible.end.y > game.map_size.y - skirt: needed.append("bottom")
	if visible.position.x < skirt: needed.append("left")
	if visible.end.x > game.map_size.x - skirt: needed.append("right")
	game.draw_set_transform(PixelScaling.snap_screen(game.view_offset), 0.0, Vector2(game.view_zoom, game.view_zoom))
	for edge in needed:
		if not cached_map_edge_fog_meshes.has(edge):
			cached_map_edge_fog_meshes[edge] = game._build_world_fog_mesh(regions[edge])
		game.draw_mesh(cached_map_edge_fog_meshes[edge], cached_world_fog_texture, Transform2D.IDENTITY, Color.BLACK)
	game.draw_set_transform(Vector2.ZERO)


func _reset_world_fog_cache(game) -> void:
	cached_fog_revision = -1
	cached_fog_runs.clear()
	cached_world_fog_meshes.clear()
	cached_world_fog_mesh_terrain_revision = -1
	cached_world_fog_texture = null
	cached_world_fog_texture_data.resize(0)
	cached_world_fog_texture_revision = -1
