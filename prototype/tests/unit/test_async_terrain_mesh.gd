extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Canvas := preload("res://scripts/terrain_canvas.gd")
const NativeMesh := preload("res://scripts/native_terrain_mesh.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not ClassDB.class_exists("RoRTerrainKernel"):
		check(false, "native terrain kernel is available")
		finish()
		return
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "mixed terrain pack loads")
	var canvas := Canvas.new()
	root.add_child(canvas)
	var elevation := Elevation.new(Vector2i(400, 400))
	var visible := [Rect2i(80, 80, 4, 4)]
	var content := [0]
	var provider := func(cell):
		if cell.x < 0 or cell.y < 0 or cell.x >= 400 or cell.y >= 400: return -1
		return [1, 4, 0, 1000][posmod(cell.x + cell.y + content[0], 4)]
	canvas.configure(Vector2i(400, 400), 41721, catalog, {"terrain_elevation": elevation}, provider, func(): return visible[0])
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(2560, 1080), 1)
	check(canvas.refinement_task_id >= 0, "camera update schedules refinement")
	visible[0] = Rect2i(200, 200, 4, 4)
	canvas.set_view_state(1.0, Vector2(100, 0), Vector2(2560, 1080), 1)
	visible[0] = Rect2i(320, 200, 4, 4)
	canvas.set_view_state(1.0, Vector2(200, 0), Vector2(2560, 1080), 1)
	check(canvas.terrain_mesh != null, "new camera view is drawable before worker completes")
	check(canvas.queued_refinement != null, "rapid camera changes replace the pending request")
	var latest_bounds: Rect2i = canvas.terrain_mesh_bounds
	await drain(canvas)
	check(canvas.terrain_mesh_bounds == latest_bounds, "old camera result never replaces the new bounds")
	check(canvas.last_mesh_build_metrics.has("refinement_us"), "latest camera request finishes at full detail")
	compare_full_mesh(canvas, provider, elevation, "rapid camera changes")

	# Explicit invalidation can change content without changing a world revision.
	# An already running job must not overwrite the fresh synchronous result.
	visible[0] = Rect2i(120, 260, 4, 4)
	canvas.set_view_state(1.0, Vector2(300, 0), Vector2(2560, 1080), 1)
	content[0] = 2
	canvas.invalidate_content()
	var fresh_mesh: ArrayMesh = canvas.terrain_mesh
	await drain(canvas)
	check(canvas.terrain_mesh == fresh_mesh, "explicit invalidation discards an older job at the same bounds and revision")
	compare_full_mesh(canvas, provider, elevation, "explicit invalidation")

	visible[0] = Rect2i(220, 100, 4, 4)
	canvas.set_view_state(1.0, Vector2(400, 0), Vector2(2560, 1080), 1)
	canvas.configure(Vector2i(400, 400), 2, catalog, {"terrain_elevation": elevation}, provider, func(): return visible[0])
	check(canvas.refinement_task_id < 0 and canvas.queued_refinement == null, "reconfigure joins and releases work from the previous world")
	canvas.set_view_state(1.0, Vector2(500, 0), Vector2(2560, 1080), 2)
	check(canvas.refinement_task_id >= 0, "exit test has an active worker")
	canvas.free()
	finish()

func drain(canvas) -> void:
	var deadline := Time.get_ticks_msec() + 10000
	while canvas.refinement_task_id >= 0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	check(canvas.refinement_task_id < 0, "worker completes within timeout")

func compare_full_mesh(canvas, provider: Callable, elevation, label: String) -> void:
	var arrays := NativeMesh.build_arrays(canvas.native_kernel, canvas.terrain_mesh_bounds, canvas.map_seed, provider, elevation, canvas.resource_catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size)
	var reference := ArrayMesh.new()
	reference.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var expected := reference.surface_get_arrays(0)
	var actual: Array = canvas.terrain_mesh.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		check(actual[channel] == expected[channel], "%s: exact full-detail channel %d" % [label, channel])

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func finish() -> void:
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Asynchronous terrain: rapid camera moves, exact refinement, invalidation, reconfigure and shutdown passed")
	quit(0 if failures.is_empty() else 1)
