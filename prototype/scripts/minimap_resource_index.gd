class_name RoRMinimapResourceIndex
extends RefCounted

const MinimapProjection := preload("res://scripts/minimap_projection.gd")

var pixels_by_resource_id: Dictionary = {}
var counts_by_pixel: Dictionary = {}
var pixels: Array[Vector2] = []
var geometry: Array = []


func clear() -> void:
	pixels_by_resource_id.clear()
	counts_by_pixel.clear()
	pixels.clear()
	geometry.clear()


func synchronize(resources: Array, changes: Variant, center: Vector2, scale: float, rectangle: Rect2, is_known: Callable = Callable(), probe: Variant = null) -> Array[Vector2]:
	var requested_geometry := [center, scale, rectangle]
	var rebuild := geometry != requested_geometry or changes == null
	var changed := false
	if rebuild:
		clear()
		geometry = requested_geometry
		for resource in resources:
			_update_resource(int(resource.get("id", -1)), resource, center, scale, is_known)
		changed = true
		if probe != null:
			probe.increment("presentation.minimap.resource_index.full_rebuilds")
			probe.increment("presentation.minimap.resource_index.resources_visited", resources.size())
	else:
		for resource_id in changes:
			changed = _update_resource(int(resource_id), changes[resource_id], center, scale, is_known) or changed
		if probe != null:
			probe.increment("presentation.minimap.resource_index.resources_visited", changes.size())
	if changed:
		var keys: Array = counts_by_pixel.keys()
		keys.sort_custom(func(left: Vector2i, right: Vector2i):
			return left.y < right.y or (left.y == right.y and left.x < right.x))
		pixels = []
		pixels.resize(keys.size())
		for index in range(keys.size()):
			pixels[index] = Vector2(keys[index]) * 2.0 + Vector2.ONE
	return pixels


func _update_resource(resource_id: int, resource: Variant, center: Vector2, scale: float, is_known: Callable) -> bool:
	if resource_id < 0:
		return false
	var previous: Variant = pixels_by_resource_id.get(resource_id)
	var current: Variant = null
	if resource is Dictionary and int(resource.get("amount", 0)) > 0:
		var position := Vector2(resource.get("pos", Vector2.ZERO))
		if not is_known.is_valid() or bool(is_known.call(position)):
			var point := MinimapProjection.world_to_minimap(position, center, scale)
			current = Vector2i(floori(point.x * 0.5), floori(point.y * 0.5))
	if previous == current:
		return false
	var changed := false
	if previous != null:
		var count := int(counts_by_pixel[previous]) - 1
		if count == 0:
			counts_by_pixel.erase(previous)
			changed = true
		else:
			counts_by_pixel[previous] = count
		pixels_by_resource_id.erase(resource_id)
	if current != null:
		var count := int(counts_by_pixel.get(current, 0))
		counts_by_pixel[current] = count + 1
		pixels_by_resource_id[resource_id] = current
		changed = changed or count == 0
	return changed