class_name RoRPixelScaling

const DEFAULT_WINDOW_SIZE := Vector2i(1280, 720)
const ZOOM_LEVELS := [1.0, 2.0, 3.0]


static func step_zoom(current: float, direction: int) -> float:
	var nearest_index := 0
	var nearest_distance := INF
	for index in range(ZOOM_LEVELS.size()):
		var distance: float = absf(float(ZOOM_LEVELS[index]) - current)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	return float(ZOOM_LEVELS[clampi(nearest_index + signi(direction), 0, ZOOM_LEVELS.size() - 1)])


static func snap_screen(position: Vector2) -> Vector2:
	return Vector2(roundf(position.x), roundf(position.y))


static func is_pixel_safe_zoom(value: float) -> bool:
	return ZOOM_LEVELS.has(value) and is_equal_approx(value, roundf(value))
