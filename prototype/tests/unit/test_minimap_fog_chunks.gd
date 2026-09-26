extends SceneTree

const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const MinimapProjection := preload("res://scripts/minimap_projection.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 752)
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	viewport.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.queue_redraw()
	await process_frame
	var original_mesh: ArrayMesh = game.cached_minimap_mesh
	var original_terrain: ImageTexture = game.cached_minimap_terrain_texture
	var original_fog: ImageTexture = game.cached_minimap_fog_texture
	assert_true(original_mesh != null, "minimap builds its resource and entity mesh")
	assert_true(original_terrain != null, "minimap builds a bounded terrain raster")
	assert_true(original_fog != null, "minimap builds a bounded fog overlay")
	var geometry: Dictionary = game.minimap_geometry()
	var rectangle: Rect2 = geometry["rectangle"]
	var sample_screen := MinimapProjection.world_to_minimap(Vector2(game.map_size) * 0.5, geometry["center"], geometry["scale"])
	var sample := Vector2i(sample_screen - rectangle.position)
	var fog := PackedByteArray()
	fog.resize(game.map_size.x * game.map_size.y)
	fog.fill(FogOfWar.UNKNOWN)
	game.presentation_snapshot["fog"] = {"cells": fog}
	game.presentation_snapshot["fog_revision"] = int(game.presentation_snapshot.get("fog_revision", 0)) + 1
	game.presentation_snapshot["fog_exploration_revision"] = int(game.presentation_snapshot.get("fog_exploration_revision", 0)) + 1
	game.queue_redraw()
	await process_frame
	assert_true(game.cached_minimap_mesh == original_mesh, "fog changes do not rebuild the static overview mesh")
	assert_true(game.cached_minimap_terrain_texture == original_terrain, "fog changes do not invalidate minimap terrain")
	assert_true(game.cached_minimap_fog_texture == original_fog, "fog revisions update the existing overlay texture")
	assert_true(game.cached_minimap_fog_texture.get_image().get_pixelv(sample).a > 0.99, "unknown map cells are black on the minimap")
	fog.fill(FogOfWar.EXPLORED)
	game.presentation_snapshot["fog"] = {"cells": fog}
	game.presentation_snapshot["fog_revision"] = int(game.presentation_snapshot["fog_revision"]) + 1
	game.presentation_snapshot["fog_exploration_revision"] = int(game.presentation_snapshot["fog_exploration_revision"]) + 1
	game.queue_redraw()
	await process_frame
	var explored_alpha := game.cached_minimap_fog_texture.get_image().get_pixelv(sample).a
	assert_true(explored_alpha > 0.5 and explored_alpha < 0.7, "explored map cells remain dimmed")
	var exploration_revision := game.cached_minimap_exploration_revision
	fog.fill(FogOfWar.VISIBLE)
	game.presentation_snapshot["fog"] = {"cells": fog}
	game.presentation_snapshot["fog_revision"] = int(game.presentation_snapshot["fog_revision"]) + 1
	game.queue_redraw()
	await process_frame
	assert_true(game.cached_minimap_exploration_revision == exploration_revision, "visibility-only changes do not rebuild the minimap overlay")
	assert_true(absf(game.cached_minimap_fog_texture.get_image().get_pixelv(sample).a - explored_alpha) < 0.01, "visible and explored cells look the same on the minimap")
	game.free()
	if failures.is_empty():
		print("Minimap fog rendering passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append(context)
