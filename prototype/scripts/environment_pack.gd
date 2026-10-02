class_name RoREnvironmentPack
extends RefCounted

const DEFINITION_PATH := "res://data/environment/aoe2_temperate.json"
const ASSET_ROOT := "res://assets/generated/environment/aoe2_temperate/"
const PREFIX := "aoe2_temperate:"

var enabled := false
var definition: Dictionary = {}
var manifest: Dictionary = {}
var materials_by_id: Dictionary = {}
var objects_by_key: Dictionary = {}
var textures: Dictionary = {}
var legacy_textures: Dictionary = {}


func enable() -> bool:
	if enabled:
		return true
	if not FileAccess.file_exists(ASSET_ROOT + "manifest.json"):
		push_warning("Import the optional AoE2 environment pack before enabling it.")
		return false
	var parsed_definition = JSON.parse_string(FileAccess.get_file_as_string(DEFINITION_PATH).trim_prefix("\ufeff"))
	var parsed_manifest = JSON.parse_string(FileAccess.get_file_as_string(ASSET_ROOT + "manifest.json"))
	if not parsed_definition is Dictionary or not parsed_manifest is Dictionary:
		return false
	if int(parsed_manifest.get("format_version", -1)) != 1 or parsed_manifest.get("pack_id", "") != "aoe2_temperate":
		return false
	# Never silently mix a new selection/colour recipe with stale generated art.
	if parsed_manifest.get("definition_sha256", "") != FileAccess.get_sha256(DEFINITION_PATH):
		push_warning("AoE2 environment definition changed; reimport the pack.")
		return false
	for material in parsed_definition.get("materials", []):
		var record: Dictionary = parsed_manifest.get("materials", {}).get(material["key"], {})
		if not _valid_image(record):
			return false
	for object in parsed_definition.get("objects", []):
		var frames: Array = parsed_manifest.get("objects", {}).get(object["key"], {}).get("frames", [])
		if frames.size() != object["frames"].size():
			return false
		for frame in frames:
			if not _valid_image(frame) or frame.get("hotspot", []).size() != 2:
				return false
	definition = parsed_definition
	manifest = parsed_manifest
	for material in definition["materials"]:
		materials_by_id[int(material["terrain_id"])] = material
	for object in definition["objects"]:
		objects_by_key[String(object["key"])] = object
	enabled = true
	return true


func _valid_image(record: Dictionary) -> bool:
	var file := String(record.get("file", ""))
	if file.is_empty() or file != file.get_file() or not ResourceLoader.exists(ASSET_ROOT + file):
		return false
	# Exported PCKs retain imported textures rather than original PNG bytes.
	return not FileAccess.file_exists(ASSET_ROOT + file) or FileAccess.get_sha256(ASSET_ROOT + file) == String(record.get("sha256", ""))


func _texture(file: String) -> Texture2D:
	if not textures.has(file):
		textures[file] = load(ASSET_ROOT + file)
	return textures[file]


func terrain_textures() -> Array:
	var result: Array = []
	if enabled:
		result.append_array(legacy_textures.values())
		for material in definition["materials"]:
			result.append(material_texture(int(material["terrain_id"])))
	return result


func has_material(terrain_id: int) -> bool:
	return enabled and materials_by_id.has(terrain_id)


func material_texture(terrain_id: int) -> Texture2D:
	if not has_material(terrain_id):
		return null
	return _texture(String(manifest["materials"][materials_by_id[terrain_id]["key"]]["file"]))


func terrain_id(key: String) -> int:
	for id in materials_by_id:
		if materials_by_id[id]["key"] == key:
			return int(id)
	return -1


func material(key: String) -> Dictionary:
	return materials_by_id.get(terrain_id(key), {}).duplicate(true)


func object_definition(key: String) -> Dictionary:
	return objects_by_key.get(key, {}).duplicate(true)


func object_variant_count(key: String) -> int:
	return manifest.get("objects", {}).get(key, {}).get("frames", []).size()


func owns_asset(asset_name: String) -> bool:
	return enabled and asset_name.begins_with(PREFIX) and objects_by_key.has(asset_name.trim_prefix(PREFIX))


