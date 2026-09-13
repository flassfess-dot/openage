class_name EntityIdSequence

var _next_id: int = 1

func reset(start: int = 1) -> void:
	_next_id = max(1, start)

func peek() -> int:
	return _next_id

func next() -> int:
	var current := _next_id
	_next_id += 1
	return current

class EntityId:
	var value: int

	func _init(entity_id: int) -> void:
		value = entity_id

	func to_int() -> int:
		return value

	func is_valid() -> bool:
		return value > 0

	func _to_string() -> String:
		return str(value)
