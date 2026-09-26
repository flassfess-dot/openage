extends SceneTree

const EventStream := preload("res://scripts/simulation_event_stream.gd")


func _initialize() -> void:
	var stream := EventStream.new()
	for index in range(20000):
		stream.emit(index, "sample", {"index": index})
	var recent := stream.events_after(19990)
	var valid := stream.latest_sequence() == 20000 and recent.size() == 10
	valid = valid and int(recent[0].get("sequence_id", -1)) == 19991 and int(recent[-1].get("sequence_id", -1)) == 20000
	valid = valid and stream.all_events().size() == 20000
	stream.prune_through(12000)
	valid = valid and stream.retained_count() == 8000 and stream.latest_sequence() == 20000
	valid = valid and stream.events_after(11999).size() == 8000 and stream.events_after(19990).size() == 10
	stream.emit(20000, "after_prune")
	valid = valid and int(stream.events_after(20000)[0].get("sequence_id", -1)) == 20001
	if not valid:
		push_error("Event stream must preserve the default journal and stable cursors after explicit pruning")
		quit(1)
		return
	print("Full event journal, explicit pruning and fast cursor tests passed")
	quit(0)
