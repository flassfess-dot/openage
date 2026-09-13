class_name RoRViewportCulling
extends RefCounted


static func tile_bounds(map_size: Vector2i, world_corners: Array[Vector2], margin: int = 3) -> Rect2i:
	if world_corners.is_empty():
		return Rect2i(Vector2i.ZERO, map_size)
	var minimum := world_corners[0]
	var maximum := world_corners[0]
	for point in world_corners.slice(1):
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	var start := Vector2i(
		clampi(floori(minimum.x) - margin, 0, map_size.x),
		clampi(floori(minimum.y) - margin, 0, map_size.y)
	)
	var finish := Vector2i(
		clampi(ceili(maximum.x) + margin + 1, start.x, map_size.x),
		clampi(ceili(maximum.y) + margin + 1, start.y, map_size.y)
	)
	return Rect2i(start, finish - start)


static func fog_runs(cells: Variant, map_size: Vector2i, visible_state: int) -> Array:
	var result: Array = []
	if cells.size() < map_size.x * map_size.y:
		return result
	for y in range(map_size.y):
		var run_start := 0
		var run_state := int(cells[y * map_size.x])
		for x in range(1, map_size.x + 1):
			var state := int(cells[y * map_size.x + x]) if x < map_size.x else -1
			if state == run_state:
				continue
			if run_state != visible_state:
				result.append({"y": y, "x_from": run_start, "x_to": x, "state": run_state})
			run_start = x
			run_state = state
	return result
