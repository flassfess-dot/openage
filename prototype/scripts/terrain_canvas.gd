class_name RoRTerrainCanvas
extends Node2D

const TerrainRenderer := preload("res://scripts/terrain_renderer.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")

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


func configure(size: Vector2i, seed: int, catalog, world, id_provider: Callable, visible_bounds_provider: Callable) -> void:
	map_size = size
	map_seed = seed
	resource_catalog = catalog
	simulation_world = world
	terrain_id_provider = id_provider
	bounds_provider = visible_bounds_provider
	queue_redraw()


func set_view_state(zoom: float, offset: Vector2, next_viewport_size: Vector2, next_terrain_revision: int) -> void:
	if is_equal_approx(view_zoom, zoom) and view_offset.is_equal_approx(offset) and viewport_size.is_equal_approx(next_viewport_size) and terrain_revision == next_terrain_revision:
		return
	view_zoom = zoom
	view_offset = offset
	viewport_size = next_viewport_size
	terrain_revision = next_terrain_revision
	queue_redraw()


func _draw() -> void:
	# RoR's space outside the finite isometric map is opaque black. Keeping a
	# separate blue-gray canvas behind the map exposes colored wedges whenever
	# fog/terrain end at different projected edges.
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color.BLACK, true)
	if resource_catalog == null or simulation_world == null or not terrain_id_provider.is_valid() or not bounds_provider.is_valid():
		return
	var bounds: Rect2i = bounds_provider.call()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var terrain_id := int(terrain_id_provider.call(cell))
			var drawable := TerrainRenderer.tile_drawable(cell, terrain_id, terrain_id_provider, resource_catalog, simulation_world.terrain_elevation, view_zoom, view_offset, map_seed)
			if drawable.is_empty():
				continue
			draw_texture_rect(drawable["texture"], Rect2(PixelScaling.snap_screen(drawable["position"]), drawable["size"]), false)
			for layer_value in drawable["borders"]:
				_draw_terrain_border(drawable["position"], layer_value)


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
