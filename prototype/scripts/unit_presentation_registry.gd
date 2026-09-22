class_name RoRUnitPresentationRegistry
extends RefCounted

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")
const DamageSelector := preload("res://scripts/presentation_damage_selector.gd")

var runtime_catalog: Dictionary = {}
var object_catalog: Dictionary = {}
var graphics_catalog: Dictionary = {}
var asset_records: Array = []
var textures: Dictionary = {}
var descriptors: Dictionary = {}
var graphic_ids: Dictionary = {}
var composite_parts: Dictionary = {}
var definitions: Dictionary = {}
var records_by_name: Dictionary = {}
var effect_presentations


func configure(runtime_data: Dictionary, object_data: Dictionary, graphics_data: Dictionary, records: Array, effect_registry = null, indexed_frame_records: Dictionary = {}) -> void:
	runtime_catalog = runtime_data
	object_catalog = object_data
	graphics_catalog = graphics_data
	asset_records = records
	textures.clear()
	descriptors.clear()
	graphic_ids.clear()
	composite_parts.clear()
	definitions.clear()
	records_by_name = indexed_frame_records.duplicate() if not indexed_frame_records.is_empty() else _records_by_name()
	effect_presentations = effect_registry
	var archetypes: Dictionary = runtime_catalog.get("archetypes", {})
	var aliases: Array = archetypes.keys()
	aliases.sort()
	for alias_value in aliases:
		var alias := String(alias_value)
		var archetype: Dictionary = archetypes[alias]
		if String(archetype.get("category", "")) != "unit":
			continue
		var state_specs: Dictionary = archetype.get("runtime", {}).get("presentation_states", {})
		if state_specs.is_empty():
			continue
		_register_team(alias, alias, 1, archetype, state_specs)
		_register_team(alias, "enemy_%s" % alias, 2, archetype, state_specs)
		if state_specs.values().any(func(state): return not String(state.get("neutral_asset_name", "")).is_empty()):
			_register_team(alias, "neutral_%s" % alias, 0, archetype, state_specs)
		var variants: Dictionary = archetype.get("runtime", {}).get("presentation_variants", {})
		for source_id_value in variants:
			var source_id := int(source_id_value)
			# Variants are sparse overlays. Shared task states and lifecycle clips stay
			# inherited when a source upgrade changes only one graphic (for example
			# the Iron Age Villager attack).
			var variant_states: Dictionary = state_specs.duplicate()
			for state_value in variants[source_id_value]:
				variant_states[state_value] = variants[source_id_value][state_value]
			_register_team(alias, "%s#%d" % [alias, source_id], 1, archetype, variant_states, source_id)
			_register_team(alias, "enemy_%s#%d" % [alias, source_id], 2, archetype, variant_states, source_id)


func descriptor(texture_key: String, state: String) -> Variant:
	ensure_loaded(texture_key)
	return descriptors.get(texture_key, {}).get(state)


func has_unit(alias: String) -> bool:
	return definitions.has(alias)


func presentation_keys() -> Array:
	var result: Array = definitions.keys()
	result.sort()
	return result


func animation_states(texture_key: String) -> Array:
	var definition: Dictionary = definitions.get(texture_key, {})
	var result: Array = definition.get("state_specs", {}).keys()
	result.sort()
	return result


func animation_frames(texture_key: String, state: String) -> Array:
	ensure_loaded(texture_key)
	return textures.get(texture_key, {}).get(state, [])


func ensure_loaded(texture_key: String) -> void:
	if textures.has(texture_key):
		return
	var definition: Dictionary = definitions.get(texture_key, {})
	if definition.is_empty():
		return
	_load_team(
		String(definition.get("alias", "")),
		texture_key,
		int(definition.get("team", 1)),
		definition.get("archetype", {}),
		definition.get("state_specs", {}),
		int(definition.get("source_unit_id", -1))
	)


