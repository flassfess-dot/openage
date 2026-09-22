class_name RoRPresentationAudioRouter
extends RefCounted

const CATEGORY_COOLDOWNS := {
	"voice_selection": 0.18,
	"voice_command": 0.12,
	"production": 0.10,
	"combat": 0.08,
}

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var sound_catalog: Dictionary = {}
var graphics_catalog: Dictionary = {}
var assets_by_resource_id: Dictionary = {}
var clock_seconds: float = 0.0
var request_sequence: int = 0
var last_played_by_category: Dictionary = {}


func configure(runtime_data: Dictionary, sound_data: Dictionary, asset_records: Variant, graphics_data: Dictionary = {}, object_data: Dictionary = {}, indexed_audio_assets: Dictionary = {}) -> void:
	runtime_catalog = runtime_data
	object_catalog = object_data
	sound_catalog = sound_data
	graphics_catalog = graphics_data
	assets_by_resource_id.clear()
	if not indexed_audio_assets.is_empty():
		assets_by_resource_id = indexed_audio_assets.duplicate()
		reset()
		return
	var records: Array = asset_records.values() if asset_records is Dictionary else asset_records if asset_records is Array else []
	for metadata_value in records:
		var metadata: Dictionary = metadata_value
		if String(metadata.get("extension", "")).to_lower() != "wav" or not metadata.has("id"):
			continue
		assets_by_resource_id[int(metadata["id"])] = String(metadata.get("file", ""))
	reset()


func reset() -> void:
	clock_seconds = 0.0
	request_sequence = 0
	last_played_by_category.clear()


func advance(delta: float) -> void:
	clock_seconds += maxf(0.0, delta)


func request(kind: String, event_name: String, civilization_id: int = -1, selection_seed: int = -1) -> Dictionary:
	var presentation := _presentation(kind, civilization_id)
	var sound_reference: Dictionary = presentation.get("sounds", {}).get(event_name, {})
	var sound_id := int(sound_reference.get("sound_id", -1))
	if sound_id < 0 or not bool(sound_reference.get("available", false)):
		return {"accepted": false, "reason": "sound_unavailable", "sound_id": sound_id}
	return request_sound_id(sound_id, event_name, civilization_id, selection_seed)


func request_animation(kind: String, animation_state: String, civilization_id: int = -1, selection_seed: int = -1) -> Dictionary:
	var presentation := _presentation(kind, civilization_id)
	var graphic_reference: Dictionary = presentation.get("graphics", {}).get(animation_state, {})
	var graphic_id := int(graphic_reference.get("graphic_id", -1))
	if graphic_id < 0:
		return {"accepted": false, "reason": "graphic_unavailable", "graphic_id": graphic_id}
	var result := request_graphic(graphic_id, animation_state, civilization_id, selection_seed)
	result["graphic_id"] = graphic_id
	return result


func request_entity_animation(entity: Dictionary, animation_state: String, selection_seed: int = -1) -> Dictionary:
	var civilization_id := int(entity.get("components", {}).get("ownership", {}).get("civilization_id", -1))
	var graphic_id := _entity_graphic_id(entity, animation_state, civilization_id)
	if graphic_id < 0:
		return {"accepted": false, "reason": "graphic_unavailable", "graphic_id": graphic_id}
	var result := request_graphic(graphic_id, animation_state, civilization_id, selection_seed, int(entity.get("facing", 0)))
	result["graphic_id"] = graphic_id
	return result


func request_graphic(graphic_id: int, fallback_category: String, civilization_id: int = -1, selection_seed: int = -1, logical_facing: int = 0) -> Dictionary:
	var sound_id := _graphic_sound_id(graphic_id, logical_facing)
	if sound_id < 0:
		return {"accepted": false, "reason": "sound_unavailable", "graphic_id": graphic_id, "sound_id": sound_id}
	var result := request_sound_id(sound_id, fallback_category, civilization_id, selection_seed)
	result["graphic_id"] = graphic_id
	return result


