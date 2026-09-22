class_name RoRBuildingPresentationRegistry
extends RefCounted

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")
const CompositeGraphic := preload("res://scripts/composite_graphic.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")
const DamageSelector := preload("res://scripts/presentation_damage_selector.gd")

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var graphics_catalog: Dictionary = {}
var asset_metadata: Dictionary = {}
var frame_records_by_name: Dictionary = {}
var textures_by_key: Dictionary = {}
var descriptors_by_key: Dictionary = {}
var resolved_graphic_keys: Dictionary = {}
var source_records_by_key: Dictionary = {}
var presentation_facing_by_key: Dictionary = {}
var civilization_icon_sets: Dictionary = {}


func configure(runtime_data: Dictionary, object_data: Dictionary, graphics_data: Dictionary, metadata: Dictionary, indexed_frame_records: Dictionary = {}) -> void:
	runtime_catalog = runtime_data
	object_catalog = object_data
	graphics_catalog = graphics_data
	asset_metadata = metadata
	source_records_by_key.clear()
	presentation_facing_by_key.clear()
	civilization_icon_sets.clear()
	for civilization_value in object_catalog.get("civilizations", []):
		var civilization: Dictionary = civilization_value
		civilization_icon_sets[int(civilization.get("civilization_id", -1))] = int(civilization.get("icon_set", 0))
	_index_imported_graphics(indexed_frame_records)


func frame_info(building: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var player := _player_asset_id(int(building.get("team", 1)))
	var source := _source_record(building)
	if String(building.get("death_phase", "alive")) == "dying" or String(building.get("state", "complete")) == "destroyed":
		var death_graphic := int(source.get("graphics", {}).get("death", -1))
		var death_time := float(building.get("death_elapsed", animation_time))
		var death_info := _resolved_frame(death_graphic, player, 0, death_time)
		death_info["graphic_id"] = death_graphic
		death_info["composite_parts"] = _composite_parts(death_graphic, player, 0, death_time)
		return death_info
	if String(building.get("state", "complete")) == "foundation":
		var construction_graphic := int(source.get("graphics", {}).get("construction", -1))
		var stage := maxi(0, int(building.get("construction_stage", 0)))
		var construction_result := _frame_at(construction_graphic, player, stage)
		construction_result["graphic_id"] = construction_graphic
		return construction_result
	if bool(building.get("harvestable", false)) and int(building.get("amount", 0)) <= 0:
		var runtime: Dictionary = runtime_catalog.get("archetypes", {}).get(String(building.get("kind", "")), {}).get("runtime", {})
		var depleted_graphic := int(runtime.get("depleted_graphic_id", -1))
		if depleted_graphic < 0:
			var depleted_source_id := int(runtime.get("depleted_source_unit_id", -1))
			var civilization_id := int(building.get("components", {}).get("ownership", {}).get("civilization_id", runtime_catalog.get("default_civilization_id", 13)))
			var depleted_source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, depleted_source_id], object_catalog.get("objects", {}).get("0:%d" % depleted_source_id, {}))
			depleted_graphic = int(depleted_source.get("graphics", {}).get("idle", -1))
		var depleted_result := _resolved_frame(depleted_graphic, player, 0, animation_time)
		depleted_result["graphic_id"] = depleted_graphic
		depleted_result["composite_parts"] = _composite_parts(depleted_graphic, player, 0, animation_time)
		return depleted_result

	var clip := AnimationController.clip_for_state(String(building.get("anim_state", AnimationController.IDLE)))
	var presentation_time := float(building.get("anim", animation_time)) if clip == "attack" else animation_time
	var base_graphic := int(building.get("display_graphic_id", source.get("graphics", {}).get("idle", -1)))
	if clip == "attack":
		var attack_graphic := int(source.get("graphics", {}).get("attack", -1))
		if attack_graphic >= 0:
			base_graphic = attack_graphic
	var presentation_facing := _presentation_facing(building, base_graphic)
	var result := _resolved_frame(base_graphic, player, presentation_facing, presentation_time)
	result["graphic_id"] = base_graphic
	var parts := _composite_parts(base_graphic, player, presentation_facing, presentation_time)
	var damage_part := _damage_part(building, source, player, presentation_time)
	if not damage_part.is_empty():
		parts.append(damage_part)
	result["composite_parts"] = parts
	return result


func has_graphic(graphic_id: int, player: int = 1) -> bool:
	return not _frame_records(graphic_id, _player_asset_id(player)).is_empty()


