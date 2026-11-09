extends RefCounted
# One map generation owns all full-detail ground chunks. Camera changes only
# select already installed geometry; workers receive detached numeric requests.
const Pixels := preload("res://scripts/pixel_scaling.gd")
const MeshJob := preload("res://scripts/native_terrain_mesh.gd")
# Full-width rows retain the kernel's original y/x triangle order, including
# overlapping slopes. A camera only selects complete, previously built rows.
const ROW_HEIGHT := 1
const MAX_JOBS := 2
var size := Vector2i.ZERO
var records: Dictionary = {}
var queued: Array[Vector2i] = []
var running: Array[Dictionary] = []
var staged: Dictionary = {}
var generation := 0
var ready := false
var failed := false
var started_us := 0
var preparation_us := 0
var vertices := 0
var buffer_bytes := 0
var completed_jobs := 0
var discarded_transparent_triangles := 0
var avoided_vertices := 0
var visible_chunks := 0
var visible_meshes := 0
var visible_vertices := 0

func begin(canvas) -> void:
	shutdown(canvas)
	size = canvas.map_size
	started_us = Time.get_ticks_usec()
	invalidate(null, canvas)

func invalidate(cells: Variant, canvas) -> void:
	generation += 1
	# A second terrain edit must not discard unfinished rows from the previous
	# publication, especially during initial scene preparation.
	var keys: Dictionary = {}
	for key in queued: keys[key] = true
	for entry in running: keys[entry["key"]] = true
	for key in staged: keys[key] = true
	if not ready:
		for y in range(size.y):
			if not records.has(Vector2i(0,y)): keys[Vector2i(0,y)] = true
	queued.clear()
	for record in staged.values(): canvas.retired_meshes.append_array(record["meshes"])
	staged.clear()
	if cells is Array:
		for value in cells:
			var cell := Vector2i(value)
			# Material/height blends also depend on adjacent rows.
			for y in range(maxi(0, cell.y-1), mini(size.y-1, cell.y+1)+1): keys[Vector2i(0,y)] = true
	else:
		for y in range(size.y): keys[Vector2i(0,y)] = true
	queued.assign(keys.keys())
	queued.sort_custom(func(a,b): return a.y < b.y if a.y != b.y else a.x < b.x)

func pending() -> bool:
	return not failed and (not queued.is_empty() or not running.is_empty() or not staged.is_empty())

func fraction() -> float:
	var count := size.y
	return 1.0 if ready else float(staged.size())/maxi(1,count)

