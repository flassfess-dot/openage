class_name RoRSimulationEventStream
extends RefCounted

var _events: Array = []
var _next_sequence: int = 1


func emit(tick: int, event_type: String, payload: Dictionary = {}) -> Dictionary:
	var event := {
		"sequence_id": _next_sequence,
		"tick": tick,
		"type": event_type,
		"payload": payload.duplicate(true),
	}
	_next_sequence += 1
	_events.append(event)
	return event.duplicate(true)


func events_after(sequence_id: int = 0) -> Array:
	var result: Array = []
	for event in _events:
		if int(event["sequence_id"]) > sequence_id:
			result.append(event.duplicate(true))
	return result


func all_events() -> Array:
	return events_after(0)


func latest_sequence() -> int:
	return _next_sequence - 1


func clear() -> void:
	_events.clear()
	_next_sequence = 1
