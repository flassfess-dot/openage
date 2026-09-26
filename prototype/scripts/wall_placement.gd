class_name RoRWallPlacement
extends RefCounted


static func cells(start: Vector2i, finish: Vector2i, maximum_segments: int = 33) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var x := start.x
	var y := start.y
	var dx := absi(finish.x - start.x)
	var dy := absi(finish.y - start.y)
	var step_x := 1 if start.x < finish.x else -1
	var step_y := 1 if start.y < finish.y else -1
	var error := dx - dy
	while result.size() < maximum_segments:
		result.append(Vector2i(x, y))
		if x == finish.x and y == finish.y:
			break
		var doubled_error := error * 2
		if doubled_error > -dy:
			error -= dy
			x += step_x
		if doubled_error < dx:
			error += dx
			y += step_y
	return result
