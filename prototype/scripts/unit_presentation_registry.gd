class_name RoRUnitPresentationRegistry
extends RefCounted
const ThreadedTextureQueue := preload("res://scripts/threaded_texture_queue.gd")
var texture_queue := ThreadedTextureQueue.new()
var pending_states: Dictionary = {}
var loading_generation := 1
var background_loading_enabled := false
var prewarming := false
const PREWARM_CLIPS_PER_WINDOW := 8
const PREWARM_FRAME_BUDGET_USEC := 5000
var prewarm_thread := Thread.new()
var prewarm_textures: Dictionary = {}

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const DamageSelector := preload("res://scripts/presentation_damage_selector.gd")
const AnimationController := preload("res://scripts/animation_controller.gd")

var player_palette
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
var source_records: Dictionary = {}
var loaded_states: Dictionary = {}
var effect_presentations

# Shared art is independent of an entity's position, health and selection.
# Exact animation times also preserve independently animated composite parts.
const MAX_POSE_RECORDS := 4096
var pose_cache_enabled := OS.get_environment("ROR_DIAGNOSTIC_UNIT_POSE_CACHE") != "0"
var pose_records: Dictionary = {}
var pose_cache_hits := 0
var pose_cache_misses := 0


func configure(runtime_data: Dictionary, object_data: Dictionary, graphics_data: Dictionary, records: Array, effect_registry = null, indexed_frame_records: Dictionary = {}) -> void:
	shutdown_loading()
	runtime_catalog = runtime_data
	object_catalog = object_data
	graphics_catalog = graphics_data
	asset_records = records
	textures.clear()
	descriptors.clear()
	graphic_ids.clear()
	composite_parts.clear()
	definitions.clear()
	source_records.clear()
	loaded_states.clear()
	pose_records.clear()
	pose_cache_hits = 0
	pose_cache_misses = 0
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
	ensure_loaded(texture_key, state)
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
	ensure_loaded(texture_key, state)
	return textures.get(texture_key, {}).get(state, [])


func _prewarm_plan(units: Array) -> Dictionary:
	var requested_states_by_key: Dictionary = {}
	var requested_effect_graphics: Dictionary = {}
	for unit_value in units:
		var unit: Dictionary = unit_value
		var texture_key := texture_key_for_unit(unit)
		if texture_key.is_empty():
			continue
		var requested: Dictionary = requested_states_by_key.get(texture_key, {})
		for state in ["idle", "move", "death", "corpse"]:
			requested[state] = true
		requested[AnimationController.clip_for_state(String(unit.get("anim_state", AnimationController.IDLE)))] = true
		var components: Dictionary = unit.get("components", {})
		if bool(unit.get("combat_enabled", false)) or float(unit.get("attack_damage", 0.0)) > 0.0:
			requested["attack"] = true
		if bool(components.get("worker", {}).get("enabled", false)):
			# Worker roles select source-specific states only after an order is
			# assigned (farmer_work, carry_wood, hunter_attack, ...). Prewarm the
			# states declared by the current worker definition; loading remains
			# limited to worker types that actually exist in this match.
			var state_specs: Dictionary = definitions.get(texture_key, {}).get("state_specs", {})
			for state_value in state_specs:
				requested[String(state_value)] = true
		if bool(components.get("conversion", {}).get("enabled", false)):
			requested["convert"] = true
		if bool(components.get("healing", {}).get("enabled", false)):
			requested["heal"] = true
		requested_states_by_key[texture_key] = requested
		if effect_presentations != null:
			var source := _source_record(archetype_for_unit(String(unit.get("kind", ""))), int(unit.get("source_unit_id", -1)), unit)
			for damage_value in source.get("graphics", {}).get("damage", []):
				var damage: Dictionary = damage_value
				var damage_graphic_id := int(damage.get("graphic_id", -1))
				if damage_graphic_id >= 0:
					requested_effect_graphics[Vector2i(damage_graphic_id, int(unit.get("team", 1)))] = true
			var impact_graphic_id := int(components.get("combat", {}).get("impact_effect_graphic_id", -1))
			if impact_graphic_id >= 0:
				requested_effect_graphics[Vector2i(impact_graphic_id, int(unit.get("team", 1)))] = true
	var states: Array = []
	var keys: Array = requested_states_by_key.keys()
	keys.sort()
	for key in keys:
		var names: Array = requested_states_by_key[key].keys()
		names.sort()
		for state in names: states.append([String(key), String(state)])
	var effects: Array = requested_effect_graphics.keys()
	effects.sort_custom(func(left, right): return left.x < right.x or (left.x == right.x and left.y < right.y))
	return {"states": states, "effects": effects}


