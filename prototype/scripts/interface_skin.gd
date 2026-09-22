class_name RoRInterfaceSkin
extends RefCounted

const RoRInterfaceLayout := preload("res://scripts/interface_layout.gd")
const INVENTORY_PATH := "res://assets/generated/interface-source-inventory.json"
const STYLE_SQUARE_CONTROL_IDS := [50713, 50714, 50715, 50716, 53304]
const STYLE_SMALL_MENU_IDS := [50717, 50718, 50719, 50717, 53007]
const STYLE_COMMAND_ARROW_IDS := [50725, 50726, 50727, 50728, 53009]
const STYLE_MEDIUM_MENU_IDS := [50747, 50748, 50749, 50750, 53008]
# Rise of Rome adds a fifth shell/control style but reuses the classical panel tile.
const STYLE_PANEL_INDICES := [0, 1, 2, 3, 1]
const STYLE_TEXT_COLORS := [
	Color("20180f"),
	Color("20180f"),
	Color("f4e6c7"),
	Color("20180f"),
	Color("f4e6c7"),
]
const SOURCE_CANDIDATES := {
	50713: {"asset_name": "hud_control_50713", "frame_count": 4, "kind": "square_command_backplate"},
	50714: {"asset_name": "hud_control_50714", "frame_count": 4, "kind": "square_command_backplate"},
	50715: {"asset_name": "hud_control_50715", "frame_count": 4, "kind": "square_command_backplate"},
	50716: {"asset_name": "hud_control_50716", "frame_count": 4, "kind": "square_command_backplate"},
	50717: {"asset_name": "hud_control_50717", "frame_count": 2, "kind": "small_menu_button"},
	50718: {"asset_name": "hud_control_50718", "frame_count": 2, "kind": "small_menu_button"},
	50719: {"asset_name": "hud_control_50719", "frame_count": 2, "kind": "small_menu_button"},
	50721: {"asset_name": "hud_glyph_50721", "frame_count": 15, "kind": "unit_command_glyph_sheet"},
	50725: {"asset_name": "hud_control_50725", "frame_count": 4, "kind": "command_arrow_button"},
	50726: {"asset_name": "hud_control_50726", "frame_count": 4, "kind": "command_arrow_button"},
	50727: {"asset_name": "hud_control_50727", "frame_count": 4, "kind": "command_arrow_button"},
	50728: {"asset_name": "hud_control_50728", "frame_count": 4, "kind": "command_arrow_button"},
	50745: {"asset_name": "hud_status_50745", "frame_count": 26, "kind": "unit_health_strip"},
	50747: {"asset_name": "hud_control_50747", "frame_count": 2, "kind": "medium_menu_button"},
	50748: {"asset_name": "hud_control_50748", "frame_count": 2, "kind": "medium_menu_button"},
	50749: {"asset_name": "hud_control_50749", "frame_count": 2, "kind": "medium_menu_button"},
	50750: {"asset_name": "hud_control_50750", "frame_count": 2, "kind": "medium_menu_button"},
	53007: {"asset_name": "hud_control_53007", "frame_count": 2, "kind": "small_menu_button"},
	53008: {"asset_name": "hud_control_53008", "frame_count": 2, "kind": "medium_menu_button"},
	53009: {"asset_name": "hud_control_53009", "frame_count": 4, "kind": "command_arrow_button"},
	53304: {"asset_name": "hud_control_53304", "frame_count": 4, "kind": "square_command_backplate"},
}

var records_by_key: Dictionary = {}
var inventory_by_key: Dictionary = {}
var texture_cache: Dictionary = {}


