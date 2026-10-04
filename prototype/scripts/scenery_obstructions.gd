class_name RoRSceneryObstructions
extends RefCounted

const SOLID_KEYS := ["boulders", "ror_rocks", "coastal_rocks", "ror_sea_rocks"]


static func collect(items: Array) -> Array:
	var result: Array = []
	for item in items:
		var key := String(item.get("decoration_key", String(item.get("asset_name", "")).trim_prefix("aoe2_temperate:")))
		if key not in SOLID_KEYS and not bool(item.get("blocks_navigation", false)):
			continue
		var position := Vector2(item.get("position", Vector2.ZERO))
		var radius := maxf(0.35, float(item.get("footprint_radius", 0.5)))
		var cells: Array[Vector2i] = []
		for y in range(floori(position.y - radius + 0.001), floori(position.y + radius - 0.001) + 1):
			for x in range(floori(position.x - radius + 0.001), floori(position.x + radius - 0.001) + 1):
				cells.append(Vector2i(x, y))
		result.append({"id": int(item.get("id", -1)), "kind": "scenery_obstruction", "position": position, "occupied_cells": cells})
	return result
