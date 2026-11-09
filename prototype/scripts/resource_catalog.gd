class_name RoRResourceCatalog

const GateCatalog := preload("res://scripts/gate_catalog.gd")
const PlayerPalette := preload("res://scripts/player_palette.gd")
var player_palette := PlayerPalette.new()

const EnvironmentPack := preload("res://scripts/environment_pack.gd")

const ShorelineTiles := preload("res://scripts/shoreline_tiles.gd")

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")
const CompositeGraphic := preload("res://scripts/composite_graphic.gd")
const FacingConvention := preload("res://scripts/facing_convention.gd")
const BuildingPresentationRegistry := preload("res://scripts/building_presentation_registry.gd")
const ResourcePresentationRegistry := preload("res://scripts/resource_presentation_registry.gd")
const UnitPresentationRegistry := preload("res://scripts/unit_presentation_registry.gd")
const ProjectilePresentationRegistry := preload("res://scripts/projectile_presentation_registry.gd")
const EffectPresentationRegistry := preload("res://scripts/effect_presentation_registry.gd")
const InterfaceIconRegistry := preload("res://scripts/interface_icon_registry.gd")
const InterfaceSkin := preload("res://scripts/interface_skin.gd")
const LocalizationCatalog := preload("res://scripts/localization_catalog.gd")
const CORPSE_GRAPHIC_IDS := {"villager": 141, "clubman": 138, "archer": 135}
const SPECIAL_GRAPHIC_IDS := {
	"villager": {"work_food": 470, "work_wood": 467, "work_mine": 474, "carry_food": 681, "carry_wood": 93, "carry_stone": 94, "carry_gold": 91},
}

var environment_pack := EnvironmentPack.new()

var terrain_textures := {}
var terrain_all_textures := {}
var terrain_border_textures := {}
var town_center_texture: Texture2D
var town_center_construction_textures: Array = []
var tree_texture: Texture2D
var tree_stump_textures: Array = []
var berry_texture: Texture2D
var interface_panel_texture: Texture2D
var unit_textures := {}
var gamespec_data: Dictionary = {}
var graphics_catalog_data: Dictionary = {}
var object_catalog_data: Dictionary = {}
var localization_data: Dictionary = {}
var sound_catalog_data: Dictionary = {}
var terrain_catalog_data: Dictionary = {}
var runtime_catalog_data: Dictionary = {}
var scenario_catalog_data: Dictionary = {}
var interface_source_inventory_data: Dictionary = {}
var localization := LocalizationCatalog.new()
var asset_metadata: Dictionary = {}
var asset_records: Array = []
var asset_frame_records_by_archive: Dictionary = {}
var audio_asset_files_by_resource_id: Dictionary = {}
var graphic_descriptors: Dictionary = {}
var composite_textures: Dictionary = {}
var composite_descriptors: Dictionary = {}
var scenario_marker_textures: Dictionary = {}
var performance_probe: Variant = null
var source_resource_textures: Dictionary = {}
var source_resource_frame_metadata: Dictionary = {}
var source_resource_descriptors: Dictionary = {}
var source_resource_descriptor_hits := 0
var source_resource_descriptor_misses := 0
const MAX_RESOURCE_DESCRIPTORS := 8192
var environment_graphic_descriptors: Dictionary = {}
var building_presentations := BuildingPresentationRegistry.new()
var resource_presentations := ResourcePresentationRegistry.new()
var unit_presentations := UnitPresentationRegistry.new()
var projectile_presentations := ProjectilePresentationRegistry.new()
var effect_presentations := EffectPresentationRegistry.new()
var interface_icons := InterfaceIconRegistry.new()
var interface_skin := InterfaceSkin.new()
var presentation_metadata_ready := false

func load() -> void:
	load_generated_data()
	for step in range(5): _configure_presentation_step(step)


func configure_presentations_async(tree: SceneTree, progress: Callable) -> void:
	for step in range(5):
		if progress.is_valid(): progress.call(float(step) / 5.0, "Подготовка оформления")
		await tree.process_frame
		_configure_presentation_step(step)


func prepare_presentation_metadata() -> void:
	# Metadata only. A load job may build these private registries before their
	# ownership moves to presentation; no texture loading occurs in configure.
	if presentation_metadata_ready: return
	var graphics_frame_records: Dictionary = asset_frame_records_by_archive.get("graphics", {})
	var interface_frame_records: Dictionary = asset_frame_records_by_archive.get("interfac", {})
	player_palette.configure_assets(asset_records)
	unit_presentations.player_palette = player_palette
	building_presentations.player_palette = player_palette
	effect_presentations.player_palette = player_palette
	interface_icons.player_palette = player_palette
	interface_skin.configure(asset_records, interface_source_inventory_data, interface_frame_records)
	effect_presentations.configure(graphics_catalog_data, asset_records, graphics_frame_records)
	unit_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_records, effect_presentations, graphics_frame_records)
	unit_textures = unit_presentations.textures
	building_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_metadata, graphics_frame_records)
	resource_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_records, graphics_frame_records)
	projectile_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_records, graphics_frame_records)
	interface_icons.configure(asset_records, interface_frame_records)
	presentation_metadata_ready = true


