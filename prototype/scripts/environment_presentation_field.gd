class_name RoREnvironmentPresentationField
extends RefCounted

var items_by_cell: Dictionary = {}
var ambient_items: Array = []
var item_count: int = 0
var static_items: Array = []


func configure(items: Array) -> void:
	items_by_cell.clear()
	static_items.clear()
	ambient_items.clear()
	item_count = 0
	for item_value in items:
		if not item_value is Dictionary:
			continue
		var item: Dictionary = item_value
		item_count += 1
		if String(item.get("presentation_layer", "scenery")) == "ambient_actor":
			ambient_items.append(item)
			continue
		var position: Vector2 = item.get("position", Vector2.ZERO)
		var bounds: Array = item.get("presentation_bounds", [0.0, 0.0, 0.0, 0.0])
		var index := static_items.size()
		static_items.append(item)
		for y in range(floori(position.y + float(bounds[1])), floori(position.y + float(bounds[3])) + 1):
			for x in range(floori(position.x + float(bounds[0])), floori(position.x + float(bounds[2])) + 1):
				var cell := Vector2i(x, y)
				if not items_by_cell.has(cell): items_by_cell[cell] = []
				items_by_cell[cell].append(index)
	ambient_items.sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))


func query(bounds: Rect2i) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			for index in items_by_cell.get(Vector2i(x, y), []):
				if seen.has(index): continue
				seen[index] = true
				result.append(static_items[index])
	result.sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))
	return result


func mobile_items() -> Array:
	return ambient_items
