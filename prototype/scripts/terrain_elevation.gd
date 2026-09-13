class_name RoRTerrainElevation

const TerrainRules := preload("res://scripts/terrain_rules.gd")
const Coordinates := preload("res://scripts/coordinates.gd")

const ELEVATION_PIXEL_STEP := 16.0

const CORNER_TOP := 1
const CORNER_RIGHT := 2
const CORNER_BOTTOM := 4
const CORNER_LEFT := 8

# Genie terrain slope indices. The corresponding RoR terrain frames are
# described by each terrain's elevation_graphics table in Empires.dat.
const SLOPE_BY_CORNER_MASK := {
	CORNER_BOTTOM: 1,
	CORNER_TOP: 2,
	CORNER_LEFT: 3,
	CORNER_RIGHT: 4,
	CORNER_BOTTOM | CORNER_LEFT: 5,
	CORNER_TOP | CORNER_LEFT: 6,
	CORNER_RIGHT | CORNER_BOTTOM: 7,
	CORNER_TOP | CORNER_RIGHT: 8,
	CORNER_RIGHT | CORNER_BOTTOM | CORNER_LEFT: 13,
	CORNER_TOP | CORNER_RIGHT | CORNER_LEFT: 14,
	CORNER_TOP | CORNER_LEFT | CORNER_BOTTOM: 15,
	CORNER_TOP | CORNER_RIGHT | CORNER_BOTTOM: 16,
}

var size: Vector2i
var vertex_levels: Dictionary = {}


func _init(map_size: Vector2i = Vector2i.ONE) -> void:
	size = Vector2i(maxi(1, map_size.x), maxi(1, map_size.y))
	clear()


func clear(level: int = 0) -> void:
	vertex_levels.clear()
	for y in range(size.y + 1):
		for x in range(size.x + 1):
			vertex_levels[Vector2i(x, y)] = maxi(0, level)


func set_vertex(vertex: Vector2i, level: int) -> void:
	if vertex.x < 0 or vertex.y < 0 or vertex.x > size.x or vertex.y > size.y:
		return
	vertex_levels[vertex] = maxi(0, level)


func vertex_elevation(vertex: Vector2i) -> int:
	return int(vertex_levels.get(vertex, 0))


func generate_radial_hill(center: Vector2i, radius: int = 4, maximum_elevation: int = 2) -> void:
	clear()
	var safe_radius := maxi(1, radius)
	var safe_maximum := clampi(maximum_elevation, 0, safe_radius)
	for y in range(size.y + 1):
		for x in range(size.x + 1):
			var distance := maxi(absi(x - center.x), absi(y - center.y))
			set_vertex(Vector2i(x, y), clampi(safe_radius - distance, 0, safe_maximum))


func cell_profile(cell: Vector2i) -> Dictionary:
	var corners: Array[int] = [
		vertex_elevation(cell),
		vertex_elevation(cell + Vector2i(1, 0)),
		vertex_elevation(cell + Vector2i(1, 1)),
		vertex_elevation(cell + Vector2i(0, 1)),
	]
	var minimum: int = int(corners.min())
	var maximum: int = int(corners.max())
	var mask := 0
	if maximum > minimum:
		for index in range(corners.size()):
			if corners[index] > minimum:
				mask |= 1 << index
	var valid_gradient: bool = maximum - minimum <= 1 and mask != 5 and mask != 10
	var slope_index := int(SLOPE_BY_CORNER_MASK.get(mask, 0)) if valid_gradient else -1
	return {
		"corners": corners,
		"base_elevation": minimum,
		"maximum_elevation": maximum,
		"corner_mask": mask,
		"slope_index": slope_index,
		"is_flat": minimum == maximum,
		"is_valid": minimum == maximum or slope_index > 0,
		"minimum_screen_y": minimum_corner_screen_y(corners, minimum),
	}