func configure(asset_records: Array, inventory: Dictionary, indexed_frame_records: Dictionary = {}) -> void:
	records_by_key.clear()
	inventory_by_key.clear()
	texture_cache.clear()
	for record_value in inventory.get("records", []):
		var record: Dictionary = record_value
		inventory_by_key[_source_key(String(record.get("source", "")), int(record.get("id", -1)))] = record
	var interface_records: Array = []
	if not indexed_frame_records.is_empty():
		for records_value in indexed_frame_records.values():
			interface_records.append_array(records_value)
	else:
		interface_records = asset_records
	for asset_value in interface_records:
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
	var style := clampi(style_index, 0, 4)
	var asset_name := RoRInterfaceLayout.shell_asset_name(source_width, style)
	var top := _normalized_shell_frame(texture(asset_name, 0), int(RoRInterfaceLayout.TOP_HEIGHT))
	var bottom := _normalized_shell_frame(texture(asset_name, 1), int(RoRInterfaceLayout.BOTTOM_HEIGHT))
	if (top == null or bottom == null) and style == 4:
		asset_name = RoRInterfaceLayout.shell_asset_name(source_width, 1)
		top = _normalized_shell_frame(texture(asset_name, 0), int(RoRInterfaceLayout.TOP_HEIGHT))
		bottom = _normalized_shell_frame(texture(asset_name, 1), int(RoRInterfaceLayout.BOTTOM_HEIGHT))
	return {
		"asset_name": asset_name,
		"top": top,
		"bottom": bottom,
		"source_width": source_width,
		"style_index": style,
	}


func _normalized_shell_frame(source: Texture2D, expected_height: int) -> Texture2D:
	if source == null or source.get_height() <= expected_height:
		return source
	var region := AtlasTexture.new()
	region.atlas = source
	region.region = Rect2(0, 0, source.get_width(), expected_height)
	return region


func panel_texture(style_index: int = 0) -> Texture2D:
	var style := clampi(style_index, 0, 4)
	var panel := texture(panel_asset_name(style))
	return panel if panel != null else texture("interface_panel")


static func panel_asset_name(style_index: int) -> String:
	return "interface_panel_%d" % STYLE_PANEL_INDICES[clampi(style_index, 0, 4)]


static func text_color(style_index: int) -> Color:
	return STYLE_TEXT_COLORS[clampi(style_index, 0, 4)]


static func style_index_for_civilization(civilization_id: int, object_catalog: Dictionary) -> int:
	for civilization_value in object_catalog.get("civilizations", []):
		var civilization: Dictionary = civilization_value
		if int(civilization.get("civilization_id", -1)) == civilization_id:
			return clampi(int(civilization.get("icon_set", 0)), 0, 4)
	return 0


static func style_index_for_match(match_definition: Dictionary, object_catalog: Dictionary) -> int:
	var local_team := int(match_definition.get("local_team", 1))
	for player_value in match_definition.get("players", []):
		var player: Dictionary = player_value
		if int(player.get("team", 0)) == local_team:
			return style_index_for_civilization(int(player.get("civilization_id", 0)), object_catalog)
	return 0


func control_candidate(source_id: int) -> Dictionary:
	var candidate := source_candidate(source_id)
	if candidate.is_empty() or String(candidate.get("kind", "")) in ["unit_health_strip", "unit_command_glyph_sheet"]:
		return {}
	return candidate


func status_candidate(source_id: int = 50745) -> Dictionary:
	var candidate := source_candidate(source_id)
	if String(candidate.get("kind", "")) != "unit_health_strip":
		return {}
	candidate["semantic_role"] = "unit_health"
	candidate["semantic_role_status"] = "reference_confirmed"
	return candidate


static func is_unit_health(candidate: Dictionary) -> bool:
	return String(candidate.get("semantic_role_status", "")) in ["reference_confirmed", "measured"] and String(candidate.get("semantic_role", "")) == "unit_health"


func menu_button(style_index: int, medium: bool) -> Dictionary:
	var style := clampi(style_index, 0, 4)
	var ids := STYLE_MEDIUM_MENU_IDS if medium else STYLE_SMALL_MENU_IDS
	var candidate := source_candidate(int(ids[style]))
	var frames: Array = candidate.get("frames", [])
	if frames.size() < 2:
		return {}
	return {
		"source_id": int(ids[style]),
		"normal": frames[0],
		"pressed": frames[1],
		"size": Vector2(frames[0].get_size()),
		"semantic_role": "medium_menu_button" if medium else "small_menu_button",
	}


func square_command_backplate(style_index: int) -> Texture2D:
	var candidate := source_candidate(int(STYLE_SQUARE_CONTROL_IDS[clampi(style_index, 0, 4)]))
	var frames: Array = candidate.get("frames", [])
	return frames[0] if not frames.is_empty() else null


func command_arrow_frames(style_index: int) -> Array:
	return source_candidate(int(STYLE_COMMAND_ARROW_IDS[clampi(style_index, 0, 4)])).get("frames", [])


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
