class_name RoRResourceCatalog

const GraphicDescriptor := preload("res://scripts/graphic_descriptor.gd")
const CompositeGraphic := preload("res://scripts/composite_graphic.gd")
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
var graphic_descriptors: Dictionary = {}
var composite_textures: Dictionary = {}
var composite_descriptors: Dictionary = {}
var scenario_marker_textures: Dictionary = {}
var source_resource_textures: Dictionary = {}
var building_presentations := BuildingPresentationRegistry.new()
var resource_presentations := ResourcePresentationRegistry.new()
var unit_presentations := UnitPresentationRegistry.new()
var projectile_presentations := ProjectilePresentationRegistry.new()
var effect_presentations := EffectPresentationRegistry.new()
var interface_icons := InterfaceIconRegistry.new()
var interface_skin := InterfaceSkin.new()

func load() -> void:
	load_generated_data()
	scenario_marker_textures.clear()
	source_resource_textures.clear()
	terrain_textures = {
		"grass": load_frames("terrain_grass", 9),
		"sand": load_frames("terrain_sand", 9),
		"water": load_frames("terrain_water", 4),
	}
	terrain_all_textures = {
		"grass": load_frames("terrain_grass", 25),
		"sand": load_frames("terrain_sand", 25),
		"water": load_frames("terrain_water", 20),
	}
	terrain_border_textures = {
		2: load_frames("border_desert_water", 12),
		3: load_frames("border_grass_water", 12),
		4: load_frames("border_grass_desert", 12),
		5: load_frames("border_grass_forest", 12),
		6: load_frames("border_grass_desert2", 4),
	}
	town_center_texture = load("res://assets/generated/town_center.png")
	town_center_construction_textures = load_frames("town_center_construction", 4)
	tree_texture = load("res://assets/generated/tree.png")
	tree_stump_textures = load_frames("tree_stump", 4)
	berry_texture = load("res://assets/generated/berry_bush.png")
	interface_skin.configure(asset_records, interface_source_inventory_data)
	interface_panel_texture = interface_skin.texture("interface_panel")
	if interface_panel_texture == null:
		interface_panel_texture = load("res://assets/generated/interface_panel.png")
	effect_presentations.configure(graphics_catalog_data, asset_records)
	unit_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_records, effect_presentations)
	unit_textures = unit_presentations.textures
	build_graphic_descriptors()
	load_composite_graphics()
	building_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_metadata)
	resource_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_records)
	projectile_presentations.configure(runtime_catalog_data, object_catalog_data, graphics_catalog_data, asset_records)
	interface_icons.configure(asset_records)

func read_json(path: String):
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open generated data: %s" % path)
		return null
	return JSON.parse_string(file.get_as_text())

func load_generated_data() -> void:
	asset_metadata.clear()
	asset_records.clear()
	var parsed_gamespec = read_json("res://assets/generated/gamespec-prototype.json")
	if parsed_gamespec is Dictionary:
		gamespec_data = parsed_gamespec
	var parsed_assets = read_json("res://assets/generated/assets.json")
	if parsed_assets is Array:
		for item in parsed_assets:
			asset_records.append(item.duplicate(true))
			if item.has("frame"):
				asset_metadata[asset_key(item["name"], int(item["frame"]))] = item
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


func building_frame_info(building: Dictionary, animation_time: float = 0.0) -> Dictionary:
	return building_presentations.frame_info(building, animation_time)


func resource_frame_info(resource: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var source_frame := source_resource_frame_info(resource)
	if not source_frame.is_empty():
		return source_frame
	return resource_presentations.frame_info(resource, animation_time)


func source_resource_frame_info(resource: Dictionary) -> Dictionary:
	var depleted := int(resource.get("amount", 0)) <= 0
	var graphic_field := "source_depleted_graphic_id" if depleted else "source_graphic_id"
	var asset_field := "source_depleted_asset_name" if depleted else "source_graphic_asset_name"
	var graphic_id := int(resource.get(graphic_field, -1))
	var asset_name := String(resource.get(asset_field, ""))
	var spec: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
	if graphic_id < 0 or asset_name.is_empty() or spec.is_empty():
		return {}
	if not source_resource_textures.has(asset_name):
		var frame_count := maxi(1, int(spec.get("slp", {}).get("frame_count", 1)))
		if frame_count == 1 and ResourceLoader.exists("res://assets/generated/%s.png" % asset_name):
			source_resource_textures[asset_name] = [load("res://assets/generated/%s.png" % asset_name)]
		elif ResourceLoader.exists("res://assets/generated/%s_00.png" % asset_name):
			source_resource_textures[asset_name] = load_frames(asset_name, frame_count)
		else:
			return {}
	var frames: Array = source_resource_textures.get(asset_name, [])
	if frames.is_empty():
		return {}
	var frame_index := frames.size() - 1 if depleted else posmod(int(resource.get("source_frame", int(resource.get("id", 0)))), frames.size())
	if not depleted and int(resource.get("source_frame", -1)) < 0:
		frame_index = posmod(int(resource.get("id", 0)), frames.size())
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


func projectile_frame_info(projectile: Dictionary) -> Dictionary:
	return projectile_presentations.frame_info(projectile)


func effect_frame_info(effect: Dictionary) -> Dictionary:
	return effect_presentations.frame_info(effect)


func environment_frame_info(item: Dictionary, animation_time: float = 0.0) -> Dictionary:
	var graphic_id := int(item.get("graphic_id", -1))
	var asset_name := String(item.get("asset_name", ""))
	var spec: Dictionary = graphics_catalog_data.get("graphics", {}).get(String.num_int64(graphic_id), {})
	if graphic_id < 0 or asset_name.is_empty() or spec.is_empty():
		return {}
	if not source_resource_textures.has(asset_name):
		var frame_count := maxi(1, int(spec.get("slp", {}).get("frame_count", 1)))
		if frame_count == 1 and ResourceLoader.exists("res://assets/generated/%s.png" % asset_name):
			source_resource_textures[asset_name] = [load("res://assets/generated/%s.png" % asset_name)]
		elif ResourceLoader.exists("res://assets/generated/%s_00.png" % asset_name):
			source_resource_textures[asset_name] = load_frames(asset_name, frame_count)
		else:
			return {}
	var frames: Array = source_resource_textures.get(asset_name, [])
	if frames.is_empty():
		return {}
	var source_frame := int(item.get("source_frame", -1))
	var frame_index := posmod(source_frame, frames.size()) if source_frame >= 0 else posmod(int(item.get("scenario_object_id", item.get("id", 0))), frames.size())
	var frame_rate := float(spec.get("frame_rate", 0.0))
	if bool(item.get("animated", false)) and frame_rate > 0.0:
		var phase := posmod(int(item.get("scenario_object_id", item.get("id", 0))) * 1618, 1000) / 1000.0
		frame_index = posmod(floori(animation_time / frame_rate + phase * frames.size()), frames.size())
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
		"graphic_layer": int(spec.get("layer", 0)),
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


func unit_frame_info(unit: Dictionary, animation_state: String) -> Dictionary:
	return unit_presentations.frame_info(unit, animation_state)


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
