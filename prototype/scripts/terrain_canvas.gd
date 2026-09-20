class_name RoRTerrainCanvas
extends Node2D

const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")
const MESH_OVERSCAN_CELLS := 12

var map_size := Vector2i.ONE
var map_seed := 1
var resource_catalog
var simulation_world
var terrain_id_provider: Callable
var bounds_provider: Callable
var view_zoom := 1.0
var view_offset := Vector2.ZERO
var viewport_size := Vector2.ZERO
var terrain_revision := -1
var terrain_atlas: Texture2D
var terrain_atlas_size := Vector2.ZERO
var terrain_atlas_regions: Dictionary = {}
var terrain_mesh: ArrayMesh
var terrain_mesh_bounds := Rect2i()


func configure(size: Vector2i, seed: int, catalog, world, id_provider: Callable, visible_bounds_provider: Callable) -> void:
	map_size = size
	map_seed = seed
	resource_catalog = catalog
	simulation_world = world
	terrain_id_provider = id_provider
	bounds_provider = visible_bounds_provider
	_build_terrain_atlas()
	_rebuild_terrain_mesh()
	queue_redraw()


func set_view_state(zoom: float, offset: Vector2, next_viewport_size: Vector2, next_terrain_revision: int) -> void:
	var projection_changed := not is_equal_approx(view_zoom, zoom) or terrain_revision != next_terrain_revision
	var view_changed := projection_changed or not view_offset.is_equal_approx(offset) or not viewport_size.is_equal_approx(next_viewport_size)
	if not view_changed:
		return
	view_zoom = zoom
	view_offset = offset
	viewport_size = next_viewport_size
	terrain_revision = next_terrain_revision
	var visible_bounds: Rect2i = bounds_provider.call() if bounds_provider.is_valid() else Rect2i()
	if projection_changed or terrain_mesh == null or not _bounds_contains(terrain_mesh_bounds, visible_bounds):
		_rebuild_terrain_mesh()
	queue_redraw()


func invalidate_content() -> void:
	_rebuild_terrain_mesh()
	queue_redraw()


func _draw() -> void:
	# RoR's space outside the finite isometric map is opaque black. Keeping a
	# separate blue-gray canvas behind the map exposes colored wedges whenever
	# fog/terrain end at different projected edges.
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color.BLACK, true)
	if resource_catalog == null or simulation_world == null or not terrain_id_provider.is_valid() or not bounds_provider.is_valid():
		return
	if terrain_mesh != null and terrain_atlas != null:
		draw_set_transform(PixelScaling.snap_screen(view_offset))
		draw_mesh(terrain_mesh, terrain_atlas)
		draw_set_transform(Vector2.ZERO)
		return
	_draw_terrain_fallback()


func _draw_terrain_fallback() -> void:
	var bounds: Rect2i = bounds_provider.call()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var terrain_id := int(terrain_id_provider.call(cell))
			var drawable := TerrainRenderer.tile_drawable(cell, terrain_id, terrain_id_provider, resource_catalog, simulation_world.terrain_elevation, view_zoom, view_offset, map_seed)
			if drawable.is_empty():
				continue
			var underlay: Variant = drawable.get("underlay")
			if underlay is Dictionary:
				draw_texture_rect(underlay["texture"], Rect2(PixelScaling.snap_screen(underlay["position"]), underlay["size"]), false)
			draw_texture_rect(drawable["texture"], Rect2(PixelScaling.snap_screen(drawable["position"]), drawable["size"]), false)
			for layer_value in drawable["borders"]:
				_draw_terrain_border(drawable["position"], layer_value)