func imported_frame_count(graphic_id: int, player: int = 1) -> int:
	return _frame_records(graphic_id, _player_asset_id(player)).size()


func _index_imported_graphics(indexed_frame_records: Dictionary) -> void:
	textures_by_key.clear()
	descriptors_by_key.clear()
	resolved_graphic_keys.clear()
	if not indexed_frame_records.is_empty():
		frame_records_by_name = indexed_frame_records.duplicate()
		return
	frame_records_by_name.clear()
	for metadata_value in asset_metadata.values():
		var metadata: Dictionary = metadata_value
		var name := String(metadata.get("name", ""))
		if not name.begins_with("graphic_") or not name.contains("_p"):
			continue
		if not frame_records_by_name.has(name):
			frame_records_by_name[name] = []
		frame_records_by_name[name].append(metadata)
	for records_value in frame_records_by_name.values():
		var records: Array = records_value
		records.sort_custom(func(left, right): return int(left.get("frame", 0)) < int(right.get("frame", 0)))


func _ensure_loaded(graphic_id: int, player: int) -> String:
	var requested_key := _graphic_key(graphic_id, player)
	if resolved_graphic_keys.has(requested_key):
		return String(resolved_graphic_keys[requested_key])
	var asset_name := "graphic_%d_p%d" % [graphic_id, player]
	var frame_records: Array = frame_records_by_name.get(asset_name, [])
	if frame_records.is_empty() and player != 1:
		var fallback_key := _ensure_loaded(graphic_id, 1)
		resolved_graphic_keys[requested_key] = fallback_key
		return fallback_key
	if frame_records.is_empty():
		resolved_graphic_keys[requested_key] = ""
		return ""
	var frames: Array = []
	var hotspots: Array[Vector2] = []
	for metadata_value in frame_records:
		var metadata: Dictionary = metadata_value
		var texture: Texture2D = load("res://assets/generated/%s" % String(metadata.get("file", "")))
		if texture == null:
			continue
		frames.append(texture)
		var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
		if metadata.has("hotspot"):
			hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
		hotspots.append(hotspot)
	if frames.is_empty():
		resolved_graphic_keys[requested_key] = ""
		return ""
	var spec: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	var sequence_type := int(spec.get("sequence_type", 0))
	var descriptor := GraphicDescriptor.new(asset_name, spec, frames.size(), sequence_type != 0 and (sequence_type & 0x08) == 0)
	descriptor.set_hotspots(hotspots)
	textures_by_key[requested_key] = frames
	descriptors_by_key[requested_key] = descriptor
	resolved_graphic_keys[requested_key] = requested_key
	return requested_key


func _frame_records(graphic_id: int, player: int) -> Array:
	return frame_records_by_name.get("graphic_%d_p%d" % [graphic_id, player], [])


func _source_record(building: Dictionary) -> Dictionary:
	var source_unit_id := int(building.get("source_unit_id", -1))
	var civilization_id := int(building.get("components", {}).get("ownership", {}).get("civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var cache_key := "%d:%d" % [civilization_id, source_unit_id]
	if source_records_by_key.has(cache_key):
		return source_records_by_key[cache_key]
	var direct: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, source_unit_id], {})
	if not direct.is_empty():
		source_records_by_key[cache_key] = direct
		return direct
	var fallback: Dictionary = object_catalog.get("objects", {}).get("0:%d" % source_unit_id, {})
	if not fallback.is_empty():
		source_records_by_key[cache_key] = fallback
		return fallback
	var alias := String(building.get("kind", ""))
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(alias, {})
	var records: Dictionary = archetype.get("records", {})
	var normalized: Dictionary = records.get(String.num_int64(civilization_id), records.get(String.num_int64(int(archetype.get("default_civilization_id", 13))), {}))
	var source_key := String(normalized.get("source_key", ""))
	var resolved: Dictionary = object_catalog.get("objects", {}).get(source_key, {})
	source_records_by_key[cache_key] = resolved
	return resolved


