extends SceneTree
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func grid(width: int, height: int) -> Array:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for y in range(height):
		for x in range(width):
			vertices.append(Vector3(x,y,(x+y)%4))
			uvs.append(Vector2(float(x)/width,float(y)/height))
			colors.append(Color(float(x%9)/9.0,float(y%7)/7.0,0.4,0.6))
	for y in range(height-1):
		for x in range(width-1):
			var p := y*width+x
			indices.append_array(PackedInt32Array([p,p+1,p+width+1,p,p+width+1,p+width]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
func _initialize() -> void:
	var kernel = ClassDB.instantiate("RoRTerrainKernel")
	if kernel == null or not kernel.has_method("split_mesh_arrays"): push_error("Current terrain chunk kernel is required");quit(1);return
	for limit in [3,2048,16384,65536]:
		var source := grid(3,3) if limit == 3 else grid(130,130)
		var chunks: Array = kernel.split_mesh_arrays(source,limit)
		check(not chunks.is_empty(),"valid terrain yields chunks")
		var cursor := 0
		var exact := true
		for chunk in chunks:
			check(chunk[Mesh.ARRAY_VERTEX].size() <= limit,"GPU upload vertex bound is enforced")
			for index in chunk[Mesh.ARRAY_INDEX]:
				var original: int = source[Mesh.ARRAY_INDEX][cursor]
				for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV]:
					exact = exact and chunk[channel][index] == source[channel][original]
				cursor += 1
		check(exact and cursor == source[Mesh.ARRAY_INDEX].size(),"chunking preserves every triangle and its exact position, UV and colour in order")
	var invalid := grid(3,3)
	invalid[Mesh.ARRAY_INDEX][0] = -1
	check(kernel.split_mesh_arrays(invalid,3).is_empty(),"invalid indices reject the complete result")
	check(kernel.split_mesh_arrays([],3).is_empty(),"invalid channel layout is rejected")
	for failure in failures: push_error(failure)
	print("Native terrain chunks: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
