class_name RoRInterfaceIconRegistry
extends RefCounted

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

var records_by_sheet: Dictionary = {}
var texture_cache: Dictionary = {}


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
		records_by_sheet[sheet_name][int(record["frame"])] = String(record.get("file", ""))


func has_icon(icon_kind: String, icon_id: int) -> bool:
	var sheet_name := String(ASSET_NAMES.get(icon_kind, ""))
	return icon_id >= 0 and records_by_sheet.get(sheet_name, {}).has(icon_id)


func texture(icon_kind: String, icon_id: int) -> Texture2D:
	if not has_icon(icon_kind, icon_id):
		return null
	var sheet_name := String(ASSET_NAMES[icon_kind])
	var cache_key := "%s:%d" % [sheet_name, icon_id]
	if texture_cache.has(cache_key):
		return texture_cache[cache_key]
	var file_name := String(records_by_sheet[sheet_name][icon_id])
	var loaded: Texture2D = load("res://assets/generated/%s" % file_name)
	if loaded != null:
		texture_cache[cache_key] = loaded
	return loaded


func frame_count(icon_kind: String) -> int:
	var sheet_name := String(ASSET_NAMES.get(icon_kind, ""))
	return records_by_sheet.get(sheet_name, {}).size()
