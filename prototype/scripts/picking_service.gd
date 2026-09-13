class_name RoRPickingService
extends RefCounted

const SelectionResolver := preload("res://scripts/selection_resolver.gd")
const PixelScaling := preload("res://scripts/pixel_scaling.gd")

const SELECTABLE_DRAWABLES := ["unit", "building", "building_part", "resource"]


func hit_stack(screen_position: Vector2, drawables: Array, world_to_screen: Callable, zoom: float) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for index in range(drawables.size() - 1, -1, -1):
		var drawable: Dictionary = drawables[index]
		var drawable_kind := String(drawable.get("kind", ""))
		if drawable_kind not in SELECTABLE_DRAWABLES:
			continue
		var entity: Dictionary = drawable.get("data", {})
		if entity.is_empty() or float(entity.get("hp", 1.0)) <= 0.0:
			continue
		var entity_type := entity_type_for(drawable_kind, entity)
		var stable_id := int(drawable.get("stable_id", entity.get("id", -1)))
		var dedupe_key := "%s:%d" % [entity_type, stable_id]
		if seen.has(dedupe_key):
			continue
		var hit_method := ""
		if texture_hit(screen_position, drawable, world_to_screen, zoom):
			hit_method = "opaque_pixel"
		elif footprint_hit(screen_position, entity_type, entity, world_to_screen, zoom):
			hit_method = "footprint"
		if hit_method.is_empty():
			continue
		seen[dedupe_key] = true
		result.append({
			"entity": entity,
			"entity_type": entity_type,
			"id": stable_id,
			"team": int(entity.get("team", 0)),
			"kind": String(entity.get("kind", "")),
			"draw_order": index,
			"hit_method": hit_method,
		})
	return result


func box_hits(rectangle: Rect2, drawables: Array, world_to_screen: Callable, player_team: int) -> Array:
	var units: Array = []
	var buildings: Array = []
	var seen: Dictionary = {}
	for drawable_value in drawables:
		var drawable: Dictionary = drawable_value
		var drawable_kind := String(drawable.get("kind", ""))
		if drawable_kind not in ["unit", "building"]:
			continue
		var entity: Dictionary = drawable.get("data", {})
		var stable_id := int(entity.get("id", -1))
		if stable_id < 0 or seen.has(stable_id) or int(entity.get("team", 0)) != player_team or float(entity.get("hp", 0.0)) <= 0.0:
			continue
		if not rectangle.has_point(world_to_screen.call(Vector2(entity.get("pos", Vector2.ZERO)))):
			continue
		seen[stable_id] = true
		if drawable_kind == "unit":
			units.append(entity)
		else:
			buildings.append(entity)
	var selected := units if not units.is_empty() else buildings
	selected.sort_custom(func(left, right): return int(left.get("id", -1)) < int(right.get("id", -1)))
	return selected


func context_entity(hit: Dictionary) -> Dictionary:
	var entity: Dictionary = hit.get("entity", {}).duplicate(true)
	entity["entity_type"] = String(hit.get("entity_type", ""))
	return entity


func entity_type_for(drawable_kind: String, entity: Dictionary) -> String:
	if drawable_kind in ["building", "building_part"]:
		return "foundation" if String(entity.get("state", "complete")) == "foundation" else "building"
	return drawable_kind


func texture_hit(screen_position: Vector2, drawable: Dictionary, world_to_screen: Callable, zoom: float) -> bool:
	var frame_info: Dictionary = drawable.get("frame_info", {})
	var texture: Texture2D = frame_info.get("texture")
	if texture == null:
		return false
	var anchor := PixelScaling.snap_screen(world_to_screen.call(Vector2(drawable.get("world_anchor", Vector2.ZERO))))
	anchor += Vector2(frame_info.get("screen_offset", Vector2.ZERO)) * zoom
	return SelectionResolver.texture_hit(
		screen_position,
		anchor,
		zoom,
		texture,
		Vector2(drawable.get("hotspot", frame_info.get("hotspot", Vector2.ZERO))),
		bool(frame_info.get("mirrored", false))
	)


func footprint_hit(screen_position: Vector2, entity_type: String, entity: Dictionary, world_to_screen: Callable, zoom: float) -> bool:
	var footprint: Dictionary = entity.get("footprint", {})
	if entity_type in ["building", "foundation"]:
		var polygon_source: Variant = footprint.get("polygon", PackedVector2Array())
		var polygon := PackedVector2Array()
		for world_point in polygon_source:
			polygon.append(world_to_screen.call(Vector2(world_point)))
		return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(screen_position, polygon)
	var anchor: Vector2 = world_to_screen.call(Vector2(entity.get("pos", Vector2.ZERO))) + Vector2(0.0, 5.0 * zoom)
	var selection_value: Variant = entity.get("selection_radius", footprint.get("selection_radius", Vector2(0.3, 0.3)))
	var selection := Vector2(float(selection_value), float(selection_value)) if selection_value is float or selection_value is int else Vector2(selection_value)
	var radius_x := maxf(6.0, selection.x * 34.0 * zoom)
	var radius_y := maxf(4.0, selection.y * 17.0 * zoom)
	var relative := screen_position - anchor
	return relative.x * relative.x / (radius_x * radius_x) + relative.y * relative.y / (radius_y * radius_y) <= 1.0
