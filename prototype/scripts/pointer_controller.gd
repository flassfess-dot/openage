class_name RoRPointerController

enum State {
	IDLE,
	PRIMARY_PENDING,
	PRIMARY_BOX,
	SECONDARY_PENDING,
	SECONDARY_DIRECTION,
	PANNING,
}

const SELECTION_DRAG_THRESHOLD: float = 9.0
const DIRECTION_DRAG_THRESHOLD: float = 14.0

var state: State = State.IDLE
var anchor := Vector2.ZERO
var current := Vector2.ZERO


func begin_primary(position: Vector2) -> void:
	state = State.PRIMARY_PENDING
	anchor = position
	current = position

func end_primary(position: Vector2) -> Dictionary:
	update_position(position)
	var action: Dictionary = {}
	if state == State.PRIMARY_PENDING:
		action = {"type": "select_click", "from": anchor, "to": current}
	elif state == State.PRIMARY_BOX:
		action = {"type": "select_box", "from": anchor, "to": current}
	reset()
	return action

func begin_secondary(position: Vector2) -> void:
	state = State.SECONDARY_PENDING
	anchor = position
	current = position

func end_secondary(position: Vector2) -> Dictionary:
	update_position(position)
	var action: Dictionary = {}
	if state == State.SECONDARY_PENDING:
		action = {"type": "context_command", "position": current}
	elif state == State.SECONDARY_DIRECTION:
		action = {"type": "formation_direction", "position": anchor, "direction_end": current}
	reset()
	return action

func begin_pan(position: Vector2) -> void:
	state = State.PANNING
	anchor = position
	current = position

func end_pan() -> void:
	if state == State.PANNING:
		reset()

func update_position(position: Vector2) -> Vector2:
	var delta := position - current
	current = position
	if state == State.PRIMARY_PENDING and anchor.distance_to(current) >= SELECTION_DRAG_THRESHOLD:
		state = State.PRIMARY_BOX
	elif state == State.SECONDARY_PENDING and anchor.distance_to(current) >= DIRECTION_DRAG_THRESHOLD:
		state = State.SECONDARY_DIRECTION
	return delta if state == State.PANNING else Vector2.ZERO

func is_selecting() -> bool:
	return state == State.PRIMARY_PENDING or state == State.PRIMARY_BOX

func is_setting_formation_direction() -> bool:
	return state == State.SECONDARY_DIRECTION

func reset() -> void:
	state = State.IDLE
	anchor = Vector2.ZERO
	current = Vector2.ZERO