func _presentation_facing(building: Dictionary, graphic_id: int) -> int:
	if building.has("presentation_facing"):
		return maxi(0, int(building["presentation_facing"]))
	var civilization_id := int(building.get("components", {}).get("ownership", {}).get("civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var cache_key := "%d:%d" % [civilization_id, graphic_id]
	if presentation_facing_by_key.has(cache_key):
		return int(presentation_facing_by_key[cache_key])
	var graphic: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	var angle_count := maxi(1, int(graphic.get("angle_count", 1)))
	if angle_count <= 1:
		presentation_facing_by_key[cache_key] = 0
		return 0
	# RoR stores the expansion's Roman architecture as the final static
	# direction in otherwise non-rotating building graphics.
	var facing := angle_count - 1 if int(civilization_icon_sets.get(civilization_id, 0)) == 4 else 0
	presentation_facing_by_key[cache_key] = facing
	return facing


func _frame_at(graphic_id: int, player: int, requested_frame: int) -> Dictionary:
	var key := _ensure_loaded(graphic_id, player)
	var frames: Array = textures_by_key.get(key, [])
	if frames.is_empty():
		return {"texture": null, "asset_name": "", "frame_index": 0, "hotspot": Vector2.ZERO, "mirrored": false, "graphic_layer": _graphic_layer(graphic_id)}
	var frame_index := clampi(requested_frame, 0, frames.size() - 1)
	var descriptor = descriptors_by_key[key]
	var texture: Texture2D = frames[frame_index]
	return {
		"texture": texture,
		"asset_name": descriptor.asset_name,
		"frame_index": frame_index,
		"hotspot": descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height())),
		"mirrored": false,
		"graphic_layer": _graphic_layer(graphic_id),
	}


func _resolved_frame(graphic_id: int, player: int, logical_facing: int, animation_time: float) -> Dictionary:
	var key := _ensure_loaded(graphic_id, player)
	var frames: Array = textures_by_key.get(key, [])
	if frames.is_empty():
		return _frame_at(graphic_id, player, 0)
	var descriptor = descriptors_by_key[key]
	var resolved: Dictionary = descriptor.resolve(logical_facing, animation_time, frames.size())
	var frame_index := int(resolved["frame_index"])
	var texture: Texture2D = frames[frame_index]
	return {
		"texture": texture,
		"asset_name": descriptor.asset_name,
		"frame_index": frame_index,
		"hotspot": descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height())),
		"mirrored": bool(resolved["mirrored"]),
		"source_direction": int(resolved["source_direction"]),
		"direction_degrees": int(resolved["direction_degrees"]),
		"graphic_layer": _graphic_layer(graphic_id),
	}


func _composite_parts(base_graphic_id: int, player: int, logical_facing: int, animation_time: float) -> Array:
	var result: Array = []
	_append_composite_parts(result, base_graphic_id, player, logical_facing, animation_time, Vector2.ZERO, {})
	return result


func _append_composite_parts(result: Array, base_graphic_id: int, player: int, logical_facing: int, animation_time: float, inherited_offset: Vector2, visited: Dictionary) -> void:
	var base_key := String.num_int64(base_graphic_id)
	if visited.has(base_key):
		return
	visited[base_key] = true
	var base_spec: Dictionary = graphics_catalog.get("graphics", {}).get(base_key, {})
	for delta_value in _delta_records(base_spec.get("deltas", [])):
		var delta: Dictionary = delta_value
		var child_id := int(delta.get("graphic_id", -1))
		if child_id < 0 or not CompositeGraphic.delta_visible(int(delta.get("display_angle", -1)), logical_facing, int(base_spec.get("angle_count", 1))):
			continue
		var part := _resolved_frame(child_id, player, logical_facing, animation_time)
		if part.get("texture") == null:
			continue
		var offset := inherited_offset + Vector2(float(delta.get("offset_x", 0)), float(delta.get("offset_y", 0)))
		part["graphic_id"] = child_id
		part["screen_offset"] = offset
		result.append(part)
		_append_composite_parts(result, child_id, player, logical_facing, animation_time, offset, visited)
	visited.erase(base_key)


func _delta_records(value: Variant) -> Array:
	if value is Array:
		return value
	if value is Dictionary and not value.is_empty():
		return [value]
	return []


func _damage_part(building: Dictionary, source: Dictionary, player: int, animation_time: float) -> Dictionary:
	var selected_graphic := DamageSelector.select_graphic_id(building, source)
	if selected_graphic < 0:
		return {}
	var result := _resolved_frame(selected_graphic, player, 0, animation_time)
	if result.get("texture") == null:
		return {}
	result["graphic_id"] = selected_graphic
	result["screen_offset"] = Vector2.ZERO
	return result


func _graphic_key(graphic_id: int, player: int) -> String:
	return "%d:%d" % [graphic_id, player]


func _graphic_layer(graphic_id: int) -> int:
	return int(graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {}).get("layer", 20))


func _player_asset_id(team: int) -> int:
	return 2 if team == 2 else 1