func prewarm_units(units: Array) -> void:
	prewarming = true
	var plan := _prewarm_plan(units)
	for entry in plan["states"]: ensure_loaded(entry[0], entry[1])
	for key in plan["effects"]: effect_presentations.frame_info_for(key.x, key.y, 0.0)
	prewarming = false


func prewarm_units_async(units: Array, tree: SceneTree, progress: Callable) -> void:
	var plan := _prewarm_plan(units)
	var states: Array = plan["states"]
	var effects: Array = plan["effects"]
	var total := maxi(1, states.size() + effects.size())
	var generation := loading_generation
	var started := Time.get_ticks_usec()
	for first in range(0, states.size(), PREWARM_CLIPS_PER_WINDOW):
		var end := mini(first + PREWARM_CLIPS_PER_WINDOW, states.size())
		var distinct := {}
		for index in range(first, end):
			var key := String(states[index][0])
			var state := String(states[index][1])
			if loaded_states.get(key, {}).has(state): continue
			var definition: Dictionary = definitions.get(key, {})
			var spec: Dictionary = definition.get("state_specs", {}).get(state, {})
			for path in _state_paths(definition, spec): distinct[path] = true
		var paths: Array[String] = []
		paths.assign(distinct.keys())
		if not paths.is_empty():
			var loader := ThreadedTextureQueue.new()
			if prewarm_thread.start(loader.load_window.bind(paths)) == OK:
				if progress.is_valid(): progress.call(float(first) / total, "Загрузка анимаций: %d/%d" % [first, total])
				while prewarm_thread.is_alive():
					await tree.process_frame
					if generation != loading_generation: return
				prewarm_textures = prewarm_thread.wait_to_finish()
			else:
				while not loader.is_complete(paths):
					loader.request(paths)
					await tree.process_frame
					if generation != loading_generation: return
				prewarm_textures = loader.completed
		# Only whole clips become available. Palette conversion and publication
		# stay on the main thread. The next window reuses textures held by them.
		for index in range(first, end):
			_ensure_loaded_synchronous(states[index][0], states[index][1])
			if Time.get_ticks_usec() - started >= PREWARM_FRAME_BUDGET_USEC:
				if progress.is_valid(): progress.call(float(index + 1) / total, "Подготовка анимаций: %d/%d" % [index + 1, total])
				await tree.process_frame
				if generation != loading_generation: return
				started = Time.get_ticks_usec()
		prewarm_textures = {}
	for index in range(effects.size()):
		var key: Vector2i = effects[index]
		effect_presentations.frame_info_for(key.x, key.y, 0.0)
		if progress.is_valid(): progress.call(float(states.size() + index + 1) / total, "Подготовка эффектов")
		await tree.process_frame
		if generation != loading_generation: return

