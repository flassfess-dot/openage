class_name RoREffectPresentationRegistry
extends RefCounted

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")

var graphics_catalog: Dictionary = {}
var records_by_name: Dictionary = {}
var frames_by_key: Dictionary = {}
var descriptors_by_key: Dictionary = {}


func configure(graphics_data: Dictionary, asset_records: Array) -> void:
	graphics_catalog = graphics_data
	records_by_name.clear()
	frames_by_key.clear()
	descriptors_by_key.clear()
	for record_value in asset_records:
		var record: Dictionary = record_value
		if String(record.get("archive", "")) != "graphics" or not record.has("frame"):
			continue
		var name := String(record.get("name", ""))
		if not name.begins_with("graphic_") or not name.contains("_p"):
			continue
		if not records_by_name.has(name):
			records_by_name[name] = []
		records_by_name[name].append(record)
	for name in records_by_name:
		records_by_name[name].sort_custom(func(left, right): return int(left.get("frame", 0)) < int(right.get("frame", 0)))


func frame_info(effect: Dictionary) -> Dictionary:
	return frame_info_for(
		int(effect.get("graphic_id", -1)),
		int(effect.get("team", 1)),
		float(effect.get("elapsed", 0.0))
	)


func frame_info_for(graphic_id: int, team: int, animation_time: float) -> Dictionary:
	var player := 2 if team == 2 else 1
	var key := _ensure_loaded(graphic_id, player)
	if key.is_empty():
		return {}
	var frames: Array = frames_by_key.get(key, [])
	var descriptor = descriptors_by_key.get(key)
	if frames.is_empty() or descriptor == null:
		return {}
	var resolved: Dictionary = descriptor.resolve(0, animation_time, frames.size())
	var frame_index := int(resolved.get("frame_index", 0))
	var texture: Texture2D = frames[frame_index]
	return {
		"texture": texture,
		"asset_name": descriptor.asset_name,
		"frame_index": frame_index,
		"graphic_id": graphic_id,
		"graphic_layer": int(graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {}).get("layer", 30)),
		"hotspot": descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height())),
		"mirrored": false,
		"screen_offset": Vector2.ZERO,
	}


func duration(graphic_id: int) -> float:
	var graphic: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	return maxf(0.05, float(graphic.get("frames_per_angle", 1)) * maxf(0.001, float(graphic.get("frame_rate", 0.05))))


func has_graphic(graphic_id: int, team: int = 1) -> bool:
	return not _ensure_loaded(graphic_id, 2 if team == 2 else 1).is_empty()


func _ensure_loaded(graphic_id: int, player: int) -> String:
	var requested_key := "%d:%d" % [graphic_id, player]
	if frames_by_key.has(requested_key):
		return requested_key
	var asset_name := "graphic_%d_p%d" % [graphic_id, player]
	var frame_records: Array = records_by_name.get(asset_name, [])
	if frame_records.is_empty() and player != 1:
		return _ensure_loaded(graphic_id, 1)
	if frame_records.is_empty():
		return ""
	var frames: Array = []
	var hotspots: Array[Vector2] = []
	for record_value in frame_records:
		var record: Dictionary = record_value
		var texture: Texture2D = load("res://assets/generated/%s" % String(record.get("file", "")))
		if texture == null:
			continue
		frames.append(texture)
		var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
		if record.has("hotspot"):
			hotspot = Vector2(float(record["hotspot"][0]), float(record["hotspot"][1]))
		hotspots.append(hotspot)
	if frames.is_empty():
		return ""
	var graphic: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	var sequence_type := int(graphic.get("sequence_type", 0))
	var descriptor := GraphicDescriptor.new(asset_name, graphic, frames.size(), sequence_type != 0 and (sequence_type & 0x08) == 0)
	descriptor.set_hotspots(hotspots)
	frames_by_key[requested_key] = frames
	descriptors_by_key[requested_key] = descriptor
	return requested_key