func _configure_presentation_step(step: int) -> void:
	match step:
		0:
			prepare_presentation_metadata()
			scenario_marker_textures.clear()
			source_resource_textures.clear()
			source_resource_frame_metadata.clear()
			source_resource_descriptors.clear()
			environment_graphic_descriptors.clear()
		1:
			terrain_textures = {
				"grass": load_frames("terrain_grass", 9),
				"sand": load_frames("terrain_sand", 9),
				"water": load_frames("terrain_water", 4),
				"water_dark": load_frames("terrain_water_dark", 4),
			}
			terrain_all_textures = {
				"grass": load_frames("terrain_grass", 25),
				"sand": load_frames("terrain_sand", 25),
				"water": load_frames("terrain_water", 20),
				"water_dark": load_frames("terrain_water_dark", 20),
			}
			terrain_border_textures = {
				2: load_frames("border_desert_water", 12),
				3: load_frames("border_grass_water", 12),
				7: load_frames("border_water_dark", 4),
				4: load_frames("border_grass_desert", 12),
				5: load_frames("border_grass_forest", 12),
				6: load_frames("border_grass_desert2", 4),
			}
		2:
			var shoreline_hotspots: Array = []
			for frame in range(12):
				var hotspot: Array = get_texture_metadata("border_desert_water", frame).get("hotspot", [0, 0])
				shoreline_hotspots.append(Vector2i(hotspot[0], hotspot[1]))
			terrain_border_textures[8] = ShorelineTiles.build_frames(terrain_border_textures[2], shoreline_hotspots, terrain_textures["water"][0])
			town_center_texture = load("res://assets/generated/town_center.png")
			town_center_construction_textures = load_frames("town_center_construction", 4)
			tree_texture = load("res://assets/generated/tree.png")
			tree_stump_textures = load_frames("tree_stump", 4)
			berry_texture = load("res://assets/generated/berry_bush.png")
			interface_panel_texture = interface_skin.panel_texture(0)
			if interface_panel_texture == null:
				interface_panel_texture = load("res://assets/generated/interface_panel.png")
		3:
			load_composite_graphics()
		4:
			build_graphic_descriptors()

func configure_player_colors(players: Array) -> void:
	player_palette.configure_players(players)


func rally_flag_frame_info(team: int, animation_time: float) -> Dictionary:
	return effect_presentations.frame_info_for(322, team, animation_time)


func prewarm_match_entities(units: Array, buildings: Array, resources: Array = [], scenery: Array = []) -> void:
	unit_presentations.prewarm_units(units)
	building_presentations.gate_presentations.prewarm_textures()
	building_presentations.prewarm_buildings(buildings)
	for building in buildings:
		if String(building.get("state", "")) == "complete":
			rally_flag_frame_info(int(building.get("team", 1)), 0.0)
	var projectile_source_ids: Dictionary = {}
	for unit_value in units + buildings:
		var unit: Dictionary = unit_value
		var source_unit_id := int(unit.get("projectile_id", -1))
		if source_unit_id >= 0:
			projectile_source_ids[source_unit_id] = true
	var ordered_projectile_ids: Array = projectile_source_ids.keys()
	ordered_projectile_ids.sort()
	for source_unit_id_value in ordered_projectile_ids:
		var projectile_source_id := int(source_unit_id_value)
		projectile_presentations.ensure_loaded(projectile_source_id)
		var source: Dictionary = object_catalog_data.get("objects", {}).get("0:%d" % projectile_source_id, {})
		var impact_id := int(source.get("graphics", {}).get("death", -1))
		if impact_id >= 0:
			effect_presentations.frame_info({"graphic_id": impact_id, "team": 1, "elapsed": 0.0})

	var resource_assets := {}
	for resource in resources: _collect_resource_prewarm_assets(resource, resource_assets)
	for item in scenery: _collect_scenery_prewarm_assets(item, resource_assets)
	for asset_name in resource_assets:
		if environment_pack.owns_asset(String(asset_name)): environment_pack.prewarm_object_textures(String(asset_name))
		else: _cache_source_resource_frames(String(asset_name))


