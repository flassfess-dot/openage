class_name RoRSimulationEventStream
extends RefCounted

var _events: Array = []
var _next_sequence: int = 1
var _first_sequence: int = 1


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
	if _events.is_empty():
		return result
	# Sequence IDs are contiguous. Looking up a presentation cursor must not
	# rescan and duplicate the entire match history on every rendered frame.
	# The complete journal remains available to diagnostics and scenario tests.
	var start_index := clampi(sequence_id + 1 - _first_sequence, 0, _events.size())
	for index in range(start_index, _events.size()):
		result.append(_events[index].duplicate(true))
	return result


func all_events() -> Array:
	return events_after(0)


func latest_sequence() -> int:
	return _next_sequence - 1


func retained_count() -> int:
	return _events.size()


func prune_through(sequence_id: int) -> void:
	# Only a consumer that has finished processing these events should call this.
	# Sequence IDs stay absolute, so later cursor lookups remain stable.
	var remove_count := clampi(sequence_id - _first_sequence + 1, 0, _events.size())
	if remove_count <= 0:
		return
	_events = _events.slice(remove_count)
	_first_sequence += remove_count


func clear() -> void:
	_events.clear()
	_next_sequence = 1
	_first_sequence = 1