func _build_terrain_atlas() -> void:
	terrain_atlas = null
	terrain_atlas_regions.clear()
	if resource_catalog == null:
		return
	var textures: Array[Texture2D] = []
	var seen: Dictionary = {}
	for frames_value in resource_catalog.terrain_all_textures.values():
		for texture_value in frames_value:
			_append_unique_texture(textures, seen, texture_value)
	for frames_value in resource_catalog.terrain_border_textures.values():
		for texture_value in frames_value:
			_append_unique_texture(textures, seen, texture_value)
	if textures.is_empty():
		return
	var placements: Dictionary = {}
	var atlas_width := 2048
	var cursor := Vector2i(1, 1)
	var row_height := 0
	var required_height := 1
	for texture in textures:
		var size := Vector2i(texture.get_size())
		if cursor.x + size.x + 1 > atlas_width:
			cursor.x = 1
			cursor.y += row_height + 1
			row_height = 0
		placements[_texture_key(texture)] = Rect2i(cursor, size)
		cursor.x += size.x + 1
		row_height = maxi(row_height, size.y)
		required_height = maxi(required_height, cursor.y + row_height + 1)
	var atlas_height := _next_power_of_two(required_height)
	var image := Image.create(atlas_width, atlas_height, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for texture in textures:
		var source := texture.get_image()
		if source == null or source.is_empty():
			continue
		if source.get_format() != Image.FORMAT_RGBA8:
			source.convert(Image.FORMAT_RGBA8)
		var region: Rect2i = placements[_texture_key(texture)]
		image.blit_rect(source, Rect2i(Vector2i.ZERO, region.size), region.position)
	terrain_atlas = ImageTexture.create_from_image(image)
	terrain_atlas_size = Vector2(image.get_size())
	terrain_atlas_regions = placements


func _append_unique_texture(textures: Array[Texture2D], seen: Dictionary, value: Variant) -> void:
	if not value is Texture2D:
		return
	var texture: Texture2D = value
	var key := _texture_key(texture)
	if seen.has(key):
		return
	seen[key] = true
	textures.append(texture)


func _texture_key(texture: Texture2D) -> String:
	if not texture.resource_path.is_empty():
		return texture.resource_path
	return str(texture.get_rid())


func _next_power_of_two(value: int) -> int:
	var result := 1
	while result < value:
		result *= 2
	return result


func _rebuild_terrain_mesh() -> void:
	terrain_mesh = null
	terrain_mesh_bounds = Rect2i()
	if terrain_atlas == null or resource_catalog == null or simulation_world == null or not terrain_id_provider.is_valid() or not bounds_provider.is_valid():
		return
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var bounds := _expanded_bounds(bounds_provider.call(), MESH_OVERSCAN_CELLS)
	terrain_mesh_bounds = bounds
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var terrain_id := int(terrain_id_provider.call(cell))
			var drawable := TerrainRenderer.tile_drawable(cell, terrain_id, terrain_id_provider, resource_catalog, simulation_world.terrain_elevation, view_zoom, Vector2.ZERO, map_seed)
			if drawable.is_empty():
				continue
			var underlay: Variant = drawable.get("underlay")
			if underlay is Dictionary:
				_append_texture_quad(vertices, uvs, indices, underlay["texture"], PixelScaling.snap_screen(underlay["position"]), underlay["size"])
			_append_texture_quad(vertices, uvs, indices, drawable["texture"], PixelScaling.snap_screen(drawable["position"]), drawable["size"])
			for layer_value in drawable["borders"]:
				var layer: Dictionary = layer_value
				var texture: Texture2D = resource_catalog.get_terrain_border_texture(int(layer["border_id"]), int(layer["frame"]))
				if texture == null:
					continue
				var metadata: Dictionary = resource_catalog.get_texture_metadata(String(layer["asset_name"]), int(layer["frame"]))
				var hotspot := Vector2.ZERO
				if metadata.has("hotspot"):
					hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
				var position := PixelScaling.snap_screen(Vector2(drawable["position"]) - hotspot * view_zoom)
				_append_texture_quad(vertices, uvs, indices, texture, position, texture.get_size() * view_zoom)
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	terrain_mesh = ArrayMesh.new()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _expanded_bounds(bounds: Rect2i, margin: int) -> Rect2i:
	var start := Vector2i(maxi(0, bounds.position.x - margin), maxi(0, bounds.position.y - margin))
	var finish := Vector2i(mini(map_size.x, bounds.end.x + margin), mini(map_size.y, bounds.end.y + margin))
	return Rect2i(start, finish - start)


func _bounds_contains(outer: Rect2i, inner: Rect2i) -> bool:
	return (
		inner.position.x >= outer.position.x
		and inner.position.y >= outer.position.y
		and inner.end.x <= outer.end.x
		and inner.end.y <= outer.end.y
	)


func _append_texture_quad(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, texture: Texture2D, position: Vector2, size: Vector2) -> void:
	var region: Rect2i = terrain_atlas_regions.get(_texture_key(texture), Rect2i())
	if region.size == Vector2i.ZERO:
		return
	var first := vertices.size()
	vertices.append(Vector3(position.x, position.y, 0.0))
	vertices.append(Vector3(position.x + size.x, position.y, 0.0))
	vertices.append(Vector3(position.x + size.x, position.y + size.y, 0.0))
	vertices.append(Vector3(position.x, position.y + size.y, 0.0))
	var uv_min := Vector2(region.position) / terrain_atlas_size
	var uv_max := Vector2(region.end) / terrain_atlas_size
	uvs.append(uv_min)
	uvs.append(Vector2(uv_max.x, uv_min.y))
	uvs.append(uv_max)
	uvs.append(Vector2(uv_min.x, uv_max.y))
	indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))


func _draw_terrain_border(tile_origin: Vector2, layer: Dictionary) -> void:
	var border_id := int(layer["border_id"])
	var frame := int(layer["frame"])
	var texture: Texture2D = resource_catalog.get_terrain_border_texture(border_id, frame)
	if texture == null:
		return
	var metadata: Dictionary = resource_catalog.get_texture_metadata(String(layer["asset_name"]), frame)
	var hotspot := Vector2.ZERO
	if metadata.has("hotspot"):
		hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	var position := PixelScaling.snap_screen(tile_origin - hotspot * view_zoom)
	draw_texture_rect(texture, Rect2(position, texture.get_size() * view_zoom), false)
