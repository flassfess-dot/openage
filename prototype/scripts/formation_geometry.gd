class_name RoRFormationGeometry

const LINE := "LINE"
const BLOCK := "RECTANGLE"
const COLUMN := "COLUMN"
const WEDGE := "WEDGE"
const STAGGER := "STAGGERED"
const FLANK := "FLANK"
const ALL := [LINE, BLOCK, COLUMN, WEDGE, STAGGER, FLANK]


static func local_slots(count: int, formation_type: String, spacing: float = 1.0) -> Array[Vector2]:
	if count <= 0:
		return []
	var result: Array[Vector2]
	match formation_type:
		LINE:
			result = _line(count, spacing)
		COLUMN:
			result = _column(count, spacing)
		WEDGE:
			result = _wedge(count, spacing)
		STAGGER:
			result = ranks(count, line_width(count), spacing * 1.7, true)
		FLANK:
			result = _flank(count, spacing)
		_:
			result = _box(count, spacing)
	return _centered(result)


static func world_slots(local: Array[Vector2], anchor: Vector2, forward: Vector2) -> Array[Vector2]:
	var normalized_forward := forward.normalized() if forward.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var right := Vector2(normalized_forward.y, -normalized_forward.x)
	var result: Array[Vector2] = []
	for offset in local:
		result.append(anchor + right * offset.x + normalized_forward * offset.y)
	return result


static func line_width(count: int) -> int:
	return mini(count, mini(20, maxi(1, ceili(sqrt(float(count) * 2.0)))))


static func _line(count: int, spacing: float) -> Array[Vector2]:
	return ranks(count, line_width(count), spacing)


static func ranks(count: int, width: int, spacing: float, staggered: bool = false) -> Array[Vector2]:
	var result: Array[Vector2] = []
	width = maxi(1, width)
	var rows := ceili(float(count) / float(width))
	for index in range(count):
		var row := index / width
		var row_count := mini(width, count - row * width)
		var x := (float(index % width) - float(row_count - 1) * 0.5) * spacing
		if staggered and row % 2 == 1: x += spacing * 0.5
		result.append(Vector2(x, (float(rows - 1) * 0.5 - row) * spacing * 1.1))
	return _centered(result) if not result.is_empty() else result


static func _box(count: int, spacing: float) -> Array[Vector2]:
	if count <= 4:
		return _block(count, spacing, false)
	var width := ceili(sqrt(float(count)))
	var outer_count := mini(count - 1, 4 * (width - 1))
	var half := float(width - 1) * spacing * 0.75
	var result := _box(count - outer_count, spacing)
	for index in range(outer_count):
		var perimeter := float(index) * 4.0 / float(outer_count)
		var side := floori(perimeter)
		var along := lerpf(-half, half, perimeter - side)
		match side:
			0: result.append(Vector2(along, half))
			1: result.append(Vector2(half, -along))
			2: result.append(Vector2(-along, -half))
			3: result.append(Vector2(-half, along))
	return result


static func _flank(count: int, spacing: float) -> Array[Vector2]:
	var left_count := (count + 1) / 2
	var width := maxi(1, ceili(sqrt(float(left_count))))
	var result: Array[Vector2] = []
	for side in [-1, 1]:
		var side_count := left_count if side < 0 else count - left_count
		for offset in ranks(side_count, width, spacing):
			result.append(offset + Vector2(float(side) * float(width + 2) * spacing * 0.5, 0))
	return result


static func _column(count: int, spacing: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in range(count):
		result.append(Vector2(0.0, (float(count - 1) * 0.5 - float(index)) * spacing))
	return result


static func _block(count: int, spacing: float, staggered: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var width := ceili(sqrt(float(count)))
	var rows := ceili(float(count) / float(width))
	var slot := 0
	for row in range(rows):
		var row_count := mini(width, count - slot)
		var stagger := spacing * 0.5 if staggered and row % 2 == 1 else 0.0
		for column in range(row_count):
			var lateral := (float(column) - float(row_count - 1) * 0.5) * spacing + stagger
			var depth := (float(rows - 1) * 0.5 - float(row)) * spacing * 1.1
			result.append(Vector2(lateral, depth))
			slot += 1
	return result


static func _wedge(count: int, spacing: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var pair_count := count / 2
	if count % 2 == 1:
		result.append(Vector2(0.0, spacing * 0.5))
	for pair in range(pair_count):
		var row := float(pair + 1)
		var lateral := (row + 0.5) * spacing
		var depth := -row * spacing * 0.75
		result.append(Vector2(-lateral, depth))
		result.append(Vector2(lateral, depth))
	return result


static func _centered(values: Array[Vector2]) -> Array[Vector2]:
	var center := Vector2.ZERO
	for value in values:
		center += value
	center /= float(values.size())
	var result: Array[Vector2] = []
	for value in values:
		result.append(value - center)
	return result
