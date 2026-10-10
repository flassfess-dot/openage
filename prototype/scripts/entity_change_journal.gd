class_name RoREntityChangeJournal
extends RefCounted

# Derived, non-consuming history. IDs and versions never enter canonical state.
# A publication boundary closes a batch; writes after a read open a new batch,
# even within the same simulation tick, so independent consumers miss nothing.
const LIFECYCLE := 1
const POSITION := 2
const ACTIVITY := 4
const COMBAT := 8
const ECONOMY := 16
const APPEARANCE := 32
const CONTROL := 64
const OWNERSHIP := 128
const ALL := 255
const GROUP_COUNT := 8
const MAX_BATCHES := 256
const MAX_PENDING_IDS := 8192
const MAX_RETAINED_IDS := 32768
const MAX_TRACKED_IDS := 262144
const PILOT_FIELDS := ["pos", "task", "hp", "team", "order"]

var epoch := 0
var revision := 0
var versions_by_id: Dictionary = {}
var pending: Dictionary = {}
var pending_removed: Dictionary = {}
var pending_full := false
var history: Array = []
var retained_ids := 0
var performance_probe: Variant = null
var comparison_enabled := false
var comparison_records: Dictionary = {}
var comparison_versions: Dictionary = {}

func reset() -> void:
	epoch += 1
	revision = 0
	versions_by_id.clear()
	pending.clear()
	pending_removed.clear()
	pending_full = false
	history.clear()
	retained_ids = 0
	comparison_records.clear()
	comparison_versions.clear()

static func field_mask(field: String) -> int:
	match field:
		"pos", "facing", "formation_forward": return POSITION
		"task", "order": return ACTIVITY | CONTROL
		"hp": return COMBAT | CONTROL
		"team": return OWNERSHIP | ACTIVITY | COMBAT | ECONOMY | APPEARANCE | CONTROL
	match field:
		"previous_pos", "anim", "anim_event_frame": return 0
		"target", "actual_velocity", "footprint_radius", "minimum_clearance", "push_priority", "movement_domain", "terrain_restriction": return POSITION | ACTIVITY | CONTROL
		"path", "path_index", "stuck_ticks", "cohesion_speed_scale", "cooldown", "work", "faith": return ACTIVITY | CONTROL
		"state", "death_phase", "combat_enabled", "retaliation_target_id", "target_id", "attack_autonomous", "stance": return ACTIVITY | COMBAT | APPEARANCE | CONTROL
		"production_queue", "construction_progress", "construction_remaining", "builders", "amount", "cargo", "source_unit_id", "unit_lineage": return ECONOMY | APPEARANCE | CONTROL
	return APPEARANCE | CONTROL

func mark(entity_id: int, mask: int) -> void:
	mask &= ALL
	if entity_id < 0 or mask == 0:
		return
	if (int(pending.get(entity_id, 0)) & mask) == mask: return
	var versions: PackedInt64Array = versions_by_id.get(entity_id, PackedInt64Array())
	if versions.is_empty():
		if versions_by_id.size() >= MAX_TRACKED_IDS:
			pending.clear()
			pending_removed.clear()
			pending_full = true
			if performance_probe != null: performance_probe.increment("entities.full.version_capacity")
			return
		versions.resize(GROUP_COUNT)
	var next_version := revision + 1
	# Scalar hot paths avoid testing all eight groups for each moving unit.
	if mask == POSITION:
		versions[1] = next_version
	elif mask == (ACTIVITY | CONTROL):
		versions[2] = next_version
		versions[6] = next_version
	elif mask == (COMBAT | CONTROL):
		versions[3] = next_version
		versions[6] = next_version
	else:
		for group in range(GROUP_COUNT):
			if mask & (1 << group):
				versions[group] = next_version
	versions_by_id[entity_id] = versions
	if performance_probe != null:
		performance_probe.increment("entities.mark_calls")
	if pending_full:
		return
	pending[entity_id] = int(pending.get(entity_id, 0)) | mask
	if pending.size() > MAX_PENDING_IDS:
		pending.clear()
		pending_removed.clear()
		pending_full = true

