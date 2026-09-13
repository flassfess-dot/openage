class_name RoRResourcePresentationRegistry
extends RefCounted

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var graphics_catalog: Dictionary = {}
var frames_by_asset: Dictionary = {}
var metadata_by_asset_frame: Dictionary = {}


func configure(runtime_data: Dictionary, object_data: Dictionary, graphics_data: Dictionary, asset_records: Array) -> void:
	runtime_catalog = runtime_data
	object_catalog = object_data
	graphics_catalog = graphics_data
	frames_by_asset.clear()
	metadata_by_asset_frame.clear()
	var required_assets := _required_asset_names()
	var records_by_asset: Dictionary = {}
	for record_value in asset_records:
		var record: Dictionary = record_value
		if String(record.get("archive", "")) != "graphics" or not record.has("frame"):
			continue
		var name := String(record.get("name", ""))
		if name.is_empty() or not required_assets.has(name):
			continue
		if not records_by_asset.has(name):
			records_by_asset[name] = []
		records_by_asset[name].append(record)
	for asset_name_value in records_by_asset:
		var asset_name := String(asset_name_value)
		var records: Array = records_by_asset[asset_name]
		records.sort_custom(func(left, right): return int(left.get("frame", 0)) < int(right.get("frame", 0)))
		var frames: Array = []
		for record_value in records:
			var record: Dictionary = record_value
			var texture: Texture2D = load("res://assets/generated/%s" % String(record.get("file", "")))
			if texture == null:
				continue
			frames.append(texture)
			metadata_by_asset_frame[_key(asset_name, int(record.get("frame", 0)))] = record.duplicate(true)
		if not frames.is_empty():
			frames_by_asset[asset_name] = frames


func frame_info(resource: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var kind := String(resource.get("kind", ""))
	var metadata: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {}).get("runtime", {})
	var asset_name := String(metadata.get("asset_name", ""))
	if int(resource.get("amount", 0)) <= 0:
		if not bool(metadata.get("visible_when_depleted", false)):
			return {}
		asset_name = String(metadata.get("depleted_asset_name", asset_name))
	if asset_name.is_empty():
		return {}
	var frames: Array = frames_by_asset.get(asset_name, [])
	if frames.is_empty():
		return {}
	var frame_index := posmod(int(resource.get("id", 0)), frames.size())
	if bool(metadata.get("animated", false)):
		frame_index = _animated_frame(kind, int(resource.get("id", 0)), animation_time, frames.size())
	var texture: Texture2D = frames[frame_index]
	var frame_metadata: Dictionary = metadata_by_asset_frame.get(_key(asset_name, frame_index), {})
	var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
	if frame_metadata.has("hotspot"):
		hotspot = Vector2(float(frame_metadata["hotspot"][0]), float(frame_metadata["hotspot"][1]))
	return {
		"texture": texture,
		"asset_name": asset_name,
		"frame_index": frame_index,
		"hotspot": hotspot,
		"mirrored": false,
	}


func _animated_frame(kind: String, entity_id: int, animation_time: float, frame_count: int) -> int:
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {})
	var source_unit_id := int(archetype.get("identifiers", {}).get("source_unit_id", -1))
	var source: Dictionary = object_catalog.get("objects", {}).get("0:%d" % source_unit_id, {})
	var graphic_id := int(source.get("graphics", {}).get("idle", -1))
	var graphic: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	var frame_duration := maxf(0.001, float(graphic.get("frame_rate", 0.1)))
	var animation_duration := frame_duration * float(maxi(1, frame_count))
	var replay_delay := maxf(0.0, float(graphic.get("replay_delay", 0.0)))
	var cycle_duration := animation_duration + replay_delay
	var phase := fmod(maxf(0.0, animation_time) + float(posmod(entity_id * 1618, 1000)) / 1000.0 * cycle_duration, cycle_duration)
	if phase >= animation_duration:
		return frame_count - 1
	return clampi(floori(phase / frame_duration), 0, frame_count - 1)


func has_presentation(kind: String) -> bool:
	var metadata: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {}).get("runtime", {})
	return frames_by_asset.has(String(metadata.get("asset_name", "")))


func _required_asset_names() -> Dictionary:
	var required: Dictionary = {}
	for archetype_value in runtime_catalog.get("archetypes", {}).values():
		var archetype: Dictionary = archetype_value
		if String(archetype.get("category", "")) != "resource":
			continue
		var metadata: Dictionary = archetype.get("runtime", {})
		for field in ["asset_name", "depleted_asset_name"]:
			var asset_name := String(metadata.get(field, ""))
			if not asset_name.is_empty():
				required[asset_name] = true
	return required


func _key(asset_name: String, frame: int) -> String:
	return "%s:%d" % [asset_name, frame]
