extends SceneTree
const Canvas := preload("res://scripts/terrain_canvas.gd")
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func arrays() -> Array:
	var value: Array = []
	value.resize(Mesh.ARRAY_MAX)
	value[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	value[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP])
	value[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE])
	value[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2])
	return value
func state(canvas) -> Dictionary:
	return {"arrays":[arrays(),arrays(),arrays(),arrays(),arrays()],"meshes":[],"cursor":0,"generation":canvas.mesh_generation,"revision":canvas.terrain_revision,"bounds":canvas.terrain_mesh_bounds,"prefetch":false,"timings":{},"upload_us":0,"max_chunk_upload_us":0,"vertices":0}
func _initialize() -> void:
	var canvas := Canvas.new()
	root.add_child(canvas)
	canvas.terrain_mesh_bounds = Rect2i(0,0,1,1)
	canvas.bounds_provider = func(): return Rect2i(0,0,1,1)
	var old := ArrayMesh.new()
	old.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays())
	canvas.terrain_mesh = old
	canvas.refinement_upload = state(canvas)
	canvas._process(0.0)
	check(canvas.refinement_upload != null and canvas.refinement_upload["cursor"] <= Canvas.MAX_UPLOADS_PER_FRAME,"one frame uploads only its bounded number of parts")
	check(canvas.terrain_mesh == old and canvas.terrain_mesh_parts.is_empty(),"partially uploaded terrain never replaces the complete visible mesh")
	for _step in range(8):
		if canvas.refinement_upload == null: break
		canvas._process(0.0)
	check(canvas.refinement_upload == null and canvas.terrain_mesh_parts.size() == 5 and canvas.terrain_mesh != old,"all parts publish in one complete replacement")
	var visible: ArrayMesh = canvas.terrain_mesh
	canvas.refinement_upload = state(canvas)
	canvas.refinement_upload["generation"] -= 1
	canvas._process(0.0)
	check(canvas.refinement_upload == null and canvas.terrain_mesh == visible,"an older camera generation cannot publish staged GPU parts")
	canvas.refinement_upload = state(canvas)
	canvas.refinement_upload["revision"] -= 1
	canvas._process(0.0)
	check(canvas.refinement_upload == null and canvas.terrain_mesh == visible,"an older terrain revision cannot publish staged GPU parts")
	canvas.refinement_upload = state(canvas)
	canvas._process(0.0)
	canvas._finish_refinement()
	check(canvas.refinement_upload == null and canvas.retired_meshes.is_empty(),"shutdown cancels staged uploads and releases retired mesh references")
	canvas.free()
	for failure in failures: push_error(failure)
	print("Terrain upload batches: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
