class_name RoRPresentationDamageSelector
extends RefCounted


static func select_graphic_id(entity: Dictionary, source: Dictionary) -> int:
	var max_hp := maxf(1.0, float(entity.get("max_hp", 1.0)))
	var damage_percent := 100.0 * (1.0 - clampf(float(entity.get("hp", max_hp)) / max_hp, 0.0, 1.0))
	var selected_graphic := -1
	var selected_threshold := -1.0
	for damage_value in source.get("graphics", {}).get("damage", []):
		var damage: Dictionary = damage_value
		var threshold := float(damage.get("damage_percent", 101.0))
		if damage_percent + 0.0001 >= threshold and threshold >= selected_threshold:
			selected_threshold = threshold
			selected_graphic = int(damage.get("graphic_id", -1))
	return selected_graphic
