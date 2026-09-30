extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Canvas := preload("res://scripts/terrain_canvas.gd")
const NativeMesh := preload("res://scripts/native_terrain_mesh.gd")
const Terrain := preload("res://scripts/environment_terrain.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	check(ClassDB.class_exists("RoRTerrainKernel"), "native terrain kernel is packaged")
	if not failures.is_empty(): finish(); return
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "mixed terrain assets load")
	if not failures.is_empty(): finish(); return
	var canvas := Canvas.new()
	canvas.resource_catalog = catalog
	canvas._build_terrain_atlas()
	var kernel = ClassDB.instantiate("RoRTerrainKernel")
	var elevation := Elevation.new(Vector2i(400, 400))
	for material in [0, 1, 4, 6, 22, 1000, 1001]:
		compare_patch("uniform %d" % material, Rect2i(190, 190, 2, 2), func(_cell): return material, elevation, canvas, kernel, 41721)
	var coast := func(cell):
		if cell.x < 0 or cell.y < 0 or cell.x > 399 or cell.y > 399: return -1
		return [1, 4, 22, 0, 6, 1000, 1001][posmod(cell.x * 7 + cell.y * 3, 7)]
	compare_patch("coast and junctions", Rect2i(190, 190, 4, 4), coast, elevation, canvas, kernel, 41689)
	compare_patch("map boundary", Rect2i(0, 0, 3, 3), coast, elevation, canvas, kernel, 2147483647)
	for y in range(190, 196):
		for x in range(190, 196): elevation.set_vertex(Vector2i(x, y), posmod(x + y, 3))
	compare_patch("slopes and imported materials", Rect2i(190, 190, 4, 4), coast, elevation, canvas, kernel, 4172126579)
	check(kernel.build_mesh(Rect2i(0, 0, 2, 2), PackedInt32Array(), PackedFloat32Array(), PackedInt32Array(), PackedFloat32Array(), 1).is_empty(), "malformed mesh input is rejected")
	canvas.free()
	finish()

func compare_patch(label: String, bounds: Rect2i, provider: Callable, elevation, canvas, kernel, seed: int) -> void:
	var actual := NativeMesh.build_arrays(kernel, bounds, seed, provider, elevation, canvas.resource_catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size)
	check(not actual.is_empty(), label + " builds native arrays")
	if actual.is_empty(): return
	var points := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var cell := Vector2i(x, y)
			var drawable := Terrain.tile_drawable(cell, int(provider.call(cell)), provider, canvas.resource_catalog, elevation, 1.0, Vector2.ZERO, seed)
			for layer in drawable["mesh_layers"]: canvas._append_material_layer(points, uvs, indices, colors, layer)
	check(actual[Mesh.ARRAY_INDEX] == indices, label + " preserves tessellation and triangle order")
	check(actual[Mesh.ARRAY_VERTEX].size() == points.size(), label + " preserves vertex count")
	if actual[Mesh.ARRAY_VERTEX].size() != points.size(): return
	var position_error := 0.0
	var uv_error := 0.0
	var color_error := 0.0
	for i in range(points.size()):
		position_error = maxf(position_error, points[i].distance_to(actual[Mesh.ARRAY_VERTEX][i]))
		uv_error = maxf(uv_error, uvs[i].distance_to(actual[Mesh.ARRAY_TEX_UV][i]))
		var diff: Color = colors[i] - actual[Mesh.ARRAY_COLOR][i]
		color_error = maxf(color_error, maxf(absf(diff.r), maxf(absf(diff.g), maxf(absf(diff.b), absf(diff.a)))))
	check(position_error < 0.001, "%s elevation geometry error %.8f" % [label, position_error])
	check(uv_error < 0.000002, "%s texture coordinates error %.8f" % [label, uv_error])
	check(color_error < 0.00005, "%s coast blending and lighting error %.8f" % [label, color_error])

func check(value: bool, context: String) -> void:
	if not value: failures.append(context)

func finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Native terrain geometry matches reference: materials, coasts, seams, map boundaries and slopes")
	quit(0 if failures.is_empty() else 1)