func frame_info(unit: Dictionary, state: String, animation_time: float = -1.0) -> Dictionary:
	var alias := String(unit.get("kind", ""))
	var owner_team := int(unit.get("team", 1))
	var prefix := alias if owner_team == 1 else "enemy_%s" % alias
	var neutral_prefix := "neutral_%s" % alias
	if owner_team <= 0 and definitions.has(neutral_prefix):
		prefix = neutral_prefix
	var source_id := int(unit.get("source_unit_id", -1))
	var variant_key := "%s#%d" % [prefix, source_id]
	var texture_key := variant_key if definitions.has(variant_key) else prefix
	ensure_loaded(texture_key)
	var animation_sets: Dictionary = textures.get(texture_key, {})
	var resolved_state := state if animation_sets.has(state) else "idle"
	var frames: Array = animation_sets.get(resolved_state, [])
	var graphic_descriptor = descriptor(texture_key, resolved_state)
	if frames.is_empty() or graphic_descriptor == null:
		return {}
	var time := float(unit.get("anim", 0.0)) if animation_time < 0.0 else animation_time
	var resolved: Dictionary = graphic_descriptor.resolve(int(unit.get("facing", 0)), time, frames.size())
	var frame_index := int(resolved["frame_index"])
	var texture: Texture2D = frames[frame_index]
	var graphic_id := int(graphic_ids.get(texture_key, {}).get(resolved_state, -1))
	var resolved_parts := _resolved_composite_parts(texture_key, resolved_state, int(unit.get("facing", 0)), time)
	var damage_graphic_id := -1
	if resolved_state not in ["death", "corpse"] and effect_presentations != null:
		var source := _source_record(archetype_for_unit(alias), source_id, unit)
		damage_graphic_id = DamageSelector.select_graphic_id(unit, source)
		if damage_graphic_id >= 0:
			var damage_part: Dictionary = effect_presentations.frame_info_for(damage_graphic_id, int(unit.get("team", 1)), time)
			if not damage_part.is_empty():
				damage_part["effect_kind"] = "damage"
				resolved_parts.append(damage_part)
	return {
		"texture": texture,
		"frame_index": frame_index,
		"asset_name": graphic_descriptor.asset_name,
		"graphic_id": graphic_id,
		"graphic_layer": int(graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {}).get("layer", 20)),
		"mirrored": bool(resolved["mirrored"]),
		"source_direction": int(resolved["source_direction"]),
		"direction_degrees": int(resolved["direction_degrees"]),
		"hotspot": graphic_descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height())),
		"composite_parts": resolved_parts,
		"damage_graphic_id": damage_graphic_id,
	}


func archetype_for_unit(alias: String) -> Dictionary:
	return runtime_catalog.get("archetypes", {}).get(alias, {})


func _source_record(archetype: Dictionary, source_unit_id: int, unit: Dictionary) -> Dictionary:
	var resolved_source_id := source_unit_id if source_unit_id >= 0 else int(archetype.get("identifiers", {}).get("source_unit_id", -1))
	var civilization_id := int(unit.get("components", {}).get("ownership", {}).get("civilization_id", archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13))))
	var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, resolved_source_id], {})
	if source.is_empty():
		source = object_catalog.get("objects", {}).get("0:%d" % resolved_source_id, {})
	return source


func _register_team(alias: String, texture_key: String, team: int, archetype: Dictionary, state_specs: Dictionary, source_unit_id: int = -1) -> void:
	definitions[texture_key] = {
		"alias": alias,
		"team": team,
		"archetype": archetype,
		"state_specs": state_specs,
		"source_unit_id": source_unit_id,
	}


func _load_team(alias: String, texture_key: String, team: int, archetype: Dictionary, state_specs: Dictionary, source_unit_id: int = -1) -> void:
	textures[texture_key] = {}
	descriptors[texture_key] = {}
	graphic_ids[texture_key] = {}
	composite_parts[texture_key] = {}
	for state_value in state_specs:
		var state := String(state_value)
		var state_spec: Dictionary = state_specs[state]
		var base_asset_name := String(state_spec.get("asset_name", ""))
		var asset_name := String(state_spec.get("neutral_asset_name", base_asset_name)) if team <= 0 else String(state_spec.get("enemy_asset_name", base_asset_name)) if team == 2 else base_asset_name
		var frame_records: Array = records_by_name.get(asset_name, [])
		if frame_records.is_empty() and team == 2:
			asset_name = base_asset_name
			frame_records = records_by_name.get(asset_name, [])
		if frame_records.is_empty():
			continue
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
			continue
		var graphic_id := int(state_spec.get("neutral_graphic_id", state_spec.get("graphic_id", -1))) if team <= 0 else int(state_spec.get("graphic_id", -1))
		if graphic_id < 0:
			graphic_id = _source_graphic_id(archetype, String(state_spec.get("graphic_field", state)), team, source_unit_id)
		var graphic_spec: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
		var graphic_descriptor := GraphicDescriptor.new(asset_name, graphic_spec, frames.size(), bool(state_spec.get("loop", true)))
		graphic_descriptor.set_hotspots(hotspots)
		textures[texture_key][state] = frames
		descriptors[texture_key][state] = graphic_descriptor
		graphic_ids[texture_key][state] = graphic_id
		_load_composite_parts(texture_key, state, team, state_spec)


