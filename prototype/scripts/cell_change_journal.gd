class_name RoRCellChangeJournal
extends RefCounted

# Non-consuming, bounded change history shared by navigation, terrain and fog.
# Legacy navigation entries keep their serialized keys. Region validity and
# exact-cell validity are separate: a large edit may still have a bounded region.
const DEFAULT_CAPACITY := 256
const MAX_CELLS_PER_ENTRY := 512

static func record_cell(history: Array, before: int, cell: Vector2i, capacity: int = DEFAULT_CAPACITY, retain: int = -1) -> void:
	var entry: Dictionary = {}
	if not history.is_empty() and int(history.back().get("from", -1)) == before:
		entry = history.back()
	else:
		if not history.is_empty() and int(history.back().get("to", -1)) != before:
			history.clear()
		entry = {"from": before, "to": before + 1, "region": Rect2(), "has_region": false, "cells": [], "cells_complete": true}
		history.append(entry)
	var region := Rect2(Vector2(cell), Vector2.ONE)
	entry["region"] = entry["region"].merge(region) if bool(entry.get("has_region", false)) else region
	entry["has_region"] = true
	if bool(entry.get("cells_complete", false)):
		if entry["cells"].size() < MAX_CELLS_PER_ENTRY:
			entry["cells"].append(cell)
		else:
			entry["cells"].clear()
			entry["cells_complete"] = false
	_trim(history, capacity, retain)

static func record_full(history: Array, before: int, after: int, capacity: int = DEFAULT_CAPACITY) -> void:
	history.clear()
	history.append({"from": before, "to": after, "region": Rect2(), "has_region": false, "cells": [], "cells_complete": false})
	_trim(history, capacity)

static func _trim(history: Array, capacity: int, retain: int = -1) -> void:
	if history.size() <= capacity:
		return
	var keep := capacity if retain < 0 else mini(capacity, maxi(1, retain))
	while history.size() > keep:
		history.pop_front()

static func delta(history: Array, previous: int, current: int) -> Dictionary:
	if previous == current:
		return {"revision": current, "full": false, "exact": true, "cells": [], "region": Rect2()}
	var fallback := {"revision": current, "full": true, "exact": false, "cells": [], "region": Rect2()}
	if previous < 0 or previous > current:
		return fallback
	var covered := current
	var cells: Dictionary = {}
	var region := Rect2()
	var has_region := false
	var exact := true
	for index in range(history.size() - 1, -1, -1):
		var entry: Dictionary = history[index]
		if int(entry.get("to", -1)) != covered or not bool(entry.get("has_region", false)):
			return fallback
		region = region.merge(entry["region"]) if has_region else entry["region"]
		has_region = true
		exact = bool(entry.get("cells_complete", false)) and exact
		if exact:
			for cell in entry.get("cells", []):
				cells[cell] = true
		covered = int(entry.get("from", -1))
		if covered <= previous:
			return {"revision": current, "full": false, "exact": exact, "cells": cells.keys() if exact else [], "region": region}
	return fallback
