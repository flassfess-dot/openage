class_name RoRInterfaceSkin
extends RefCounted

const RoRInterfaceLayout := preload("res://scripts/interface_layout.gd")
const INVENTORY_PATH := "res://assets/generated/interface-source-inventory.json"
const SOURCE_CANDIDATES := {
	50713: {"asset_name": "hud_control_50713", "frame_count": 4, "kind": "square_control_backplate"},
	50714: {"asset_name": "hud_control_50714", "frame_count": 4, "kind": "square_control_backplate"},
	50715: {"asset_name": "hud_control_50715", "frame_count": 4, "kind": "square_control_backplate"},
	50716: {"asset_name": "hud_control_50716", "frame_count": 4, "kind": "square_control_backplate"},
	50717: {"asset_name": "hud_control_50717", "frame_count": 2, "kind": "text_button_backplate"},
	50718: {"asset_name": "hud_control_50718", "frame_count": 2, "kind": "text_button_backplate"},
	50719: {"asset_name": "hud_control_50719", "frame_count": 2, "kind": "text_button_backplate"},
	50721: {"asset_name": "hud_glyph_50721", "frame_count": 15, "kind": "command_glyph_sheet"},
	50725: {"asset_name": "hud_control_50725", "frame_count": 4, "kind": "compact_control"},
	50726: {"asset_name": "hud_control_50726", "frame_count": 4, "kind": "compact_control"},
	50727: {"asset_name": "hud_control_50727", "frame_count": 4, "kind": "compact_control"},
	50728: {"asset_name": "hud_control_50728", "frame_count": 4, "kind": "compact_control"},
	50745: {"asset_name": "hud_status_50745", "frame_count": 26, "kind": "status_strip"},
	50747: {"asset_name": "hud_control_50747", "frame_count": 2, "kind": "wide_text_button_backplate"},
	50748: {"asset_name": "hud_control_50748", "frame_count": 2, "kind": "wide_text_button_backplate"},
	50749: {"asset_name": "hud_control_50749", "frame_count": 2, "kind": "wide_text_button_backplate"},
	50750: {"asset_name": "hud_control_50750", "frame_count": 2, "kind": "wide_text_button_backplate"},
}

var records_by_key: Dictionary = {}
var inventory_by_key: Dictionary = {}
var texture_cache: Dictionary = {}


func configure(asset_records: Array, inventory: Dictionary) -> void:
	records_by_key.clear()
	inventory_by_key.clear()
	texture_cache.clear()
	for record_value in inventory.get("records", []):
		var record: Dictionary = record_value
		inventory_by_key[_source_key(String(record.get("source", "")), int(record.get("id", -1)))] = record
	for asset_value in asset_records:
		var asset: Dictionary = asset_value
		if String(asset.get("archive", "")) != "interfac" or not asset.has("frame"):
			continue
		records_by_key[_asset_key(String(asset.get("name", "")), int(asset.get("frame", 0)))] = asset


func texture(asset_name: String, frame: int = 0) -> Texture2D:
	var key := _asset_key(asset_name, frame)
	if texture_cache.has(key):
		return texture_cache[key]
	var record: Dictionary = records_by_key.get(key, {})
	if record.is_empty() or not has_valid_provenance(asset_name, frame):
		return null
	var file_name := String(record.get("file", ""))
	var resource_path := "res://assets/generated/%s" % file_name
	if not ResourceLoader.exists(resource_path):
		return null
	var loaded: Texture2D = load(resource_path)
	if loaded != null:
		texture_cache[key] = loaded
	return loaded


func hud_shell(source_width: int, style_index: int = 0) -> Dictionary:
	var asset_name := RoRInterfaceLayout.shell_asset_name(source_width, style_index)
	return {
		"asset_name": asset_name,
		"top": texture(asset_name, 0),
		"bottom": texture(asset_name, 1),
		"source_width": source_width,
		"style_index": clampi(style_index, 0, 3),
	}


func control_candidate(source_id: int) -> Dictionary:
	var candidate := source_candidate(source_id)
	if candidate.is_empty() or String(candidate.get("kind", "")) in ["status_strip", "command_glyph_sheet"]:
		return {}
	return candidate


func status_candidate(source_id: int = 50745) -> Dictionary:
	var candidate := source_candidate(source_id)
	if String(candidate.get("kind", "")) != "status_strip":
		return {}
	candidate["semantic_role"] = ""
	candidate["semantic_role_status"] = "original_capture_pending"
	return candidate


func source_candidate(source_id: int) -> Dictionary:
	var descriptor: Dictionary = SOURCE_CANDIDATES.get(source_id, {})
	if descriptor.is_empty():
		return {}
	var asset_name := String(descriptor.get("asset_name", ""))
	var frame_count := int(descriptor.get("frame_count", 0))
	var frames: Array[Texture2D] = []
	for frame in range(frame_count):
		var candidate := texture(asset_name, frame)
		if candidate == null:
			return {}
		frames.append(candidate)
	return {
		"source_id": source_id,
		"asset_name": asset_name,
		"kind": String(descriptor.get("kind", "")),
		"frames": frames,
		"frame_sha256": _frame_hashes(asset_name, frame_count),
		"semantic_composition": {},
		"semantic_composition_status": "original_capture_pending",
	}


func status_frame(remaining_ratio: float, source_id: int = 50745) -> Texture2D:
	var candidate := status_candidate(source_id)
	var frames: Array = candidate.get("frames", [])
	if frames.is_empty():
		return null
	return frames[status_frame_index(remaining_ratio, frames.size())]


static func status_frame_index(remaining_ratio: float, frame_count: int = 26) -> int:
	if frame_count <= 1:
		return 0
	return clampi(roundi((1.0 - clampf(remaining_ratio, 0.0, 1.0)) * float(frame_count - 1)), 0, frame_count - 1)


func has_valid_provenance(asset_name: String, frame: int = 0) -> bool:
	var asset: Dictionary = records_by_key.get(_asset_key(asset_name, frame), {})
	if asset.is_empty():
		return false
	var source := String(asset.get("source", ""))
	var palette_id := int(asset.get("paletteId", -1))
	if source.is_empty() or palette_id < 0:
		return false
	var inventory_record: Dictionary = inventory_by_key.get(_source_key(source, int(asset.get("id", -1))), {})
	if inventory_record.is_empty():
		return false
	var policy: Dictionary = inventory_record.get("palettePolicy", {})
	return String(policy.get("mode", "")) == "explicit" and int(policy.get("paletteId", -1)) == palette_id


func record(asset_name: String, frame: int = 0) -> Dictionary:
	return records_by_key.get(_asset_key(asset_name, frame), {}).duplicate(true)


func _frame_hashes(asset_name: String, frame_count: int) -> Array[String]:
	var hashes: Array[String] = []
	for frame in range(frame_count):
		hashes.append(String(records_by_key.get(_asset_key(asset_name, frame), {}).get("fileSha256", "")))
	return hashes


func _asset_key(asset_name: String, frame: int) -> String:
	return "%s:%d" % [asset_name, frame]


func _source_key(source: String, source_id: int) -> String:
	return "%s:%d" % [source.replace("\\", "/").to_lower(), source_id]
