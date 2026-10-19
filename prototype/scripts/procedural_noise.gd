extends RefCounted

# Shared deterministic arithmetic; changing it changes existing map seeds.
static func smooth(point: Vector2, scale: float, seed: int) -> float:
	var sample := point / maxf(1.0, scale)
	var origin := Vector2i(floori(sample.x), floori(sample.y))
	var fraction := sample - Vector2(origin)
	var smooth_x := fraction.x * fraction.x * (3.0 - 2.0 * fraction.x)
	var smooth_y := fraction.y * fraction.y * (3.0 - 2.0 * fraction.y)
	var top := lerpf(hash_cell(origin, seed), hash_cell(origin + Vector2i.RIGHT, seed), smooth_x)
	var bottom := lerpf(hash_cell(origin + Vector2i.DOWN, seed), hash_cell(origin + Vector2i.ONE, seed), smooth_x)
	return lerpf(top, bottom, smooth_y)


static func hash_cell(cell: Vector2i, seed: int) -> float:
	# Keep the mixing constants and integer truncation stable across generators.
	var value := (int(cell.x) * 73856093) ^ (int(cell.y) * 19349663) ^ (seed * 83492791)
	value = ((value ^ (value >> 16)) * 0x7feb352d) & 0xffffffff
	value = ((value ^ (value >> 15)) * 0x846ca68b) & 0xffffffff
	value = (value ^ (value >> 16)) & 0xffffffff
	return float(value) / 4294967295.0 * 2.0 - 1.0