func poll(canvas) -> void:
	if failed: return
	var started := Time.get_ticks_usec()
	var uploads := 0
	# The same2ms budget; loading can use more small uploads within it.
	var upload_limit: int = 8 if not ready else canvas.MAX_UPLOADS_PER_FRAME
	for entry in running.duplicate():
		var job = entry["job"]
		if int(entry["id"]) >= 0:
			if not WorkerThreadPool.is_task_completed(int(entry["id"])): continue
			WorkerThreadPool.wait_for_task_completion(int(entry["id"]))
			entry["id"] = -1
			if job.result_chunks.is_empty() and not job.result.is_empty(): job.result_chunks = [job.result]; job.result = []
			job.request = {}
		if int(entry["generation"]) != generation:
			canvas._retire_cpu_arrays(job.result_chunks)
			canvas.retired_meshes.append_array(entry["meshes"])
			running.erase(entry)
			continue
		if job.result_chunks.is_empty():
			if bool(job.timings.get("valid_empty_geometry", false)):
				staged[entry["key"]] = {"bounds":entry["bounds"],"meshes":[],"mesh_bounds":[],"mesh_vertices":[],"vertices":0,"bytes":0}
				completed_jobs += 1
				running.erase(entry)
				continue
			else:
				failed = true
				push_error("Prepared terrain chunk produced no geometry")
				return
		while int(entry["cursor"]) < job.result_chunks.size() and uploads < upload_limit:
			var arrays: Array = job.result_chunks[int(entry["cursor"])]
			var mesh := ArrayMesh.new()
			var upload_started := Time.get_ticks_usec()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			canvas.peak_chunk_upload_us = maxi(canvas.peak_chunk_upload_us, Time.get_ticks_usec()-upload_started)
			entry["vertices"] += arrays[Mesh.ARRAY_VERTEX].size()
			entry["bytes"] += arrays[Mesh.ARRAY_VERTEX].size()*12 + arrays[Mesh.ARRAY_TEX_UV].size()*8 + arrays[Mesh.ARRAY_COLOR].size()*16 + arrays[Mesh.ARRAY_INDEX].size()*4
			entry["meshes"].append(mesh)
			var box := mesh.get_aabb()
			entry["mesh_bounds"].append(Rect2(Vector2(box.position.x,box.position.y),Vector2(box.size.x,box.size.y)))
			entry["mesh_vertices"].append(arrays[Mesh.ARRAY_VERTEX].size())
			job.result_chunks[int(entry["cursor"])] = null
			canvas._retire_cpu_arrays([arrays])
			entry["cursor"] += 1
			uploads += 1
			if Time.get_ticks_usec()-started >= canvas.UPLOAD_BUDGET_USEC: break
		if int(entry["cursor"]) == job.result_chunks.size():
			staged[entry["key"]] = {"bounds":entry["bounds"],"meshes":entry["meshes"],"mesh_bounds":entry["mesh_bounds"],"mesh_vertices":entry["mesh_vertices"],"vertices":entry["vertices"],"bytes":entry["bytes"]}
			discarded_transparent_triangles += int(job.timings.get("discarded_transparent_triangles",0))
			avoided_vertices += int(job.timings.get("avoided_vertices",0))
			completed_jobs += 1
			running.erase(entry)
		if uploads >= upload_limit or Time.get_ticks_usec()-started >= canvas.UPLOAD_BUDGET_USEC: break
	if running.size() < MAX_JOBS and not queued.is_empty() and Time.get_ticks_usec()-started < canvas.UPLOAD_BUDGET_USEC:
		var key: Vector2i = queued.pop_front()
		var bounds := Rect2i(Vector2i(0,key.y), Vector2i(size.x,ROW_HEIGHT)).intersection(Rect2i(Vector2i.ZERO,size))
		var job := MeshJob.new()
		job.kernel = canvas.native_kernel
		job.request = MeshJob.capture(bounds, canvas.map_seed, canvas.terrain_id_provider, canvas.simulation_world.terrain_elevation, canvas.resource_catalog.environment_pack, canvas.terrain_atlas_regions, canvas.terrain_atlas_size, {}, {}, canvas.native_kernel)
		# The same final 8x8 blends /16x16 coasts as the original detailed mesh.
		job.subdivisions = 16
		job.split_result = true
		var id := WorkerThreadPool.add_task(Callable(job,"run"), false, "Prepare map terrain chunk")
		running.append({"id":id,"job":job,"generation":generation,"key":key,"bounds":bounds,"cursor":0,"meshes":[],"mesh_bounds":[],"mesh_vertices":[],"vertices":0,"bytes":0})
	if queued.is_empty() and running.is_empty() and not staged.is_empty():
		# Publish a changed set together; no partially updated seam is displayed.
		for key in staged:
			if records.has(key):
				canvas.retired_meshes.append_array(records[key]["meshes"])
				vertices -= int(records[key]["vertices"]); buffer_bytes -= int(records[key]["bytes"])
			records[key] = staged[key]
			vertices += int(staged[key]["vertices"]); buffer_bytes += int(staged[key]["bytes"])
		staged.clear()
		if not ready:
			ready = true
			preparation_us = Time.get_ticks_usec()-started_us
			canvas._retire_current_meshes()
			canvas.terrain_mesh = null
			canvas._retire_coverage_mesh()
		canvas.queue_redraw()

func draw(canvas, bounds: Rect2i) -> void:
	visible_chunks = 0; visible_meshes = 0; visible_vertices = 0
	var clip := Rect2(-Pixels.snap_screen(canvas.view_offset)/canvas.view_zoom,canvas.viewport_size/canvas.view_zoom).grow(1.0/canvas.view_zoom)
	if bounds.size == Vector2i.ZERO: return
	for y in range(maxi(0,bounds.position.y), mini(size.y,bounds.end.y)):
		var record: Dictionary = records.get(Vector2i(0,y),{})
		if record.is_empty(): continue
		visible_chunks += 1
		for index in range(record["meshes"].size()):
			if not clip.intersects(record["mesh_bounds"][index],true): continue
			visible_meshes += 1
			visible_vertices += int(record["mesh_vertices"][index])
			canvas.draw_mesh(record["meshes"][index], canvas.terrain_atlas)

func shutdown(canvas) -> void:
	for entry in running:
		if int(entry["id"]) >= 0: WorkerThreadPool.wait_for_task_completion(int(entry["id"]))
		canvas._retire_cpu_arrays(entry["job"].result_chunks)
		canvas.retired_meshes.append_array(entry["meshes"])
	for record in records.values(): canvas.retired_meshes.append_array(record["meshes"])
	for record in staged.values(): canvas.retired_meshes.append_array(record["meshes"])
	running.clear(); queued.clear(); records.clear(); staged.clear()
	ready = false; failed = false; vertices = 0; buffer_bytes = 0
