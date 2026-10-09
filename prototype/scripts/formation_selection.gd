class_name RoRFormationSelection
extends RefCounted

const Geometry := preload("res://scripts/formation_geometry.gd")

# Empty means mixed selection, never "use the last clicked formation button".
static func selected_type(units: Array, groups: Dictionary = {}) -> String:
	var result := ""
	for unit in units:
		var type := type_for(unit, groups)
		if result.is_empty():
			result = type
		elif result != type:
			return ""
	return result


static func type_for(unit: Dictionary, groups: Dictionary = {}) -> String:
	var group = groups.get(int(unit.get("formation_group_id", -1)))
	var type := String(group.preferred_formation_type) if group != null else String(unit.get("preferred_formation", Geometry.BLOCK))
	return type if Geometry.ALL.has(type) else Geometry.BLOCK
