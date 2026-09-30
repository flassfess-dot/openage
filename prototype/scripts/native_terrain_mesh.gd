class_name RoRNativeTerrainMesh
extends RefCounted

const Terrain := preload("res://scripts/environment_terrain.gd")
const TerrainRules := preload("res://scripts/terrain_rules.gd")

# Capture each terrain/height sample once, instead of crossing the script and
# dictionary boundary for every vertex of every material layer. The native
# kernel retains the reference's 8x8 blends and 16x16 coastline tessellation.
static func capture(bounds: Rect2i, seed: int, provider: Callable, elevation, pack, regions: Dictionary, atlas_size: Vector2, timings: Dictionary = {}) -> Dictionary:
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {}
	var started := Time.get_ticks_usec()
	var ids: Array = [0, 1, 4, 6, 22]
	for material_id in pack.materials_by_id:
		if material_id not in ids: ids.append(material_id)
	ids.sort()
	var slots: Dictionary = {}
	var materials := PackedFloat32Array()
	for id in ids:
		var imported: bool = pack.has_material(int(id))
		var texture: Texture2D = pack.material_texture(int(id)) if imported else pack.legacy_textures.get(id)
		if texture == null: return {}
		var key := texture.resource_path if not texture.resource_path.is_empty() else str(texture.get_rid())
		var region: Rect2i = regions.get(key, Rect2i())
		if region.size == Vector2i.ZERO: return {}
		slots[id] = slots.size()
		var uv_origin := Vector2(region.position) / atlas_size
		var uv_size := Vector2(region.size) / atlas_size
		materials.append_array(PackedFloat32Array([
			Terrain._priority(int(id), pack), 1.0 if id in [1, 4, 22] else 0.0,
			1.0 if imported else 0.0, uv_origin.x, uv_origin.y, uv_size.x, uv_size.y,
		]))
	var cells := PackedInt32Array()
	cells.resize((bounds.size.x + 2) * (bounds.size.y + 2))
	var index := 0
	for y in range(bounds.position.y - 1, bounds.end.y + 1):
		for x in range(bounds.position.x - 1, bounds.end.x + 1):
			var id := int(provider.call(Vector2i(x, y)))
			cells[index] = -1 if id < 0 else int(slots[Terrain._material_id(id, pack)])
			index += 1
	var heights := PackedFloat32Array()
	heights.resize((bounds.size.x + 1) * (bounds.size.y + 1))
	index = 0
	for y in range(bounds.position.y, bounds.end.y + 1):
		for x in range(bounds.position.x, bounds.end.x + 1):
			heights[index] = elevation.vertex_elevation(Vector2i(x, y))
			index += 1
	var frames := PackedInt32Array()
	frames.resize(bounds.size.x * bounds.size.y)
	index = 0
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			frames[index] = TerrainRules.tile_variant(Vector2i(x, y), "terrain", seed, 9)
			index += 1
	timings["capture_us"] = Time.get_ticks_usec() - started
	return {"bounds": bounds, "cells": cells, "heights": heights, "frames": frames, "materials": materials, "seed": seed}


static func build_arrays(kernel, bounds: Rect2i, seed: int, provider: Callable, elevation, pack, regions: Dictionary, atlas_size: Vector2, timings: Dictionary = {}) -> Array:
	return build_request(kernel, capture(bounds, seed, provider, elevation, pack, regions, atlas_size, timings), 16, timings)


static func build_request(kernel, request: Dictionary, subdivisions: int = 16, timings: Dictionary = {}) -> Array:
	if kernel == null or request.is_empty(): return []
	var started := Time.get_ticks_usec()
	var geometry: Dictionary = kernel.build_mesh(request["bounds"], request["cells"], request["heights"], request["frames"], request["materials"], request["seed"], subdivisions)
	timings["native_us"] = Time.get_ticks_usec() - started
	if geometry.is_empty() or geometry["vertices"].is_empty(): return []
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = geometry["vertices"]
	arrays[Mesh.ARRAY_TEX_UV] = geometry["uvs"]
	arrays[Mesh.ARRAY_COLOR] = geometry["colors"]
	arrays[Mesh.ARRAY_INDEX] = geometry["indices"]
	return arrays


# A worker owns its result until the main thread joins the completed task.
# Its input contains only detached numeric arrays, never the changing world.
var kernel: Variant
var request: Dictionary
var result: Array = []
var timings: Dictionary = {}

func run() -> void:
	result = build_request(kernel, request, 16, timings)
