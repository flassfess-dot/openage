class_name RoRFormationGeometry

const LINE := "LINE"
const BLOCK := "RECTANGLE"
const COLUMN := "COLUMN"
const WEDGE := "WEDGE"
const STAGGER := "STAGGERED"
const ALL := [LINE, BLOCK, COLUMN, WEDGE, STAGGER]


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
			result = _block(count, spacing, true)
		_:
			result = _block(count, spacing, false)
	return _centered(result)


static func world_slots(local: Array[Vector2], anchor: Vector2, forward: Vector2) -> Array[Vector2]:
	var normalized_forward := forward.normalized() if forward.length_squared() > 0.0001 else Vector2(0.0, -1.0)
	var right := Vector2(normalized_forward.y, -normalized_forward.x)
	var result: Array[Vector2] = []
	for offset in local:
		result.append(anchor + right * offset.x + normalized_forward * offset.y)
	return result


static func _line(count: int, spacing: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for index in range(count):
		result.append(Vector2((float(index) - float(count - 1) * 0.5) * spacing, 0.0))
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