func remove(entity_id: int) -> void:
	mark(entity_id, ALL)
	versions_by_id.erase(entity_id)
	if not pending_full:
		pending_removed[entity_id] = true

func flush() -> void:
	if pending.is_empty() and not pending_full:
		return
	var before := revision
	revision += 1
	var entry := {"from": before, "to": revision, "full": pending_full, "masks": pending, "removed": pending_removed}
	history.append(entry)
	retained_ids += pending.size()
	if performance_probe != null:
		performance_probe.increment("entities.published_ids", pending.size())
		if pending_full: performance_probe.increment("entities.full.pending_overflow")
	pending = {}
	pending_removed = {}
	pending_full = false
	while history.size() > MAX_BATCHES or retained_ids > MAX_RETAINED_IDS:
		var expired: Dictionary = history.pop_front()
		retained_ids -= expired["masks"].size()

func revision_for(entity_id: int, mask: int = ALL) -> int:
	var versions: PackedInt64Array = versions_by_id.get(entity_id, PackedInt64Array())
	var result := -1
	for group in range(versions.size()):
		if mask & (1 << group): result = maxi(result, int(versions[group]))
	return result

func changes_since(before: int) -> Dictionary:
	flush()
	var result := {"revision": revision, "full": false, "exact": true, "ids": [], "masks": {}, "removed_ids": [], "reason": ""}
	if before == revision: return result
	if before < 0 or before > revision:
		return _full("new_consumer")
	var covered := before
	var masks: Dictionary = {}
	var removed: Dictionary = {}
	for entry in history:
		if int(entry["to"]) <= before: continue
		if int(entry["from"]) != covered: return _full("history_overflow")
		if bool(entry["full"]): return _full("pending_overflow")
		for id in entry["masks"]:
			masks[id] = int(masks.get(id, 0)) | int(entry["masks"][id])
		for id in entry["removed"]: removed[id] = true
		covered = int(entry["to"])
	if covered != revision: return _full("history_overflow")
	var ids: Array = masks.keys()
	ids.sort()
	var removed_ids: Array = removed.keys()
	removed_ids.sort()
	result["ids"] = ids
	result["masks"] = masks
	result["removed_ids"] = removed_ids
	return result

func _full(reason: String) -> Dictionary:
	if performance_probe != null: performance_probe.increment("entities.full." + reason)
	return {"revision": revision, "full": true, "exact": false, "ids": [], "masks": {}, "removed_ids": [], "reason": reason}

func set_comparison_enabled(enabled: bool, entities: Array) -> void:
	comparison_enabled = enabled
	comparison_records.clear()
	comparison_versions.clear()
	if enabled: compare(entities)

# Explicit debug oracle, never invoked in normal gameplay. Each pilot write
# must advance its group, including changes to existing records after import.
func compare(entities: Array) -> Array:
	var missed: Array = []
	var records: Dictionary = {}
	var versions: Dictionary = {}
	for entity in entities:
		var id := int(entity.get("id", -1))
		if id < 0: continue
		var record: Array = []
		for field in PILOT_FIELDS:
			record.append(entity.get("components", {}).get("order", {}).duplicate(true) if field == "order" else entity.get(field))
		records[id] = record
		versions[id] = versions_by_id.get(id, PackedInt64Array()).duplicate()
		if not versions_by_id.has(id):
			missed.append({"id": id, "field": "created"})
			continue
		if not comparison_records.has(id): continue
		for index in range(PILOT_FIELDS.size()):
			if record[index] == comparison_records[id][index]: continue
			var mask := field_mask(PILOT_FIELDS[index])
			var old: PackedInt64Array = comparison_versions[id]
			var current: PackedInt64Array = versions[id]
			for group in range(GROUP_COUNT):
				if mask & (1 << group) and (old.size() <= group or current[group] <= old[group]):
					missed.append({"id": id, "field": PILOT_FIELDS[index], "group": group})
	for id in comparison_records:
		if not records.has(id) and versions_by_id.has(id): missed.append({"id": id, "field": "removed"})
	comparison_records = records
	comparison_versions = versions
	if performance_probe != null: performance_probe.increment("entities.comparison_scanned", entities.size())
	return missed
