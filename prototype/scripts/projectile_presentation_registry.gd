class_name RoRProjectilePresentationRegistry
extends RefCounted

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")
const ProjectileMotion := preload("res://scripts/projectile_motion.gd")

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var graphics_catalog: Dictionary = {}
var definitions: Dictionary = {}
var records_by_name: Dictionary = {}
var frames_by_source: Dictionary = {}
var descriptors_by_source: Dictionary = {}


func configure(runtime_data: Dictionary, object_data: Dictionary, graphics_data: Dictionary, asset_records: Array, indexed_frame_records: Dictionary = {}) -> void:
	runtime_catalog = runtime_data
	object_catalog = object_data
	graphics_catalog = graphics_data
	definitions.clear()
	frames_by_source.clear()
	descriptors_by_source.clear()
	if not indexed_frame_records.is_empty():
		records_by_name = indexed_frame_records.duplicate()
	else:
		records_by_name.clear()
		for record_value in asset_records:
			var record: Dictionary = record_value
			if String(record.get("archive", "")) != "graphics" or not record.has("frame"):
				continue
			var name := String(record.get("name", ""))
			if name.is_empty():
				continue
			if not records_by_name.has(name):
				records_by_name[name] = []
			records_by_name[name].append(record)
		for name in records_by_name:
			records_by_name[name].sort_custom(func(left, right): return int(left.get("frame", 0)) < int(right.get("frame", 0)))
	for archetype_value in runtime_catalog.get("archetypes", {}).values():
		var archetype: Dictionary = archetype_value
		if String(archetype.get("category", "")) != "projectile":
			continue
		var source_id := int(archetype.get("identifiers", {}).get("source_unit_id", -1))
		var runtime: Dictionary = archetype.get("runtime", {})
		var asset_name := String(runtime.get("asset_name", ""))
		if source_id < 0 or asset_name.is_empty():
			continue
		definitions[source_id] = {
			"asset_name": asset_name,
			"graphic_id": int(runtime.get("graphic_id", -1)),
			"loop": bool(runtime.get("loop", true)),
		}


func has_projectile(source_unit_id: int) -> bool:
	return definitions.has(source_unit_id)


func animation_frames(source_unit_id: int) -> Array:
	ensure_loaded(source_unit_id)
	return frames_by_source.get(source_unit_id, [])


func frame_info(projectile: Dictionary) -> Dictionary:
	var source_unit_id := int(projectile.get("projectile_unit_id", -1))
	ensure_loaded(source_unit_id)
	var frames: Array = frames_by_source.get(source_unit_id, [])
	var descriptor = descriptors_by_source.get(source_unit_id)
	if frames.is_empty() or descriptor == null:
		return {}
	var facing := ProjectileMotion.logical_facing(projectile, descriptor.logical_angle_count)
	var resolved: Dictionary = descriptor.resolve(facing, float(projectile.get("elapsed", 0.0)), frames.size())
	var frame_index := int(resolved.get("frame_index", 0))
	var texture: Texture2D = frames[frame_index]
	return {
		"texture": texture,
		"asset_name": descriptor.asset_name,
		"frame_index": frame_index,
		"hotspot": descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height() * 0.5)),
		"mirrored": bool(resolved.get("mirrored", false)),
	}


func ensure_loaded(source_unit_id: int) -> void:
	if frames_by_source.has(source_unit_id):
		return
	var definition: Dictionary = definitions.get(source_unit_id, {})
	if definition.is_empty():
		return
	var asset_name := String(definition.get("asset_name", ""))
	var frame_records: Array = records_by_name.get(asset_name, [])
	if frame_records.is_empty():
		return
	var frames: Array = []
	var hotspots: Array[Vector2] = []
	for record_value in frame_records:
		var record: Dictionary = record_value
		var texture: Texture2D = load("res://assets/generated/%s" % String(record.get("file", "")))
		if texture == null:
			continue
		frames.append(texture)
		var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height() * 0.5)
		if record.has("hotspot"):
			hotspot = Vector2(float(record["hotspot"][0]), float(record["hotspot"][1]))
		hotspots.append(hotspot)
	if frames.is_empty():
		return
	var graphic_id := int(definition.get("graphic_id", -1))
	if graphic_id < 0:
		var civilization_id := int(runtime_catalog.get("default_civilization_id", 13))
		var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, source_unit_id], {})
		if source.is_empty():
			source = object_catalog.get("objects", {}).get("0:%d" % source_unit_id, {})
		graphic_id = int(source.get("graphics", {}).get("idle", -1))
	var graphic_spec: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	var descriptor := GraphicDescriptor.new(asset_name, graphic_spec, frames.size(), bool(definition.get("loop", true)))
	descriptor.set_hotspots(hotspots)
	frames_by_source[source_unit_id] = frames
	descriptors_by_source[source_unit_id] = descriptor