func prewarm_match_entities_async(units: Array, buildings: Array, tree: SceneTree, progress: Callable, resources: Array = [], scenery: Array = []) -> void:
	var unit_progress := func(value: float, stage: String):
		if progress.is_valid(): progress.call(value * 0.7, stage)
	await unit_presentations.prewarm_units_async(units, tree, unit_progress)
	building_presentations.gate_presentations.prewarm_textures()
	var started := Time.get_ticks_usec()
	for index in range(buildings.size()):
		var building: Dictionary = buildings[index]
		building_presentations.prewarm_buildings([building])
		if String(building.get("state", "")) == "complete": rally_flag_frame_info(int(building.get("team", 1)), 0.0)
		if Time.get_ticks_usec() - started >= 6000:
			if progress.is_valid(): progress.call(0.7 + float(index + 1) / maxi(1, buildings.size()) * 0.1, "Подготовка зданий: %d/%d" % [index + 1, buildings.size()])
			await tree.process_frame
			started = Time.get_ticks_usec()
	var projectile_ids := {}
	for entity in units + buildings:
		var source_id := int(entity.get("projectile_id", -1))
		if source_id >= 0: projectile_ids[source_id] = true
	var ordered: Array = projectile_ids.keys()
	ordered.sort()
	for index in range(ordered.size()):
		var source_id := int(ordered[index])
		projectile_presentations.ensure_loaded(source_id)
		var source: Dictionary = object_catalog_data.get("objects", {}).get("0:%d" % source_id, {})
		var impact_id := int(source.get("graphics", {}).get("death", -1))
		if impact_id >= 0: effect_presentations.frame_info({"graphic_id": impact_id, "team": 1, "elapsed": 0.0})
		if progress.is_valid(): progress.call(0.8 + float(index + 1) / maxi(1, ordered.size()) * 0.05, "Подготовка выстрелов")
		await tree.process_frame
	# Include hidden map resources and their depleted/felled graphics. Seeing a
	# new area must not load a complete animation inside a gameplay frame.
	var resource_assets := {}
	started = Time.get_ticks_usec()
	for index in range(resources.size()):
		_collect_resource_prewarm_assets(resources[index], resource_assets)
		if Time.get_ticks_usec() - started >= 6000:
			if progress.is_valid(): progress.call(0.85 + float(index + 1) / maxi(1, resources.size()) * 0.01, "Подготовка ресурсов карты")
			await tree.process_frame
			started = Time.get_ticks_usec()
	for index in range(scenery.size()):
		_collect_scenery_prewarm_assets(scenery[index], resource_assets)
		if Time.get_ticks_usec() - started >= 6000:
			if progress.is_valid(): progress.call(0.86 + float(index + 1) / maxi(1, scenery.size()) * 0.01, "Подготовка окружения карты")
			await tree.process_frame
			started = Time.get_ticks_usec()
	var resource_names: Array = resource_assets.keys()
	resource_names.sort()
	for index in range(resource_names.size()):
		var resource_progress := func(value: float):
			if progress.is_valid(): progress.call(0.87 + (float(index) + value) / maxi(1, resource_names.size()) * 0.13, "Подготовка ресурсов: %d/%d" % [index + 1, resource_names.size()])
		var asset_name := String(resource_names[index])
		if environment_pack.owns_asset(asset_name): await environment_pack.prewarm_object_textures_async(asset_name, tree, resource_progress)
		else: await _cache_source_resource_frames_async(asset_name, tree, resource_progress)
	if progress.is_valid(): progress.call(1.0, "Графика подготовлена")


func _collect_resource_prewarm_assets(resource: Dictionary, assets: Dictionary) -> void:
	for asset_name in resource_presentations.prewarm_asset_names(resource):
		if environment_pack.owns_asset(asset_name) or resource_presentations.has_frame_records(asset_name): assets[asset_name] = true
	if environment_pack.enabled and resource.has("environment_asset"):
		var decorated_asset := EnvironmentPack.PREFIX + String(resource["environment_asset"])
		if environment_pack.owns_asset(decorated_asset): assets[decorated_asset] = true
	if String(resource.get("kind", "")) != "tree": return
	var felled_asset := String(resource.get("source_felled_asset_name", "graphic_636"))
	if resource_presentations.has_frame_records(felled_asset): assets[felled_asset] = true
	# The tree crown and its ground shadow can be separate DAT graphics.
	var spec := resource_presentations.graphic_for_resource(resource)
	for delta in spec.get("deltas", []):
		var graphic_id := int(delta.get("graphic_id", -1))
		var part: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
		if int(part.get("layer", -1)) != 0: continue
		if not CompositeGraphic.delta_visible(int(delta.get("display_angle", -1)), 0, int(spec.get("angle_count", 1))): continue
		var asset_name := "graphic_%d" % graphic_id
		if resource_presentations.has_frame_records(asset_name): assets[asset_name] = true


func _collect_scenery_prewarm_assets(item: Dictionary, assets: Dictionary) -> void:
	var graphic_id := int(item.get("graphic_id", -1))
	var asset_name := String(item.get("asset_name", ""))
	if graphic_id == 107 and String(item.get("kind", "")) == "cliff" or String(item.get("river_feature", "")) == "ledge":
		asset_name = "cliff_grounded"
	elif String(item.get("presentation_layer", "scenery")) == "ambient_actor":
		var source: Dictionary = object_catalog_data.get("objects", {}).get("0:%d" % int(item.get("source_unit_id", -1)), {})
		var movement_id := int(item.get("movement_graphic_id", source.get("graphics", {}).get("move", -1)))
		if movement_id >= 0: asset_name = String(item.get("movement_asset_name", "graphic_%d" % movement_id))
	if environment_pack.owns_asset(asset_name) or resource_presentations.has_frame_records(asset_name): assets[asset_name] = true


