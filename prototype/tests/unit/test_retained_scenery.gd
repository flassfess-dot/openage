extends SceneTree
const Renderer := preload("res://scripts/render_world.gd")
const Item := preload("res://scripts/render_item.gd")
const Field := preload("res://scripts/environment_presentation_field.gd")
var failures: Array[String] = []
var resolved := 0
var camera := Vector2.ZERO
func _initialize() -> void:
	test_retained_scenery()
	test_spatial_query()
	for failure in failures: push_error(failure)
	print("Retained scenery and pan performance regression: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func test_retained_scenery() -> void:
	var renderer = Renderer.new()
	var environment: Array = []
	for index in range(400): environment.append({"id": index + 1, "position": Vector2(index % 20, int(index / 20)), "asset_name": "stone", "source_frame": 0})
	var snapshot := {"environment": environment, "environment_revision": 1, "buildings": [{"id": 800, "hp": 100, "pos": Vector2(9, 9), "team": 1}], "resources": [{"id": 801, "amount": 50, "pos": Vector2(10, 10)}]}
	var drawables: Array = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 400, "initial scenery resolves once")
	for tick in range(20):
		camera = Vector2(tick * 2, tick * 3)
		drawables = renderer.create_world_drawables(snapshot, project, 1, frame_info)
		assert_projection_and_order(drawables)
	check(resolved == 400, "fixed ticks and camera pan do not resolve unchanged scenery")
	# An effects-only projection must not destroy the full scene's cache.
	renderer.create_world_drawables({"effects": [{"id": 900, "pos": Vector2(4, 4)}]}, project, 1, frame_info)
	renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 400, "effects preserve retained scenery")
	environment = environment.slice(1)
	environment.append({"id": 401, "position": Vector2(21, 21), "asset_name": "stone", "source_frame": 0})
	snapshot["environment"] = environment
	snapshot["environment_revision"] = 2
	drawables = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 401, "entering the viewport resolves only the new object")
	check(renderer.cached_environment_records.size() == 400, "offscreen records are evicted")
	check(not renderer.cached_environment_records.has(1), "departed scenery is not retained")
	assert_projection_and_order(drawables)
	environment[0]["source_frame"] = 1
	snapshot["environment_revision"] = 3
	renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 402, "changed artwork invalidates only its own record")
	# Standalone snapshots without revisions still detect changes by content.
	snapshot.erase("environment_revision")
	environment[0]["asset_name"] = "gravel"
	renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 403, "unversioned snapshots detect artwork changes")
	snapshot["environment"] = []
	drawables = renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(not drawables.any(func(item): return item["kind"] == "environment"), "explicit empty scenery clears the view")
	check(renderer.cached_environment_records.is_empty(), "empty scenery clears retained records")
	renderer.clear_caches()
	snapshot["environment"] = environment
	renderer.create_world_drawables(snapshot, project, 1, frame_info)
	check(resolved == 803, "new match cache reset rebuilds all present scenery")
func test_spatial_query() -> void:
	var field = Field.new()
	field.configure([{ "id": 3, "position": Vector2(2, 2), "presentation_bounds": [-2,-2,2,2] }, { "id": 1, "position": Vector2.ONE }, { "id": 2, "position": Vector2(9, 9) }])
	var result: Array = field.query(Rect2i(0, 0, 4, 4))
	check(result.map(func(item): return item["id"]) == [1,3], "query deduplicates overlapping cells and keeps deterministic ID order")
func frame_info(kind: String, data: Dictionary) -> Dictionary:
	if kind == "environment": resolved += 1
	return {"frame_index": int(data.get("source_frame", 0))}
func project(position: Vector2) -> Vector2: return position * 10 + camera
func assert_projection_and_order(drawables: Array) -> void:
	for index in range(drawables.size()):
		var drawable: Dictionary = drawables[index]
		check(drawable["screen_position"] == project(drawable["world_anchor"]), "statics stay attached to the world when panning")
		if index > 0: check(not Item.less(drawable, drawables[index-1]), "retained and new items preserve depth order")
func check(value: bool, description: String) -> void:
	if not value and not failures.has(description): failures.append(description)