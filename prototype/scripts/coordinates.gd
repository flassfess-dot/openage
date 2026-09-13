class_name RoRCoordinates

# RoR terrain sprites are 65x33 because they include the shared edge texel.
# Their isometric lattice advances by 64x32; using sprite dimensions as the
# pitch creates alternating one-pixel gaps after snapping.
const TILE_WIDTH: float = 64.0
const TILE_HEIGHT: float = 32.0
const MINIMAP_Y_SCALE: float = 0.5

class WorldPosition:
	var point: Vector2

	func _init(world: Vector2 = Vector2.ZERO) -> void:
		point = Vector2(world.x, world.y)

	func to_vector2() -> Vector2:
		return point

	func with_offset(delta: Vector2) -> WorldPosition:
		return WorldPosition.new(point + delta)

	func to_tile() -> Vector2i:
		return Vector2i(floori(point.x), floori(point.y))

	func is_finite() -> bool:
		return point.is_finite()


class TilePosition:
	var point: Vector2i

	func _init(tile: Vector2i = Vector2i.ZERO) -> void:
		point = Vector2i(tile.x, tile.y)

	func to_vector2() -> Vector2:
		return Vector2(point)

	func to_world() -> WorldPosition:
		return WorldPosition.new(Vector2(point))


class ScreenPosition:
	var point: Vector2

	func _init(screen: Vector2 = Vector2.ZERO) -> void:
		point = Vector2(screen.x, screen.y)

	func to_vector2() -> Vector2:
		return point


static func iso_raw(world: Vector2) -> Vector2:
	return Vector2((world.x - world.y) * TILE_WIDTH * 0.5, (world.x + world.y) * TILE_HEIGHT * 0.5)

static func world_to_screen(world: Vector2, view_zoom: float, view_offset: Vector2) -> Vector2:
	return iso_raw(world) * view_zoom + view_offset

static func screen_to_world(screen: Vector2, view_zoom: float, view_offset: Vector2) -> Vector2:
	var local := (screen - view_offset) / view_zoom
	return Vector2(local.x / TILE_WIDTH + local.y / TILE_HEIGHT, local.y / TILE_HEIGHT - local.x / TILE_WIDTH)

static func minimap_position(world: Vector2, center: Vector2, scale: float) -> Vector2:
	return center + Vector2((world.x - world.y) * scale, (world.x + world.y) * scale * MINIMAP_Y_SCALE)

static func world_to_tile(world: Vector2) -> Vector2i:
	return Vector2i(floori(world.x), floori(world.y))

static func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(float(tile.x), float(tile.y))

static func clamp_world(world: Vector2, map_size: Vector2i) -> Vector2:
	return Vector2(
		clampf(world.x, 0.5, float(map_size.x) - 0.5),
		clampf(world.y, 0.5, float(map_size.y) - 0.5)
	)
