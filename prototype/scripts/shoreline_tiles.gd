class_name RoRShorelineTiles
extends RefCounted

# The twelve source shoreline frames are opaque replacement tiles, not alpha
# strips. Compose disjoint isometric quarters so several exposed corners never
# paint sand back over another corner's water.
const TILE_SIZE := Vector2i(65, 33)
const CORNER_OFFSETS := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
const CORNER_SIDE_MASKS := [3, 6, 12, 9]
const EDGE_FRAMES := [8, 11, 9, 10]
const CONVEX_FRAMES := [1, 3, 2, 0]
# Source frames 5/7/6/4 put a small water inlet at top/right/bottom/left.
const CONCAVE_FRAMES := [5, 7, 6, 4]
const ISLAND_SOURCE_TIPS := [Vector2i(32, 32), Vector2i(0, 16), Vector2i(32, 0), Vector2i(64, 16)]


static func normalized_mask(mask: int) -> int:
	var result := mask
	for corner in range(4):
		if mask & int(CORNER_SIDE_MASKS[corner]):
			result &= ~(1 << (corner + 4))
	return result


static func quarter_at(pixel: Vector2i) -> int:
	# Inverse of the 64x32 isometric projection, scaled to integer coordinates.
	# The strict comparisons give every shared pixel exactly one owner.
	var u := pixel.x + 2 * pixel.y - 32
	var v := 32 + 2 * pixel.y - pixel.x
	if u < 32:
		return 0 if v < 32 else 3
	return 1 if v < 32 else 2


static func source_frame(mask: int, corner: int) -> int:
	var first := corner
	var second := (corner + 1) % 4
	var first_water := bool(mask & (1 << first))
	var second_water := bool(mask & (1 << second))
	if first_water and second_water:
		return CONVEX_FRAMES[corner]
	if first_water:
		return EDGE_FRAMES[first]
	if second_water:
		return EDGE_FRAMES[second]
	if mask & (1 << (corner + 4)):
		return CONCAVE_FRAMES[corner]
	return -1


static func build_frames(source_textures: Array, source_hotspots: Array, water_texture: Texture2D) -> Array:
	var sources: Array[Image] = []
	for frame in range(12):
		var source: Image = source_textures[frame].get_image()
		var aligned := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
		aligned.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), -Vector2i(source_hotspots[frame]))
		sources.append(aligned)
	var water := water_texture.get_image()
	var frames: Array = []
	var cache := {}
	# Diagonals beside an exposed side are redundant: 256 neighbor masks share
	# only 47 textures. Build once at catalog load, then reuse in the terrain atlas.
	for mask in range(256):
		var key := normalized_mask(mask)
		if not cache.has(key):
			var image: Image = water.duplicate() if (key & 15) == 15 else Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
			var corner_frames: Array[int] = []
			for corner in range(4):
				corner_frames.append(source_frame(key, corner))
			for y in range(TILE_SIZE.y):
				for x in range(TILE_SIZE.x):
					var point := Vector2i(x, y)
					var corner := quarter_at(point)
					var frame := corner_frames[corner]
					if frame < 0:
						continue
					if (key & 15) == 15:
						# Four exposed sides need a central island. Each convex
						# source cape has its sand at the opposite tile vertex;
						# fit each full cape into one quarter, meeting at the
						# center, and retain the original diamond footprint.
						# Original cap vertices can contain land belonging
						# to an adjoining tile. Keep those outside this
						# isolated island and preserve its water perimeter.
						if absi(x - 32) + 2 * absi(y - 16) > 24 or water.get_pixelv(point).a == 0.0:
							continue
						point = ISLAND_SOURCE_TIPS[corner] + (point - Vector2i(32, 16)) * 2
					var pixel := sources[frame].get_pixelv(point)
					if pixel.a == 0.0 and (key & 15) == 15:
						# Shared-edge texels can be absent in an individual
						# source cape; retain the water underlay there.
						continue
					image.set_pixel(x, y, pixel)
			cache[key] = ImageTexture.create_from_image(image)
		frames.append(cache[key])
	return frames
