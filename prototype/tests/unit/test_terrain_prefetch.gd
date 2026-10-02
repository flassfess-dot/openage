extends SceneTree
const Catalog := preload("res://scripts/resource_catalog.gd")
const Canvas := preload("res://scripts/terrain_canvas.gd")
const NativeMesh := preload("res://scripts/native_terrain_mesh.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
class FixtureWorld extends RefCounted:
	var terrain_elevation
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var catalog = Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "mixed surfaces load")
	var state := {"bounds": Rect2i(12, 12, 6, 6), "material": 0, "calls": 0}
	var provider := func(_cell):
		state["calls"] += 1
		return state["material"]
	var world := FixtureWorld.new()
	world.terrain_elevation = Elevation.new(Vector2i(64, 64))
	var canvas := Canvas.new()
	root.add_child(canvas)
	canvas.configure(Vector2i(64, 64), 41689, catalog, world, provider, func(): return state["bounds"])
	canvas.set_view_state(1, Vector2.ZERO, Vector2(1280, 720), -1)
	var cache: Dictionary = {}
	var first: Dictionary = NativeMesh.capture(Rect2i(12, 12, 6, 6), 41689, provider, world.terrain_elevation, catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size, {}, cache)
	var calls_before := int(state["calls"])
	var second: Dictionary = NativeMesh.capture(Rect2i(13, 12, 6, 6), 41689, provider, world.terrain_elevation, catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size, {}, cache)
	check(int(state["calls"]) - calls_before == 8, "one-cell pan samples only the entering terrain strip")
	check(cache["cells"].size() == 64 and cache["frames"].size() == 36, "numeric cache stays bounded by the current view")
	var uncached: Dictionary = NativeMesh.capture(Rect2i(13, 12, 6, 6), 41689, provider, world.terrain_elevation, catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size)
	check(second == uncached, "cached capture preserves exact materials, variants and heights")
	state["bounds"] = Rect2i(19, 12, 6, 6)
	var generation := canvas.mesh_generation
	var original_bounds := canvas.terrain_mesh_bounds
	var old_mesh: ArrayMesh = canvas.terrain_mesh
	canvas.set_view_state(1, Vector2(-128, 0), Vector2(1280, 720), -1)
	check(canvas.refinement_task_id >= 0 and canvas.refinement_prefetch, "approaching the edge starts background full-quality terrain")
	check(canvas.mesh_generation == generation and canvas.terrain_mesh == old_mesh, "prefetch keeps valid terrain without a foreground rebuild")
	for _frame in range(300):
		if canvas.refinement_task_id < 0: break
		await process_frame
	check(canvas.refinement_task_id < 0, "background terrain finishes")
	check(canvas.terrain_mesh_bounds != original_bounds and canvas._bounds_contains(canvas.terrain_mesh_bounds, state["bounds"]), "finished prefetch extends coverage before the camera exits")
	state["material"] = 6
	canvas.set_view_state(1, Vector2(-128, 0), Vector2(1280, 720), 1)
	var updated: Dictionary = NativeMesh.capture(canvas.terrain_mesh_bounds, 41689, provider, world.terrain_elevation, catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size)
	check(canvas.native_sample_cache["cells"].values().all(func(slot): return slot == updated["cells"][0]), "terrain revision invalidates cached samples")
	canvas.free()
	for failure in failures: push_error(failure)
	print("Terrain prefetch, exact samples and invalidation: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, description: String) -> void:
	if not value: failures.append(description)