func _load_composite_parts(texture_key: String, state: String, team: int, state_spec: Dictionary) -> void:
	var loaded_parts: Array = []
	for part_value in state_spec.get("composite_parts", []):
		var part_spec: Dictionary = part_value
		var base_asset_name := String(part_spec.get("asset_name", ""))
		var asset_name := String(part_spec.get("enemy_asset_name", base_asset_name)) if team == 2 else base_asset_name
		var frame_records: Array = records_by_name.get(asset_name, [])
		if frame_records.is_empty() and team == 2:
			asset_name = base_asset_name
			frame_records = records_by_name.get(asset_name, [])
		if frame_records.is_empty():
			continue
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
			continue
		var graphic_id := int(part_spec.get("graphic_id", -1))
		var graphic_spec: Dictionary = graphics_catalog.get("graphics", {}).get(String.num_int64(graphic_id), {})
		var descriptor := GraphicDescriptor.new(asset_name, graphic_spec, frames.size(), bool(part_spec.get("loop", true)))
		descriptor.set_hotspots(hotspots)
		var raw_offset: Array = part_spec.get("screen_offset", [0.0, 0.0])
		loaded_parts.append({
			"frames": frames,
			"descriptor": descriptor,
			"graphic_id": graphic_id,
			"screen_offset": Vector2(float(raw_offset[0]), float(raw_offset[1])) if raw_offset.size() >= 2 else Vector2.ZERO,
			"graphic_layer": int(graphic_spec.get("layer", 20)),
		})
	composite_parts[texture_key][state] = loaded_parts


func _resolved_composite_parts(texture_key: String, state: String, facing: int, animation_time: float) -> Array:
	var result: Array = []
	for loaded_value in composite_parts.get(texture_key, {}).get(state, []):
		var loaded: Dictionary = loaded_value
		var frames: Array = loaded.get("frames", [])
		var part_descriptor = loaded.get("descriptor")
		if frames.is_empty() or part_descriptor == null:
			continue
		var resolved: Dictionary = part_descriptor.resolve(facing, animation_time, frames.size())
		var frame_index := int(resolved.get("frame_index", 0))
		var texture: Texture2D = frames[frame_index]
		result.append({
			"texture": texture,
			"frame_index": frame_index,
			"asset_name": part_descriptor.asset_name,
			"graphic_id": int(loaded.get("graphic_id", -1)),
			"graphic_layer": int(loaded.get("graphic_layer", 20)),
			"mirrored": bool(resolved.get("mirrored", false)),
			"source_direction": int(resolved.get("source_direction", 0)),
			"direction_degrees": int(resolved.get("direction_degrees", 0)),
			"hotspot": part_descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height())),
			"screen_offset": loaded.get("screen_offset", Vector2.ZERO),
		})
	return result


func _source_graphic_id(archetype: Dictionary, field: String, team: int, source_unit_id: int = -1) -> int:
	if source_unit_id >= 0:
		var civilization_id := int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
		var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, source_unit_id], {})
		if source.is_empty():
			source = object_catalog.get("objects", {}).get("0:%d" % source_unit_id, {})
		return int(source.get("graphics", {}).get(field, -1))
	var records: Dictionary = archetype.get("records", {})
	var civilization_id := team if String(archetype.get("civilization_scope", "team")) == "gaia" else int(archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13)))
	var record: Dictionary = records.get(String.num_int64(civilization_id), {})
	if record.is_empty() and not records.is_empty():
		var keys: Array = records.keys()
		keys.sort_custom(func(left, right): return int(left) < int(right))
		record = records.get(keys[0], {})
	return int(record.get("presentation", {}).get("graphics", {}).get(field, {}).get("graphic_id", -1))


func _records_by_name() -> Dictionary:
	var result: Dictionary = {}
	for record_value in asset_records:
		var record: Dictionary = record_value
		if String(record.get("archive", "")) != "graphics" or not record.has("frame"):
			continue
		var name := String(record.get("name", ""))
		if name.is_empty():
			continue
		if not result.has(name):
			result[name] = []
		result[name].append(record)
	for name in result:
		result[name].sort_custom(func(left, right): return int(left.get("frame", 0)) < int(right.get("frame", 0)))
	return result