func request_sound_id(sound_id: int, fallback_category: String, civilization_id: int = -1, selection_seed: int = -1) -> Dictionary:
	var sound: Dictionary = sound_catalog.get("sounds", {}).get(String.num_int64(sound_id), {})
	if sound.is_empty():
		return {"accepted": false, "reason": "sound_unavailable", "sound_id": sound_id}
	var category := String(sound.get("categories", [fallback_category])[0] if not sound.get("categories", []).is_empty() else fallback_category)
	var cooldown := maxf(float(sound.get("play_delay", 0)) / 1000.0, float(CATEGORY_COOLDOWNS.get(category, 0.05)))
	if last_played_by_category.has(category) and clock_seconds - float(last_played_by_category[category]) + 0.000001 < cooldown:
		return {"accepted": false, "reason": "throttled", "sound_id": sound_id, "category": category}
	var candidates: Array = []
	var total_probability := 0
	for item_value in sound.get("items", []):
		var item: Dictionary = item_value
		var resource_id := int(item.get("resource_id", -1))
		var item_civilization = item.get("civilization_id")
		if resource_id < 0 or not assets_by_resource_id.has(resource_id) or not bool(item.get("audio", {}).get("valid", false)):
			continue
		if item_civilization != null and civilization_id >= 0 and int(item_civilization) != civilization_id:
			continue
		var probability := maxi(1, int(item.get("probability", 1)))
		candidates.append({"item": item, "weight": probability})
		total_probability += probability
	if candidates.is_empty():
		return {"accepted": false, "reason": "asset_unavailable", "sound_id": sound_id, "category": category}
	request_sequence += 1
	var seed_value := selection_seed if selection_seed >= 0 else request_sequence
	var roll := posmod(sound_id * 1103515245 + seed_value * 12345, total_probability)
	var selected: Dictionary = candidates[0]["item"]
	for candidate_value in candidates:
		var candidate: Dictionary = candidate_value
		if roll < int(candidate["weight"]):
			selected = candidate["item"]
			break
		roll -= int(candidate["weight"])
	var selected_resource_id := int(selected.get("resource_id", -1))
	var file_name := String(assets_by_resource_id.get(selected_resource_id, ""))
	var stream: AudioStream = load("res://assets/generated/%s" % file_name)
	if stream == null:
		return {"accepted": false, "reason": "asset_unavailable", "sound_id": sound_id, "category": category}
	last_played_by_category[category] = clock_seconds
	return {
		"accepted": true,
		"reason": "",
		"sound_id": sound_id,
		"resource_id": selected_resource_id,
		"category": category,
		"stream": stream,
		"cooldown": cooldown,
	}


func has_imported_variant(sound_id: int) -> bool:
	var sound: Dictionary = sound_catalog.get("sounds", {}).get(String.num_int64(sound_id), {})
	for item_value in sound.get("items", []):
		var item: Dictionary = item_value
		if bool(item.get("audio", {}).get("valid", false)) and assets_by_resource_id.has(int(item.get("resource_id", -1))):
			return true
	return false


func _graphic_sound_id(graphic_id: int, logical_facing: int) -> int:
	var graphic: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
	var sounds: Dictionary = graphic.get("sounds", {})
	var default_sound_id := int(sounds.get("sound_id", -1))
	if default_sound_id >= 0:
		return default_sound_id
	var angle_bindings: Array = sounds.get("attack", [])
	if angle_bindings.is_empty():
		return -1
	var requested_angle := posmod(logical_facing, angle_bindings.size())
	for binding_value in angle_bindings:
		var binding: Dictionary = binding_value
		if int(binding.get("angle", -1)) != requested_angle:
			continue
		for event_value in binding.get("events", []):
			var sound_id := int(event_value.get("sound_id", -1))
			if sound_id >= 0:
				return sound_id
	for binding_value in angle_bindings:
		for event_value in binding_value.get("events", []):
			var sound_id := int(event_value.get("sound_id", -1))
			if sound_id >= 0:
				return sound_id
	return -1


func _entity_graphic_id(entity: Dictionary, animation_state: String, civilization_id: int) -> int:
	var kind := String(entity.get("kind", ""))
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {})
	if archetype.is_empty():
		return -1
	var state_specs: Dictionary = archetype.get("runtime", {}).get("presentation_states", {})
	var source_unit_id := int(entity.get("source_unit_id", archetype.get("identifiers", {}).get("source_unit_id", -1)))
	var variant: Dictionary = archetype.get("runtime", {}).get("presentation_variants", {}).get(String.num_int64(source_unit_id), {})
	var state_spec: Dictionary = variant.get(animation_state, state_specs.get(animation_state, {}))
	var audio_graphic_field := String(state_spec.get("audio_graphic_field", ""))
	if not audio_graphic_field.is_empty():
		var audio_source_id := int(entity.get("source_unit_id", archetype.get("identifiers", {}).get("source_unit_id", -1)))
		var audio_civilization := civilization_id if civilization_id >= 0 else int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
		var audio_source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [audio_civilization, audio_source_id], {})
		if audio_source.is_empty():
			audio_source = object_catalog.get("objects", {}).get("0:%d" % audio_source_id, {})
		var audio_graphic_id := int(audio_source.get("graphics", {}).get(audio_graphic_field, -1))
		if audio_graphic_id >= 0:
			return audio_graphic_id
	var graphic_id := int(state_spec.get("graphic_id", -1))
	if graphic_id >= 0:
		return graphic_id
	var graphic_field := String(state_spec.get("graphic_field", animation_state))
	var resolved_civilization := civilization_id if civilization_id >= 0 else int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [resolved_civilization, source_unit_id], {})
	if source.is_empty():
		source = object_catalog.get("objects", {}).get("0:%d" % source_unit_id, {})
	graphic_id = int(source.get("graphics", {}).get(graphic_field, -1))
	if graphic_id >= 0:
		return graphic_id
	return int(_presentation(kind, resolved_civilization).get("graphics", {}).get(animation_state, {}).get("graphic_id", -1))


func _presentation(kind: String, civilization_id: int) -> Dictionary:
	var archetype: Dictionary = runtime_catalog.get("archetypes", {}).get(kind, {})
	if archetype.is_empty():
		return {}
	var records: Dictionary = archetype.get("records", {})
	var resolved_civilization := civilization_id if civilization_id >= 0 else int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var record: Dictionary = records.get(String.num_int64(resolved_civilization), records.get(String.num_int64(int(archetype.get("default_civilization_id", 13))), {}))
	return record.get("presentation", {})