func _cache_source_resource_frames_async(asset_name: String, tree: SceneTree, progress: Callable) -> void:
	if source_resource_textures.has(asset_name): return
	var records: Array = resource_presentations.valid_frame_records(asset_name)
	var frames: Array = []
	var metadata: Array = []
	var started := Time.get_ticks_usec()
	for index in range(records.size()):
		var record: Dictionary = records[index]
		var texture: Texture2D = load("res://assets/generated/%s" % String(record.get("file", "")))
		if texture != null:
			frames.append(texture)
			metadata.append(record.duplicate(true))
		if Time.get_ticks_usec() - started >= 6000:
			if progress.is_valid(): progress.call(float(index + 1) / maxi(1, records.size()))
			await tree.process_frame
			started = Time.get_ticks_usec()
	# Publish only complete arrays, with the same ordering and metadata as the
	# synchronous fallback. No texture or animation frame is discarded.
	source_resource_textures[asset_name] = frames
	source_resource_frame_metadata[asset_name] = metadata
	if progress.is_valid(): progress.call(1.0)


func read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open generated data: %s" % path)
		return null
	return JSON.parse_string(file.get_as_text())

func load_generated_data() -> void:
	presentation_metadata_ready = false
	asset_metadata.clear()
	asset_records.clear()
	asset_frame_records_by_archive.clear()
	audio_asset_files_by_resource_id.clear()
	var parsed_gamespec = read_json("res://assets/generated/gamespec-prototype.json")
	if parsed_gamespec is Dictionary:
		gamespec_data = parsed_gamespec
	var parsed_assets = read_json("res://assets/generated/assets.json")
	if parsed_assets is Array:
		for item_value in parsed_assets:
			if not item_value is Dictionary:
				continue
			var item: Dictionary = item_value
			# Parsed generated catalogs are immutable runtime data. Retaining their
			# dictionaries avoids a second deep copy of the 12+ MB asset manifest.
			asset_records.append(item)
			if item.has("frame"):
				asset_metadata[asset_key(item["name"], int(item["frame"]))] = item
				var archive := String(item.get("archive", ""))
				var name := String(item.get("name", ""))
				if not archive.is_empty() and not name.is_empty():
					if not asset_frame_records_by_archive.has(archive):
						asset_frame_records_by_archive[archive] = {}
					var archive_records: Dictionary = asset_frame_records_by_archive[archive]
					if not archive_records.has(name):
						archive_records[name] = []
					archive_records[name].append(item)
			if String(item.get("extension", "")).to_lower() == "wav" and item.has("id"):
				audio_asset_files_by_resource_id[int(item["id"])] = String(item.get("file", ""))
		for grouped_records_value in asset_frame_records_by_archive.values():
			var grouped_records: Dictionary = grouped_records_value
			for records_value in grouped_records.values():
				var records: Array = records_value
				records.sort_custom(func(left, right): return int(left.get("frame", 0)) < int(right.get("frame", 0)))
	var parsed_graphics = read_json("res://assets/generated/graphics-catalog.json")
	if parsed_graphics is Dictionary:
		graphics_catalog_data = parsed_graphics
	var parsed_objects = read_json("res://assets/generated/objects-catalog.json")
	if parsed_objects is Dictionary:
		object_catalog_data = parsed_objects
	var parsed_localization = read_json("res://assets/generated/localization-catalog.json")
	if parsed_localization is Dictionary:
		localization_data = parsed_localization
		localization.load_data(localization_data)
	var parsed_sounds = read_json("res://assets/generated/sound-catalog.json")
	if parsed_sounds is Dictionary:
		sound_catalog_data = parsed_sounds
	var parsed_terrain = read_json("res://assets/generated/terrain-catalog.json")
	if parsed_terrain is Dictionary:
		terrain_catalog_data = parsed_terrain
	var parsed_runtime = read_json("res://assets/generated/runtime-catalog.json")
	if parsed_runtime is Dictionary:
		runtime_catalog_data = parsed_runtime
	GateCatalog.install_objects(object_catalog_data)
	GateCatalog.install_runtime(runtime_catalog_data)
	var parsed_scenarios = read_json("res://assets/generated/scenario-catalog.json")
	if parsed_scenarios is Dictionary:
		scenario_catalog_data = parsed_scenarios
	var parsed_interface_inventory = read_json("res://assets/generated/interface-source-inventory.json")
	if parsed_interface_inventory is Dictionary:
		interface_source_inventory_data = parsed_interface_inventory

func asset_key(name: String, frame: int) -> String:
	return "%s:%d" % [name, frame]

func load_frames(prefix: String, count: int) -> Array:
	var frames: Array = []
	for index in range(count):
		frames.append(load("res://assets/generated/%s_%02d.png" % [prefix, index]))
	return frames


func unit_stats(kind: String) -> Dictionary:
	return gamespec_data.get("units", {}).get(kind, {})

func get_texture_metadata(name: String, frame: int) -> Dictionary:
	return asset_metadata.get(asset_key(name, frame), {})


func get_terrain_border_texture(border_id: int, frame: int) -> Texture2D:
	var frames: Array = terrain_border_textures.get(border_id, [])
	if frame < 0 or frame >= frames.size():
		return null
	return frames[frame]

