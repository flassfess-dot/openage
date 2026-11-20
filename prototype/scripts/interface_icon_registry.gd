class_name RoRInterfaceIconRegistry
extends RefCounted

const GateCatalog := preload("res://scripts/gate_catalog.gd")

const ASSET_NAMES := {
	"object": "unit_icon",
	"unit": "unit_icon",
	"technology": "technology_icon",
	"command": "hud_glyph_50721",
	"building_0": "building_icon_0",
	"building_1": "building_icon_1",
	"building_2": "building_icon_2",
	"building_3": "building_icon_3",
	"building_4": "building_icon_4",
}

# Source glyphs keep their frame numbers; modern orders have their own art.
const COMMAND_GLYPHS := {
	"repair": 0, "open_build_menu": 2, "stop": 3,
	"unload": 1, "delete": 10, "cancel_production": 10, "close_build_menu": 10, "hold": 12,
}
const CUSTOM_COMMANDS := {
	"attack_ground": preload("res://assets/ui/commands/attack_ground.png"),
	"aggressive": preload("res://assets/ui/commands/aggressive.png"),
	"defensive": preload("res://assets/ui/commands/defensive.png"),
	"stand_ground": preload("res://assets/ui/commands/stand_ground.png"),
	"passive": preload("res://assets/ui/commands/passive.png"),
	"attack_move": preload("res://assets/ui/commands/attack_move.png"),
	"ungarrison": preload("res://assets/ui/commands/ungarrison.png"),
}
const GATE_MODES := {
	"auto": preload("res://assets/ui/commands/gate-auto.png"),
	"open": preload("res://assets/ui/commands/gate-open.png"),
	"locked": preload("res://assets/ui/commands/gate-locked.png"),
}
const TRADE_RESOURCES := [
	preload("res://assets/ui/commands/trade-food.png"),
	preload("res://assets/ui/commands/trade-wood.png"),
	preload("res://assets/ui/commands/trade-stone.png"),
]

static func command_icon(action: String, stance: String = "aggressive") -> Dictionary:
	var custom := stance if action == "stance" else action
	if CUSTOM_COMMANDS.has(custom):
		return {"icon_kind": "command_custom", "icon_id": CUSTOM_COMMANDS.keys().find(custom)}
	return {"icon_kind": "command", "icon_id": int(COMMAND_GLYPHS.get(action, -1))}

static func gate_mode_icon(mode: String) -> Dictionary:
	return {"icon_kind": "gate_mode", "icon_id": GATE_MODES.keys().find(mode)}


var records_by_sheet: Dictionary = {}
var texture_cache: Dictionary = {}
var player_palette


func configure(asset_records: Variant, indexed_frame_records: Dictionary = {}) -> void:
	records_by_sheet.clear()
	texture_cache.clear()
	var records: Array = []
	if not indexed_frame_records.is_empty():
		var indexed_sheets: Dictionary = {}
		for sheet_name_value in ASSET_NAMES.values():
			var sheet_name := String(sheet_name_value)
			if indexed_sheets.has(sheet_name):
				continue
			indexed_sheets[sheet_name] = true
			for record_value in indexed_frame_records.get(sheet_name, []):
				records.append(record_value)
	else:
		records = asset_records.values() if asset_records is Dictionary else asset_records if asset_records is Array else []
	for record_value in records:
		var record: Dictionary = record_value
		if String(record.get("archive", "")) != "interfac" or not record.has("frame"):
			continue
		var sheet_name := String(record.get("name", ""))
		if sheet_name not in ASSET_NAMES.values():
			continue
		if not records_by_sheet.has(sheet_name):
			records_by_sheet[sheet_name] = {}
		records_by_sheet[sheet_name][int(record["frame"])] = record


func has_icon(icon_kind: String, icon_id: int) -> bool:
	if icon_kind == "gate":
		return icon_id >= 0 and icon_id < GateCatalog.ICON_VARIANTS.size()
	if icon_kind == "gate_mode":
		return icon_id >= 0 and icon_id < GATE_MODES.size()
	if icon_kind == "command_custom":
		return icon_id >= 0 and icon_id < CUSTOM_COMMANDS.size()
	if icon_kind == "trade_resource":
		return icon_id >= 0 and icon_id < TRADE_RESOURCES.size()
	var sheet_name := String(ASSET_NAMES.get(icon_kind, ""))
	return icon_id >= 0 and records_by_sheet.get(sheet_name, {}).has(icon_id)


func texture(icon_kind: String, icon_id: int, team: int = 1) -> Texture2D:
	if not has_icon(icon_kind, icon_id):
		return null
	match icon_kind:
		"gate_mode": return GATE_MODES.values()[icon_id]
		"command_custom": return CUSTOM_COMMANDS.values()[icon_id]
		"trade_resource": return TRADE_RESOURCES[icon_id]
	var player: int = player_palette.color_index(team) if player_palette != null and team > 0 else 1
	if icon_kind == "gate":
		var gate_key := "gate:%d:%d" % [icon_id, player]
		if not texture_cache.has(gate_key):
			texture_cache[gate_key] = load("res://assets/ui/gates/%s-p%d.png" % [GateCatalog.ICON_VARIANTS[icon_id], player])
		return texture_cache[gate_key]
	var sheet_name := String(ASSET_NAMES[icon_kind])
	var cache_key := "%s:%d:%d" % [sheet_name, icon_id, player]
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]
	var record: Dictionary = records_by_sheet[sheet_name][icon_id]
	var file_name := String(record.get("file", ""))
	var loaded: Texture2D = load("res://assets/generated/%s" % file_name)
	if player_palette != null:
		loaded = player_palette.texture_for(record, loaded, player)
	if loaded != null:
		texture_cache[cache_key] = loaded
	return loaded


func frame_count(icon_kind: String) -> int:
	match icon_kind:
		"gate": return GateCatalog.ICON_VARIANTS.size()
		"gate_mode": return GATE_MODES.size()
		"command_custom": return CUSTOM_COMMANDS.size()
		"trade_resource": return TRADE_RESOURCES.size()
	var sheet_name := String(ASSET_NAMES.get(icon_kind, ""))
	return records_by_sheet.get(sheet_name, {}).size()