func frame_info(item: Dictionary, resource: bool = false) -> Dictionary:
	var asset := String(item.get("source_graphic_asset_name" if resource else "asset_name", ""))
	if not owns_asset(asset):
		return {}
	var key := asset.trim_prefix(PREFIX)
	if resource and int(item.get("amount", 1)) <= 0:
		key = String(objects_by_key[key].get("depleted_key", ""))
	if not objects_by_key.has(key):
		return {}
	var frames: Array = manifest["objects"][key]["frames"]
	var index := posmod(int(item.get("source_frame", item.get("id", 0))), frames.size())
	var record: Dictionary = frames[index]
	return {
		"texture": _texture(String(record["file"])),
		"hotspot": Vector2(record["hotspot"][0], record["hotspot"][1]),
		"asset_name": PREFIX + key,
		"frame_index": index,
		"mirrored": false,
		"graphic_layer": 0 if objects_by_key[key].get("role", "") == "decal" else 20,
	}


func decorate_resource(resource: Dictionary, key: String, variant: int = 0) -> Dictionary:
	# Reuse the project's normal tree simulation, harvesting and occupancy.
	# Source presentation fields survive compact snapshots and saved resources.
	if not objects_by_key.has(key) or objects_by_key[key].get("role", "") != "tree":
		return {}
	var result := resource.duplicate()
	result["source_graphic_asset_name"] = PREFIX + key
	result["source_depleted_asset_name"] = PREFIX + String(objects_by_key[key]["depleted_key"])
	result["source_frame"] = posmod(variant, object_variant_count(key))
	result["visible_when_depleted"] = true
	return result


func scenery(key: String, position: Vector2, id: int, variant: int = 0) -> Dictionary:
	if not objects_by_key.has(key):
		return {}
	return {"id": id, "asset_name": PREFIX + key, "position": position,
		"source_frame": posmod(variant, object_variant_count(key)), "presentation_layer": "decal" if objects_by_key[key].get("role", "") == "decal" else "scenery"}


func prepare_legacy_terrain(frames_by_kind: Dictionary) -> void:
	# Opaque cartesian patches avoid transparent edge texels when native RoR
	# diamonds meet triangulated surfaces. Native grass, beach and both water
	# depths share the same projection and transition geometry.
	if not legacy_textures.is_empty():
		return
	var terrain_ids := {"grass": 0, "sand": 6, "water": 1, "water_dark": 22}
	for kind in terrain_ids:
		var atlas := Image.create(96, 96, false, Image.FORMAT_RGBA8)
		var frames: Array = frames_by_kind[kind]
		for frame in range(9):
			var source: Image = frames[frame % frames.size()].get_image()
			for y in range(32):
				for x in range(32):
					var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / 32.0
					var sample := Vector2i(roundi(32.0 + 32.0 * (uv.x - uv.y)), roundi(16.0 * (uv.x + uv.y)))
					var pixel := source.get_pixelv(sample)
					if pixel.a < 1.0:
						pixel = source.get_pixelv(Vector2i(Vector2(sample).move_toward(Vector2(32, 16), 1.5)))
					pixel.a = 1.0
					atlas.set_pixel((frame % 3) * 32 + x, (frame / 3) * 32 + y, pixel)
		legacy_textures[terrain_ids[kind]] = ImageTexture.create_from_image(atlas)
	# A submerged sandy bed is still water, not an opaque desert diamond.
	var shallows: Image = legacy_textures[1].get_image().duplicate()
	var sand: Image = legacy_textures[6].get_image()
	for y in range(shallows.get_height()):
		for x in range(shallows.get_width()):
			var bed := sand.get_pixel(x, y)
			# Water attenuates the warm red bed tones; an unfiltered blend is violet.
			bed.r *= 0.48
			bed.g *= 0.93
			shallows.set_pixel(x, y, shallows.get_pixel(x, y).lerp(bed, 0.42))
	legacy_textures[4] = ImageTexture.create_from_image(shallows)
