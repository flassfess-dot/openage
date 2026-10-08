extends RefCounted

const Data := preload("res://scripts/isolated_task_data.gd")

# This producer owns the list and validates each replacement before publishing.
# Readers retain an immutable version; the next edit copies only the outer list.
# Eviction from Data's bounded acceleration registry does not invalidate the
# producer's proof: neither the published list nor its children can be mutated.
var _records: Array = []

func upsert(record: Dictionary) -> bool:
	if not Data.freeze_detached(record, 0, false):
		push_error("Resource publication must contain detached values")
		return false
	var index := _lower_bound(int(record["id"]))
	_edit()
	if index < _records.size() and int(_records[index]["id"]) == int(record["id"]):
		_records[index] = record
	else:
		_records.insert(index, record)
	return true

func erase(resource_id: int) -> void:
	var index := _lower_bound(resource_id)
	if index >= _records.size() or int(_records[index]["id"]) != resource_id:
		return
	_edit()
	_records.remove_at(index)

func snapshot() -> Array:
	if not _records.is_read_only():
		_records.make_read_only()
	if not Data.is_trusted_immutable(_records):
		Data._retain_immutable(_records)
	return _records

func _edit() -> void:
	if _records.is_read_only():
		_records = _records.duplicate()

func _lower_bound(resource_id: int) -> int:
	var low := 0
	var high := _records.size()
	while low < high:
		var middle := (low + high) / 2
		if int(_records[middle]["id"]) < resource_id:
			low = middle + 1
		else:
			high = middle
	return low