func texture_key_for_unit(unit: Dictionary) -> String:
	var alias := String(unit.get("kind", ""))
	var owner_team := int(unit.get("team", 1))
	var player: int = player_palette.color_index(owner_team) if player_palette != null else clampi(owner_team, 1, 8)
	var prefix := alias if player == 1 else "enemy_%s" % alias if player == 2 else "color_%d_%s" % [player, alias]
	if player > 2 and not definitions.has(prefix) and definitions.has(alias):
		var source: Dictionary = definitions[alias]
		_register_team(alias, prefix, player, source["archetype"], source["state_specs"])
	var neutral_prefix := "neutral_%s" % alias
	if owner_team <= 0 and definitions.has(neutral_prefix):
		prefix = neutral_prefix
	var source_id := int(unit.get("source_unit_id", -1))
	var variant_key := "%s#%d" % [prefix, source_id]
	var base_variant := "%s#%d" % [alias, source_id]
	if owner_team > 0 and player > 2 and definitions.has(base_variant) and not definitions.has(variant_key):
		var source: Dictionary = definitions[base_variant]
		_register_team(alias, variant_key, player, source["archetype"], source["state_specs"], source_id)
	return variant_key if definitions.has(variant_key) else prefix


func _state_paths(definition: Dictionary, state_spec: Dictionary) -> Array[String]:
	var team := int(definition.get("team", 1))
	var parts: Array = [state_spec]
	parts.append_array(state_spec.get("composite_parts", []))
	var paths: Array[String] = []
	var seen: Dictionary = {}
	for index in range(parts.size()):
		var part: Dictionary = parts[index]
		var base_name := String(part.get("asset_name", ""))
		var asset_name := String(part.get("neutral_asset_name", base_name)) if team <= 0 and index == 0 else String(part.get("enemy_asset_name", base_name)) if team == 2 else base_name
		var records: Array = records_by_name.get(asset_name, []).duplicate()
		if team > 2:
			records.append_array(records_by_name.get(String(part.get("enemy_asset_name", "")), []))
		if records.is_empty() and team == 2:
			records = records_by_name.get(base_name, [])
		for record in records:
			var path := "res://assets/generated/%s" % String(record.get("file", ""))
			if not seen.has(path):
				seen[path] = true
				paths.append(path)
	return paths

func poll_background_loading() -> void:
	texture_queue.poll()
	for key in pending_states.keys():
		var request: Dictionary = pending_states[key]
		texture_queue.request(request["paths"])
		if not texture_queue.is_complete(request["paths"]):
			continue
		var texture_key := String(request["texture_key"])
		var state := String(request["state"])
		var definition: Dictionary = definitions.get(texture_key, {})
		if int(request["generation"]) != loading_generation or definition.is_empty():
			pending_states.erase(key)
			continue
		var attempted: Dictionary = loaded_states.get(texture_key, {})
		attempted[state] = true
		loaded_states[texture_key] = attempted
		# All base and composite frame paths have finished before any state is
		# published. No partial composite becomes visible between frames.
		_load_team(String(definition.get("alias", "")), texture_key, int(definition.get("team", 1)), definition.get("archetype", {}), {state: request["spec"]}, int(definition.get("source_unit_id", -1)))
		pending_states.erase(key)
		# Several clips may share the same frame. Keep a completed resource until
		# every pending clip that references it has published its whole state.
		var releasable: Array[String] = []
		for path in request["paths"]:
			var still_needed := false
			for pending in pending_states.values():
				if path in pending["paths"]:
					still_needed = true
					break
			if not still_needed:
				releasable.append(path)
		texture_queue.release(releasable)

func ensure_loaded(texture_key: String, requested_state: String = "") -> void:
	# A ready clip does not need to poll unrelated pending animations for every
	# visible unit and composite part. The scene polls the queue once per frame.
	if not requested_state.is_empty() and loaded_states.get(texture_key, {}).has(requested_state): return
	if prewarming or not background_loading_enabled:
		_ensure_loaded_synchronous(texture_key, requested_state)
		return
	poll_background_loading()
	var definition: Dictionary = definitions.get(texture_key, {})
	var specs: Dictionary = definition.get("state_specs", {})
	var requested: Array = specs.keys() if requested_state.is_empty() else [requested_state]
	for state_value in requested:
		var state := String(state_value)
		if loaded_states.get(texture_key, {}).has(state):
			continue
		if not specs.has(state):
			var attempted: Dictionary = loaded_states.get(texture_key, {})
			attempted[state] = true
			loaded_states[texture_key] = attempted
			continue
		var key := texture_key + ":" + state
		if pending_states.has(key) or pending_states.size() >= 32:
			continue
		var paths := _state_paths(definition, specs[state])
		pending_states[key] = {"generation": loading_generation, "texture_key": texture_key, "state": state, "spec": specs[state], "paths": paths}
		texture_queue.request(paths)
	poll_background_loading()