func elevation_at_world(world: Vector2) -> float:
	var clamped := Vector2(
		clampf(world.x, 0.0, float(size.x) - 0.0001),
		clampf(world.y, 0.0, float(size.y) - 0.0001)
	)
	var cell := Vector2i(floori(clamped.x), floori(clamped.y))
	var local := clamped - Vector2(cell)
	var top := lerpf(float(vertex_elevation(cell)), float(vertex_elevation(cell + Vector2i(1, 0))), local.x)
	var bottom := lerpf(float(vertex_elevation(cell + Vector2i(0, 1))), float(vertex_elevation(cell + Vector2i(1, 1))), local.x)
	return lerpf(top, bottom, local.y)


func world_to_screen(world: Vector2, zoom: float, view_offset: Vector2) -> Vector2:
	return Coordinates.world_to_screen(world, zoom, view_offset) + screen_offset(elevation_at_world(world), zoom)


func screen_to_world(screen: Vector2, zoom: float, view_offset: Vector2) -> Vector2:
	var flat_world := Coordinates.screen_to_world(screen, zoom, view_offset)
	var maximum_level := 0
	for level_value in vertex_levels.values():
		maximum_level = maxi(maximum_level, int(level_value))
	if maximum_level <= 0:
		return flat_world
	var low := 0.0
	var high := float(maximum_level) * ELEVATION_PIXEL_STEP / Coordinates.TILE_HEIGHT
	for _iteration in range(24):
		var middle := (low + high) * 0.5
		var candidate := flat_world + Vector2(middle, middle)
		var required_shift := elevation_at_world(candidate) * ELEVATION_PIXEL_STEP / Coordinates.TILE_HEIGHT
		if middle < required_shift:
			low = middle
		else:
			high = middle
	return flat_world + Vector2((low + high) * 0.5, (low + high) * 0.5)


func terrain_frame(terrain_record: Dictionary, profile: Dictionary, cell: Vector2i, map_seed: int) -> int:
	var elevation_graphics: Array = terrain_record.get("elevation_graphics", [])
	var slope_index := int(profile.get("slope_index", -1))
	if slope_index < 0 or slope_index >= elevation_graphics.size():
		return 0
	var graphic: Dictionary = elevation_graphics[slope_index]
	var frame_count := int(graphic.get("frame_count", 0))
	var shape_id := int(graphic.get("shape_id", 0))
	if frame_count <= 0:
		return 0
	if slope_index == 0:
		return shape_id + TerrainRules.tile_variant(cell, "terrain", map_seed, frame_count)
	return shape_id


func tile_screen_origin(flat_center: Vector2, texture_size: Vector2, profile: Dictionary, zoom: float) -> Vector2:
	var base_elevation := float(profile.get("base_elevation", 0.0))
	var minimum_y := float(profile.get("minimum_screen_y", 0.0))
	var x_offset := floorf(texture_size.x * 0.5)
	# Slope sprites are 17/33/49 px high, but all are anchored to the same
	# 64x32 logical tile center. Centering by each bitmap height shifts slopes
	# by eight pixels and opens black diamonds between neighboring cells.
	var y_offset := Coordinates.TILE_HEIGHT * 0.5 + base_elevation * ELEVATION_PIXEL_STEP - minimum_y
	return flat_center - Vector2(x_offset, y_offset) * zoom


static func screen_offset(elevation: float, zoom: float = 1.0) -> Vector2:
	return Vector2(0.0, -elevation * ELEVATION_PIXEL_STEP * zoom)


static func minimum_corner_screen_y(corners: Array[int], base_elevation: int) -> float:
	var projected := [
		0.0 - float(corners[0] - base_elevation) * ELEVATION_PIXEL_STEP,
		16.0 - float(corners[1] - base_elevation) * ELEVATION_PIXEL_STEP,
		32.0 - float(corners[2] - base_elevation) * ELEVATION_PIXEL_STEP,
		16.0 - float(corners[3] - base_elevation) * ELEVATION_PIXEL_STEP,
	]
	return float(projected.min())