func get_graphic_descriptor(texture_key: String, animation_state: String) -> Variant:
	return unit_presentations.descriptor(texture_key, animation_state)


func has_unit_presentation(texture_key: String) -> bool:
	return unit_presentations.has_unit(texture_key)


func unit_presentation_keys() -> Array:
	return unit_presentations.presentation_keys()


func unit_animation_states(texture_key: String) -> Array:
	return unit_presentations.animation_states(texture_key)


func unit_animation_frames(texture_key: String, animation_state: String) -> Array:
	return unit_presentations.animation_frames(texture_key, animation_state)

func build_graphic_descriptors() -> void:
	graphic_descriptors = unit_presentations.descriptors


func load_composite_graphics() -> void:
	composite_textures.clear()
	composite_descriptors.clear()
	for key in gamespec_data.get("graphics", {}):
		var spec: Dictionary = gamespec_data["graphics"][key]
		var frame_count := maxi(1, int(spec.get("frames_per_angle", 1)) * int(spec.get("angle_count", 1)))
		var asset_name := "graphic_%s" % key
		if not ResourceLoader.exists("res://assets/generated/%s_00.png" % asset_name):
			continue
		var frames := load_frames(asset_name, frame_count)
		var descriptor := GraphicDescriptor.new(asset_name, spec, frames.size(), true)
		var hotspots: Array[Vector2] = []
		for frame_index in range(frames.size()):
			var texture: Texture2D = frames[frame_index]
			var metadata := get_texture_metadata(asset_name, frame_index)
			var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
			if metadata.has("hotspot"):
				hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
			hotspots.append(hotspot)
		descriptor.set_hotspots(hotspots)
		composite_textures[String(key)] = frames
		composite_descriptors[String(key)] = descriptor

func get_composite_parts(base_graphic_id: int, logical_facing: int, animation_time: float) -> Array:
	var result: Array = []
	var visited: Dictionary = {}
	_append_composite_parts(result, base_graphic_id, logical_facing, animation_time, Vector2.ZERO, visited)
	return result


func building_frame_info(building: Dictionary, animation_time: float = 0.0, retain_static: bool = false) -> Dictionary:
	return building_presentations.frame_info(building, animation_time, retain_static)