func _texture_for_path(path: String) -> Texture2D:
	if prewarm_textures.has(path): return prewarm_textures[path]
	if prewarming or not background_loading_enabled:
		return load(path) as Texture2D
	return texture_queue.texture(path)

func shutdown_loading() -> void:
	loading_generation += 1
	if prewarm_thread.is_started(): prewarm_thread.wait_to_finish()
	prewarm_textures = {}
	pending_states.clear()
	pose_records.clear()
	texture_queue.shutdown()

func _ensure_loaded_synchronous(texture_key: String, requested_state: String = "") -> void:
	var attempted: Dictionary = loaded_states.get(texture_key, {})
	if not requested_state.is_empty() and attempted.has(requested_state):
		return
	var definition: Dictionary = definitions.get(texture_key, {})
	if definition.is_empty():
		return
	# Rendering needs one animation state. Loading the entire unit here decoded
	# every work/attack/death clip synchronously on its first visible frame.
	# Explicit callers without a state still request the complete animation set.
	var specs: Dictionary = definition.get("state_specs", {})
	var requested: Array = specs.keys() if requested_state.is_empty() else [requested_state]
	var missing: Dictionary = {}
	for state in requested:
		if attempted.has(state):
			continue
		attempted[state] = true
		if specs.has(state):
			missing[state] = specs[state]
	loaded_states[texture_key] = attempted
	if missing.is_empty():
		return
	_load_team(
		String(definition.get("alias", "")),
		texture_key,
		int(definition.get("team", 1)),
		definition.get("archetype", {}),
		missing,
		int(definition.get("source_unit_id", -1))
	)


func frame_info(unit: Dictionary, state: String, animation_time: float = -1.0, ambient_time: float = -1.0) -> Dictionary:
	var texture_key := texture_key_for_unit(unit)
	ensure_loaded(texture_key, state)
	# A missing/pending lifecycle clip must never resurrect the living sprite.
	var corpse_requested := state == "corpse" or state.ends_with("_corpse")
	var death_requested := state == "death" or state.ends_with("_death")
	var fallback_state := "death" if corpse_requested or death_requested else "idle"
	if corpse_requested:
		var role_death := state.trim_suffix("corpse") + "death"
		if definitions.get(texture_key, {}).get("state_specs", {}).has(role_death):
			fallback_state = role_death
	if not textures.get(texture_key, {}).has(state):
		ensure_loaded(texture_key, fallback_state)
	var time := float(unit.get("anim", 0.0)) if animation_time < 0.0 else animation_time
	var pose_key: Array = [texture_key, state, int(unit.get("facing", 0)), time]
	var base: Dictionary = pose_records.get(pose_key, {}) if pose_cache_enabled else {}
	if base.is_empty():
		base = _pose_frame_info(texture_key, state, fallback_state, int(unit.get("facing", 0)), time)
		if base.is_empty(): return {}
		if pose_cache_enabled:
			pose_cache_misses += 1
			for part in base["composite_parts"]: part.make_read_only()
			base["composite_parts"].make_read_only()
			base.make_read_only()
			pose_records[pose_key] = base
			while pose_records.size() > MAX_POSE_RECORDS:
				for oldest in pose_records:
					pose_records.erase(oldest)
					break
	else:
		pose_cache_hits += 1
	var hp := float(unit.get("hp", 0.0))
	var max_hp := maxf(1.0, float(unit.get("max_hp", 1.0)))
	if corpse_requested or death_requested or effect_presentations == null or hp + 0.0001 >= max_hp:
		return base
	# Damage belongs to this entity and has an independent ambient clock. Never
	# append it to the shared pose or retain a source entity in the cache.
	var source := _source_record(archetype_for_unit(String(unit.get("kind", ""))), int(unit.get("source_unit_id", -1)), unit)
	var damage_graphic_id := DamageSelector.select_graphic_id(unit, source)
	if damage_graphic_id < 0: return base
	var result := base.duplicate()
	var resolved_parts: Array = base["composite_parts"].duplicate()
	var damage_time := time if ambient_time < 0.0 else ambient_time
	var damage_part: Dictionary = effect_presentations.frame_info_for(damage_graphic_id, int(unit.get("team", 1)), damage_time)
	if not damage_part.is_empty():
		damage_part["effect_kind"] = "damage"
		resolved_parts.append(damage_part)
	result["composite_parts"] = resolved_parts
	result["damage_graphic_id"] = damage_graphic_id
	return result


