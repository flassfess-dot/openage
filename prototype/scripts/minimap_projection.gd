class_name RoRMinimapProjection
extends RefCounted


static func world_to_minimap(world: Vector2, center: Vector2, scale: float) -> Vector2:
	return center + Vector2((world.x - world.y) * scale, (world.x + world.y) * scale * 0.5)


static func minimap_to_world(screen: Vector2, center: Vector2, scale: float) -> Vector2:
	if scale <= 0.0:
		return Vector2.ZERO
	var relative := screen - center
	var difference := relative.x / scale
	var sum := relative.y * 2.0 / scale
	return Vector2((sum + difference) * 0.5, (sum - difference) * 0.5)


static func map_polygon(map_size: Vector2i, center: Vector2, scale: float) -> PackedVector2Array:
	return PackedVector2Array([
		world_to_minimap(Vector2.ZERO, center, scale),
		world_to_minimap(Vector2(map_size.x, 0), center, scale),
		world_to_minimap(Vector2(map_size.x, map_size.y), center, scale),
		world_to_minimap(Vector2(0, map_size.y), center, scale),
	])


static func contains_world(screen: Vector2, map_size: Vector2i, center: Vector2, scale: float) -> bool:
	var world := minimap_to_world(screen, center, scale)
	return world.x >= 0.0 and world.y >= 0.0 and world.x <= map_size.x and world.y <= map_size.y