func resource_frame_info(resource: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var phase := String(resource.get("tree_phase", ""))
	if String(resource.get("kind", "")) == "tree" and phase == "felled" and int(resource.get("amount", 0)) > 0:
		var felled := resource.duplicate()
		felled["source_graphic_id"] = int(resource.get("source_felled_graphic_id", 636))
		felled["source_graphic_asset_name"] = String(resource.get("source_felled_asset_name", "graphic_636"))
		felled["source_frame"] = posmod(int(resource.get("id", 0)), 2)
		return source_resource_frame_info(felled, animation_time)
	var result := _standing_resource_frame_info(resource, animation_time)
	if phase == "falling" and not result.is_empty():
		result = result.duplicate()
		var progress := clampf(float(resource.get("tree_fall_elapsed", 0.0)) / maxf(0.01, float(resource.get("tree_fall_duration", 0.65))), 0.0, 1.0)
		result["rotation"] = (1.0 if int(resource.get("id", 0)) % 2 == 0 else -1.0) * progress * progress * PI * 0.5
		result["fall_opacity"] = 1.0 - progress * 0.5
	return result


func _standing_resource_frame_info(resource: Dictionary, animation_time: float) -> Dictionary:
	if environment_pack.enabled and resource.has("environment_asset"):
		var presentation := environment_pack.frame_info(resource, true, String(resource["environment_asset"]), int(resource.get("environment_variant", 0)))
		if not presentation.is_empty(): return presentation
	if environment_pack.owns_asset(String(resource.get("source_graphic_asset_name", ""))):
		return environment_pack.frame_info(resource, true)
	var source_frame := source_resource_frame_info(resource, animation_time)
	if not source_frame.is_empty():
		return source_frame
	var result := resource_presentations.frame_info(resource, animation_time)
	# Legacy/default resources resolve through an alias rather than an explicit
	# source_graphic_id; their DAT shadow is required by the same contract.
	if not result.is_empty() and String(resource.get("kind", "")) == "tree" and ResourcePresentationRegistry.tree_canopy_visible(resource):
		var shadow := _source_tree_shadow(resource_presentations.graphic_for_resource(resource), int(result.get("frame_index", 0)))
		if not shadow.is_empty(): result["shadow"] = shadow
	return result


func source_resource_frame_info(resource: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var depleted := int(resource.get("amount", 0)) <= 0
	if depleted and (ResourcePresentationRegistry.is_carcass(resource) or String(resource.get("kind", "")) in ResourcePresentationRegistry.ANIMATED_MARINE_KINDS):
		return {}
	var graphic_field := "source_depleted_graphic_id" if depleted else "source_graphic_id"
	var asset_field := "source_depleted_asset_name" if depleted else "source_graphic_asset_name"
	var graphic_id := int(resource.get(graphic_field, -1))
	var asset_name := String(resource.get(asset_field, ""))
	var spec: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
	if graphic_id < 0 or asset_name.is_empty() or spec.is_empty():
		return {}
	if not source_resource_textures.has(asset_name):
		_cache_source_resource_frames(asset_name)
	var frames: Array = source_resource_textures.get(asset_name, [])
	if frames.is_empty():
		return {}
	var frame_index := frames.size() - 1 if depleted else posmod(int(resource.get("source_frame", int(resource.get("id", 0)))), frames.size())
	if not depleted and int(resource.get("source_frame", -1)) < 0:
		frame_index = posmod(int(resource.get("id", 0)), frames.size())
	var mirrored := false
	if ResourcePresentationRegistry.is_carcass(resource):
		var resolved := ResourcePresentationRegistry.corpse_frame(resource, frames.size(), spec)
		frame_index = int(resolved["frame_index"])
		mirrored = bool(resolved["mirrored"])
	elif not depleted and String(resource.get("kind", "")) in ResourcePresentationRegistry.ANIMATED_MARINE_KINDS:
		frame_index = ResourcePresentationRegistry.animation_frame(resource, int(resource.get("id", 0)), animation_time, frames.size(), spec)
	var canopy := String(resource.get("kind", "")) == "tree" and ResourcePresentationRegistry.tree_canopy_visible(resource)
	var descriptor_key := [asset_name,graphic_id,frame_index,mirrored,canopy]
	if source_resource_descriptors.has(descriptor_key):
		source_resource_descriptor_hits += 1
		return source_resource_descriptors[descriptor_key]
	source_resource_descriptor_misses += 1
	var texture: Texture2D = frames[frame_index]
	if texture == null:
		return {}
	var frame_metadata: Array = source_resource_frame_metadata.get(asset_name, [])
	var metadata: Dictionary = frame_metadata[frame_index] if frame_index < frame_metadata.size() else {}
	var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
	if metadata.has("hotspot"):
		hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	var result := {
		"texture": texture,
		"asset_name": asset_name,
		"graphic_id": graphic_id,
		"frame_index": frame_index,
		"hotspot": hotspot,
		"mirrored": mirrored,
		"graphic_layer": int(spec.get("layer", 20)),
	}
	if canopy:
		var shadow := _source_tree_shadow(spec, frame_index)
		if not shadow.is_empty():
			shadow.make_read_only()
			result["shadow"] = shadow
	result.make_read_only()
	if source_resource_descriptors.size() >= MAX_RESOURCE_DESCRIPTORS:
		var oldest: Variant
		for expired in source_resource_descriptors:
			oldest = expired
			break
		source_resource_descriptors.erase(oldest)
	source_resource_descriptors[descriptor_key] = result
	return result


func _source_tree_shadow(spec: Dictionary, source_frame: int) -> Dictionary:
	# Several RoR trees store the canopy and ground shadow in separate DAT
	# graphics. Resolve the original layer and its own hotspot, as for AoE2.
	for delta in spec.get("deltas", []):
		var graphic_id := int(delta.get("graphic_id", -1))
		var part: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
		if part.is_empty() or int(part.get("layer", -1)) != 0: continue
		if not CompositeGraphic.delta_visible(int(delta.get("display_angle", -1)), 0, int(spec.get("angle_count", 1))): continue
		var asset_name := "graphic_%d" % graphic_id
		if not source_resource_textures.has(asset_name): _cache_source_resource_frames(asset_name)
		var frames: Array = source_resource_textures.get(asset_name, [])
		if frames.is_empty(): continue
		var index := posmod(source_frame, frames.size())
		var texture: Texture2D = frames[index]
		var metadata: Dictionary = source_resource_frame_metadata[asset_name][index]
		var hotspot: Array = metadata.get("hotspot", [texture.get_width() * 0.5, texture.get_height()])
		return {"texture": texture, "asset_name": asset_name, "graphic_id": graphic_id, "frame_index": index,
			"hotspot": Vector2(hotspot[0], hotspot[1]) - Vector2(float(delta.get("offset_x", 0)), float(delta.get("offset_y", 0))),
			"mirrored": false}
	return {}


func _cache_source_resource_frames(asset_name: String) -> void:
	var started := Time.get_ticks_usec() if performance_probe != null else 0
	var frames: Array = []
	var frame_metadata: Array = []
	var records_started := Time.get_ticks_usec() if performance_probe != null else 0
	# The generated manifest remains authoritative for frame membership.
	var records: Array = resource_presentations.valid_frame_records(asset_name) if resource_presentations.has_frame_records(asset_name) else []
	if performance_probe != null: performance_probe.observe_microseconds("presentation.resource_asset.records." + asset_name, Time.get_ticks_usec() - records_started)
	for record_value in records:
		var record: Dictionary = record_value
		var texture_started := Time.get_ticks_usec() if performance_probe != null else 0
		var texture: Texture2D = load("res://assets/generated/%s" % String(record.get("file", "")))
		if performance_probe != null: performance_probe.observe_microseconds("presentation.resource_asset.texture." + asset_name, Time.get_ticks_usec() - texture_started)
		if texture == null: continue
		frames.append(texture)
		var metadata_started := Time.get_ticks_usec() if performance_probe != null else 0
		frame_metadata.append(record.duplicate(true))
		if performance_probe != null: performance_probe.observe_microseconds("presentation.resource_asset.metadata." + asset_name, Time.get_ticks_usec() - metadata_started)
	source_resource_textures[asset_name] = frames
	source_resource_frame_metadata[asset_name] = frame_metadata
	if performance_probe != null: performance_probe.observe_microseconds("presentation.resource_asset.total." + asset_name, Time.get_ticks_usec() - started)


func projectile_frame_info(projectile: Dictionary) -> Dictionary:
	return projectile_presentations.frame_info(projectile)


func effect_frame_info(effect: Dictionary) -> Dictionary:
	return effect_presentations.frame_info(effect)


func enable_environment_pack() -> bool:
	if not environment_pack.enable():
		return false
	environment_pack.prepare_legacy_terrain(terrain_textures)
	return true


func environment_frame_info(item: Dictionary, animation_time: float = 0.0) -> Dictionary:
	if item.get("shoreline_detail",false):
		return preload("res://scripts/shoreline_presentation.gd").frame_info(item,[environment_pack.shoreline_texture(false),environment_pack.shoreline_texture(true)])
	if item.get("river_feature","") == "ledge":
		if not source_resource_textures.has("cliff_grounded"): _cache_source_resource_frames("cliff_grounded")
		return preload("res://scripts/river_feature_presentation.gd").frame_info(item,source_resource_textures.get("cliff_grounded",[]),animation_time,environment_pack.river_presentation_materials() if environment_pack.enabled else {})
	if environment_pack.owns_asset(String(item.get("asset_name", ""))):
		return environment_pack.frame_info(item)
	var graphic_id := int(item.get("graphic_id", -1))
	var asset_name := String(item.get("asset_name", ""))
	if graphic_id == 107 and String(item.get("kind", "")) == "cliff":
		asset_name = "cliff_grounded"
	var ambient_actor := String(item.get("presentation_layer", "scenery")) == "ambient_actor"
	if ambient_actor:
		var source_unit_id := int(item.get("source_unit_id", -1))
		var source_record: Dictionary = object_catalog_data.get("objects", {}).get("0:%d" % source_unit_id, {})
		var movement_graphic_id := int(item.get("movement_graphic_id", source_record.get("graphics", {}).get("move", -1)))
		if movement_graphic_id >= 0:
			graphic_id = movement_graphic_id
			asset_name = String(item.get("movement_asset_name", "graphic_%d" % movement_graphic_id))
	var spec: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
	if graphic_id < 0 or asset_name.is_empty() or spec.is_empty():
		return {}
	if not source_resource_textures.has(asset_name):
		_cache_source_resource_frames(asset_name)
	var frames: Array = source_resource_textures.get(asset_name, [])
	if frames.is_empty():
		return {}
	var source_frame := int(item.get("source_frame", -1))
	var frame_index := posmod(source_frame, frames.size()) if source_frame >= 0 else posmod(int(item.get("scenario_object_id", item.get("id", 0))), frames.size())
	var mirrored := false
	if ambient_actor:
		if not environment_graphic_descriptors.has(asset_name):
			environment_graphic_descriptors[asset_name] = GraphicDescriptor.new(asset_name, spec, frames.size(), true)
		var descriptor = environment_graphic_descriptors[asset_name]
		var movement_direction := Vector2(item.get("movement_direction", Vector2.RIGHT))
		var logical_facing := FacingConvention.logical_for_world(movement_direction, descriptor.logical_angle_count)
		var cycle_duration: float = float(descriptor.frames_per_angle) * float(descriptor.frame_duration)
		var phase: float = float(posmod(int(item.get("scenario_object_id", item.get("id", 0))) * 1618, 1000)) / 1000.0 * cycle_duration
		var resolved: Dictionary = descriptor.resolve(logical_facing, animation_time + phase, frames.size())
		frame_index = int(resolved.get("frame_index", 0))
		mirrored = bool(resolved.get("mirrored", false))
	else:
		var frame_rate := float(spec.get("frame_rate", 0.0))
		if bool(item.get("animated", false)) and frame_rate > 0.0:
			var phase := posmod(int(item.get("scenario_object_id", item.get("id", 0))) * 1618, 1000) / 1000.0
			frame_index = posmod(floori(animation_time / frame_rate + phase * frames.size()), frames.size())
	var texture: Texture2D = frames[frame_index]
	if texture == null:
		return {}
	var frame_metadata: Array = source_resource_frame_metadata.get(asset_name, [])
	var metadata: Dictionary = frame_metadata[frame_index] if frame_index < frame_metadata.size() else {}
	var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
	if metadata.has("hotspot"):
		hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	return {
		"texture": texture,
		"asset_name": asset_name,
		"graphic_id": graphic_id,
		"frame_index": frame_index,
		"hotspot": hotspot,
		"mirrored": mirrored,
		"graphic_layer": int(spec.get("layer", 0)),
		"screen_offset": Vector2(item.get("cliff_screen_offset", Vector2.ZERO)) if graphic_id == 107 and String(item.get("kind", "")) == "cliff" else Vector2.ZERO,
	}


func objective_frame_info(objective: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var presentation := objective.duplicate(false)
	presentation["position"] = objective.get("pos", Vector2.ZERO)
	return environment_frame_info(presentation, animation_time)


func scenario_marker_frame_info(marker: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var graphic_id := int(marker.get("graphic_id", -1))
	var asset_name := String(marker.get("asset_name", ""))
	var spec: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
	if graphic_id < 0 or asset_name.is_empty() or spec.is_empty():
		return {}
	if not scenario_marker_textures.has(asset_name):
		if not ResourceLoader.exists("res://assets/generated/%s_00.png" % asset_name):
			return {}
		var frame_count := maxi(1, int(spec.get("slp", {}).get("frame_count", 1)))
		scenario_marker_textures[asset_name] = load_frames(asset_name, frame_count)
	var frames: Array = scenario_marker_textures.get(asset_name, [])
	if frames.is_empty():
		return {}
	var frames_per_angle := clampi(int(spec.get("frames_per_angle", frames.size())), 1, frames.size())
	var frame_rate := maxf(0.001, float(spec.get("frame_rate", 0.1)))
	var initial_frame := maxi(0, int(marker.get("source_frame", 0)))
	var frame_index := posmod(initial_frame + floori(animation_time / frame_rate), frames_per_angle)
	var texture: Texture2D = frames[frame_index]
	if texture == null:
		return {}
	var metadata := get_texture_metadata(asset_name, frame_index)
	var hotspot := Vector2(texture.get_width() * 0.5, texture.get_height())
	if metadata.has("hotspot"):
		hotspot = Vector2(float(metadata["hotspot"][0]), float(metadata["hotspot"][1]))
	return {
		"texture": texture,
		"asset_name": asset_name,
		"graphic_id": graphic_id,
		"frame_index": frame_index,
		"hotspot": hotspot,
		"mirrored": false,
		"graphic_layer": int(spec.get("layer", 20)),
	}


func projectile_animation_frames(source_unit_id: int) -> Array:
	return projectile_presentations.animation_frames(source_unit_id)


func worker_resource_animation_state(resource_type_id: int, carrying: bool) -> String:
	var profiles: Dictionary = runtime_catalog_data.get("archetypes", {}).get("villager", {}).get("runtime", {}).get("worker_resource_profiles", {})
	var profile: Dictionary = profiles.get(String.num_int64(resource_type_id), {})
	if profile.is_empty():
		return "carry_food" if carrying else "work_food"
	return String(profile.get("carry_state" if carrying else "work_state", "carry_food" if carrying else "work_food"))


func unit_frame_info(unit: Dictionary, animation_state: String, animation_time: float = -1.0, ambient_time: float = -1.0) -> Dictionary:
	return unit_presentations.frame_info(unit, animation_state, animation_time, ambient_time)


func unit_presentation_state(unit: Dictionary, default_state: String) -> String:
	var overrides: Dictionary = unit.get("presentation_state_overrides", {})
	return String(overrides.get(String(unit.get("anim_state", "")), default_state))

func _append_composite_parts(result: Array, base_graphic_id: int, logical_facing: int, animation_time: float, inherited_offset: Vector2, visited: Dictionary) -> void:
	var base_key := String.num_int64(base_graphic_id)
	if visited.has(base_key):
		return
	visited[base_key] = true
	var base_spec: Dictionary = gamespec_data.get("graphics", {}).get(base_key, {})
	for delta in base_spec.get("deltas", []):
		var child_id := int(delta.get("graphic_id", -1))
		var child_key := String.num_int64(child_id)
		if child_id < 0 or not composite_descriptors.has(child_key):
			continue
		var child_spec: Dictionary = gamespec_data["graphics"].get(child_key, {})
		if not CompositeGraphic.delta_visible(int(delta.get("display_angle", -1)), logical_facing, int(child_spec.get("angle_count", 1))):
			continue
		var descriptor = composite_descriptors[child_key]
		var frames: Array = composite_textures[child_key]
		var resolved: Dictionary = descriptor.resolve(logical_facing, animation_time, frames.size())
		var frame_index := int(resolved["frame_index"])
		var texture: Texture2D = frames[frame_index]
		var offset := inherited_offset + Vector2(float(delta.get("offset_x", 0)), float(delta.get("offset_y", 0)))
		result.append({
			"graphic_id": child_id,
			"texture": texture,
			"asset_name": descriptor.asset_name,
			"frame_index": frame_index,
			"hotspot": descriptor.hotspot_for(frame_index, Vector2(texture.get_width() * 0.5, texture.get_height())),
			"mirrored": bool(resolved["mirrored"]),
			"screen_offset": offset,
			"graphic_layer": child_spec.get("layer", 20),
		})
		_append_composite_parts(result, child_id, logical_facing, animation_time, offset, visited)
	visited.erase(base_key)
