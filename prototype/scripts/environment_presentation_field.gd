class_name RoREnvironmentPresentationField
extends RefCounted

var items_by_cell: Dictionary = {}
var ambient_items: Array = []
var item_count: int = 0


func configure(items: Array) -> void:
	items_by_cell.clear()
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
		var cell := Vector2i(floori(position.x), floori(position.y))
		if not items_by_cell.has(cell):
			items_by_cell[cell] = []
		items_by_cell[cell].append(item)
	for cell in items_by_cell:
		items_by_cell[cell].sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))
	ambient_items.sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))


func query(bounds: Rect2i) -> Array:
	var result: Array = []
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			result.append_array(items_by_cell.get(Vector2i(x, y), []))
	result.sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))
	return result


func mobile_items() -> Array:
	return ambient_items
