class_name RoREnvironmentPresentationField
extends RefCounted

var items_by_cell: Dictionary = {}
var ambient_items: Array = []
var item_count: int = 0
var static_items: Array = []
var native_query_enabled := true
var profile_query_alternatives := "--profile-environment-query-alternatives" in OS.get_cmdline_user_args()
var native_index: Variant
var last_projection: Dictionary = {}


func configure(items: Array) -> void:
	# Both the rows and their spatial membership change only with configuration.
	# Drop the previous map's native owner before clearing the script tables.
	native_index = null
	last_projection = {}
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
		static_items.append(item)
	static_items.sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))
	for index in range(static_items.size()):
		var item: Dictionary = static_items[index]
		var position: Vector2 = item.get("position", Vector2.ZERO)
		var bounds: Array = item.get("presentation_bounds", [0.0, 0.0, 0.0, 0.0])
		for y in range(floori(position.y + float(bounds[1])), floori(position.y + float(bounds[3])) + 1):
			for x in range(floori(position.x + float(bounds[0])), floori(position.x + float(bounds[2])) + 1):
				var cell := Vector2i(x, y)
				if not items_by_cell.has(cell): items_by_cell[cell] = []
				items_by_cell[cell].append(index)
	ambient_items.sort_custom(func(left, right): return int(left.get("id", 0)) < int(right.get("id", 0)))
	if native_query_enabled and ClassDB.class_exists("RoREnvironmentQueryIndex"):
		var index: Variant = ClassDB.instantiate("RoREnvironmentQueryIndex")
		if index.configure(static_items, items_by_cell, ambient_items): native_index = index


func query(bounds: Rect2i, probe = null, include_ambient: bool = false) -> Array:
	last_projection = {}
	if (native_query_enabled or (profile_query_alternatives and probe != null)) and native_index != null:
		var started := Time.get_ticks_usec() if probe != null else 0
		var projection: Dictionary = native_index.query(bounds, include_ambient)
		if not projection.is_empty():
			if probe != null: probe.observe_microseconds("presentation.environment.query_prepared", Time.get_ticks_usec() - started)
			if profile_query_alternatives and probe != null:
				started = Time.get_ticks_usec()
				var reference := _query_script(bounds, include_ambient)
				probe.observe_microseconds("presentation.environment.query_script", Time.get_ticks_usec() - started)
				if not native_query_enabled: return reference
			if native_query_enabled:
				last_projection = projection
				return projection["items"]
	return _query_script(bounds, include_ambient)


func query_presentation(bounds: Rect2i, probe = null) -> Array:
	return query(bounds, probe, true)


func _query_script(bounds: Rect2i, include_ambient: bool = false) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			for index in items_by_cell.get(Vector2i(x, y), []):
				if seen.has(index): continue
				seen[index] = true
	# Native integer sorting avoids a script comparator for every visible item.
	var indices: Array = seen.keys()
	indices.sort()
	for index in indices:
		result.append(static_items[index])
	if include_ambient: result.append_array(ambient_items)
	return result


func mobile_items() -> Array:
	return ambient_items
