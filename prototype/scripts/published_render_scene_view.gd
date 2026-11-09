extends RefCounted
## Main-thread camera queries over one immutable, legally observed generation.
## No world, controller, source cache, or owner-thread index is retained here.
const CHUNK_SIZE := 8
const Contract := preload("res://scripts/entity_read_contract.gd")
var scene: Dictionary = {}
var kernel = ClassDB.instantiate("RoRReadModelKernel") if ClassDB.class_exists("RoRReadModelKernel") else null
var cached_chunks: Dictionary = {}
var cached_bounds := Rect2i()
var cached_resources: Array = []
var queries := 0
var resource_queries := 0
var unit_metadata: Dictionary = {}
var prediction_limits: Dictionary = {}
var has_prediction_limits := false

func clear() -> void:
	scene = {}
	cached_chunks = {}
	cached_bounds = Rect2i()
	cached_resources = []
	unit_metadata.clear()
	prediction_limits = {}
	has_prediction_limits = false

func adopt(value: Dictionary, limits: Variant = null) -> void:
	scene = value
	has_prediction_limits = limits is Dictionary
	prediction_limits = limits if has_prediction_limits else {}
	unit_metadata.clear()
	if bool(scene.get("split_unit_metadata", false)):
		for row in scene["units"]: unit_metadata[int(row["id"])] = row

func select(bounds: Rect2i, selected_ids: Array) -> Dictionary:
	if scene.is_empty(): return {}
	queries += 1
	var selected := {}
	for id in selected_ids: selected[int(id)] = true
	var result := scene.duplicate()
	var rectangle := Rect2(Vector2(bounds.position), Vector2(bounds.size))
	for category in ["units", "buildings"]:
		var rows: Array = []
		var controls: Array = []
		var source_rows: Array = scene["render_units"] if category == "units" and bool(scene.get("split_unit_metadata", false)) else scene[category]
		for row in source_rows:
			var id: int = row["id"]
			var chosen := selected.has(id)
			if chosen or rectangle.has_point(Vector2(row["pos"])):
				var presented: Dictionary = row
				if category == "units" and (prediction_limits.has(id) or (chosen and unit_metadata.has(id))):
					presented = row.duplicate()
					if chosen and unit_metadata.has(id):
						presented.merge(unit_metadata[id], true)
						Contract.redact_foreign_control(presented, int(scene["observer_team"]))
					if prediction_limits.has(id): presented["render_prediction_alpha_limit"] = prediction_limits[id]
				rows.append(presented)
				if chosen: controls.append(presented)
		result[category] = rows
		result["control_" + category] = controls
	var chunks: Dictionary = scene["resource_chunks"]
	if bounds != cached_bounds or not is_same(chunks, cached_chunks):
		resource_queries += 1
		cached_resources = _resources(chunks, bounds)
		cached_bounds = bounds
		cached_chunks = chunks
	result["resources"] = cached_resources
	var control_resources: Array = []
	for row in cached_resources:
		if selected.has(int(row["id"])): control_resources.append(row)
	result["control_resources"] = control_resources
	result["resource_delta"] = {}
	result.erase("resource_chunks")
	result.erase("render_units")
	result.erase("split_unit_metadata")
	return result

func _resources(chunks: Dictionary, bounds: Rect2i) -> Array:
	if kernel != null:
		return kernel.known_resources_in_bounds({}, chunks, bounds, CHUNK_SIZE)
	var rows: Array = []
	if bounds.size.x <= 0 or bounds.size.y <= 0: return rows
	var first := Vector2i(floori(float(bounds.position.x) / CHUNK_SIZE), floori(float(bounds.position.y) / CHUNK_SIZE))
	var last := Vector2i(floori(float(bounds.end.x - 1) / CHUNK_SIZE), floori(float(bounds.end.y - 1) / CHUNK_SIZE))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for row in chunks.get(Vector2i(x, y), []):
				if bounds.has_point(Vector2i(Vector2(row["pos"]).floor())): rows.append(row)
	rows.sort_custom(func(a, b): return int(a["id"]) < int(b["id"]))
	rows.make_read_only()
	return rows