func _pose_frame_info(texture_key: String, state: String, fallback_state: String, facing: int, time: float) -> Dictionary:
	var animation_sets: Dictionary = textures.get(texture_key, {})
	var resolved_state := state if animation_sets.has(state) else fallback_state
	var frames: Array = animation_sets.get(resolved_state, [])
	var graphic_descriptor = descriptor(texture_key, resolved_state)
	if frames.is_empty() or graphic_descriptor == null:
		return {}
	if (state == "corpse" or state.ends_with("_corpse")) and resolved_state != state:
		time = float(graphic_descriptor.frames_per_angle) * float(graphic_descriptor.frame_duration)
	var graphic_facing := FacingConvention.for_angle_count(facing, graphic_descriptor.logical_angle_count)
	var resolved: Dictionary = graphic_descriptor.resolve(graphic_facing, time, frames.size())
	var frame_index := int(resolved["frame_index"])
	var texture: Texture2D = frames[frame_index]
	var graphic_id := int(graphic_ids.get(texture_key, {}).get(resolved_state, -1))
	var resolved_parts := _resolved_composite_parts(texture_key, resolved_state, facing, time)
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
		"damage_graphic_id": -1,
	}


func archetype_for_unit(alias: String) -> Dictionary:
	return runtime_catalog.get("archetypes", {}).get(alias, {})


func _source_record(archetype: Dictionary, source_unit_id: int, unit: Dictionary) -> Dictionary:
	var resolved_source_id := source_unit_id if source_unit_id >= 0 else int(archetype.get("identifiers", {}).get("source_unit_id", -1))
	var civilization_id := int(unit.get("components", {}).get("ownership", {}).get("civilization_id", archetype.get("default_civilization_id", runtime_catalog.get("default_civilization_id", 13))))
	var cache_key := Vector2i(civilization_id, resolved_source_id)
	if source_records.has(cache_key):
		return source_records[cache_key]
	var source: Dictionary = object_catalog.get("objects", {}).get("%d:%d" % [civilization_id, resolved_source_id], {})
	if source.is_empty():
		source = object_catalog.get("objects", {}).get("0:%d" % resolved_source_id, {})
	source_records[cache_key] = source
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
	# Pending clips may replace a fallback while this registry is in use.
	pose_records.clear()
	if not textures.has(texture_key):
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
			var texture: Texture2D = _texture_for_path("res://assets/generated/%s" % String(record.get("file", "")))
			if texture == null:
				continue
			if team > 0 and player_palette != null:
				texture = player_palette.texture_for(record, texture, team)
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
		graphic_spec = graphic_spec.duplicate()
		graphic_spec.merge(state_spec.get("graphic_override", {}), true)
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
			var texture: Texture2D = _texture_for_path("res://assets/generated/%s" % String(record.get("file", "")))
			if texture == null:
				continue
			if team > 0 and player_palette != null:
				texture = player_palette.texture_for(record, texture, team)
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
		var part_facing := FacingConvention.for_angle_count(facing, part_descriptor.logical_angle_count)
		var resolved: Dictionary = part_descriptor.resolve(part_facing, animation_time, frames.size())
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
