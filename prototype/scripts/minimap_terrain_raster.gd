class_name RoRMinimapTerrainRaster
extends RefCounted

const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")


static func build(map_size: Vector2i, rectangle: Rect2, center: Vector2, scale: float, terrain_id_at: Callable) -> Image:
	var width := maxi(1, roundi(rectangle.size.x))
	var height := maxi(1, roundi(rectangle.size.y))
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	if map_size.x <= 0 or map_size.y <= 0 or scale <= 0.0 or not terrain_id_at.is_valid():
		return result
	# Sample the output pixels, not every map tile. Even a supergiant map has a
	# bounded minimap raster and this runs only when terrain or geometry changes.
	for y in range(height):
		for x in range(width):
			var screen := rectangle.position + Vector2(float(x) + 0.5, float(y) + 0.5)
			var world := MinimapProjection.minimap_to_world(screen, center, scale)
			if world.x < 0.0 or world.y < 0.0 or world.x >= map_size.x or world.y >= map_size.y:
				continue
			var cell := Vector2i(floori(world.x), floori(world.y))
			result.set_pixel(x, y, color_for_terrain_id(int(terrain_id_at.call(cell))))
	return result


static func build_fog(map_size: Vector2i, rectangle: Rect2, center: Vector2, scale: float, fog_cells: Variant) -> Image:
	var width := maxi(1, roundi(rectangle.size.x))
	var height := maxi(1, roundi(rectangle.size.y))
	var result := Image.create(width, height, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	if map_size.x <= 0 or map_size.y <= 0 or scale <= 0.0 or fog_cells.size() < map_size.x * map_size.y:
		return result
	# The work is bounded by minimap pixels, even on supergiant maps.
	for y in range(height):
		for x in range(width):
			var screen := rectangle.position + Vector2(float(x) + 0.5, float(y) + 0.5)
			var world := MinimapProjection.minimap_to_world(screen, center, scale)
			if world.x < 0.0 or world.y < 0.0 or world.x >= map_size.x or world.y >= map_size.y:
				continue
			var cell := Vector2i(floori(world.x), floori(world.y))
			var state := int(fog_cells[cell.y * map_size.x + cell.x])
			if state == FogOfWar.UNKNOWN:
				result.set_pixel(x, y, Color.BLACK)
			else:
				# The minimap shows exploration, not the current vision radius.
				result.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.58))
	return result


static func color_for_terrain_id(terrain_id: int) -> Color:
	match terrain_id:
		1, 4: return Color("275991")
		22: return Color("193e75")
		2: return Color("c8ae77")
		6, 13: return Color("b99459")
		10, 19, 20: return Color("315d2b")
		_: return Color("568545")
