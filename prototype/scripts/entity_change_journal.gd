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
const MUTABLE_GROUPS := ALL ^ LIFECYCLE
const GROUP_COUNT := 8
const MAX_BATCHES := 256
const MAX_PENDING_IDS := 8192
const MAX_RETAINED_IDS := 32768
const MAX_TRACKED_IDS := 262144
const MAX_DELTA_CACHE_ENTRIES := 8
const MAX_DELTA_CACHE_IDS := 1024
const PILOT_FIELDS := ["pos", "task", "hp", "team", "order"]

var native_enabled := OS.get_environment("ROR_DIAGNOSTIC_NATIVE_ENTITY_JOURNAL") != "0"
var native_journal: Variant = ClassDB.instantiate("RoREntityChangeJournalKernel") if ClassDB.class_exists("RoREntityChangeJournalKernel") else null
var native_active: bool:
	get: return native_enabled and native_journal != null
var native_reference: Variant = null
var native_reference_checks := 0
var native_reference_mismatches := 0
var native_reference_resets := 0
var native_direct_readers_requested := OS.get_environment("ROR_DIAGNOSTIC_NATIVE_JOURNAL_READERS") != "0"
var profile_native_readers := "--profile-native-journal-readers" in OS.get_cmdline_user_args()
var native_reader_phase := 0
var native_direct_readers: bool:
	get: return native_direct_readers_requested and (not profile_native_readers or ((native_reader_phase * 1103515245 + 12345) & 0xffff) >= 32768)

var epoch := 0
var revision := 0
var _legacy_versions_by_id: Dictionary = {}
var _legacy_pending: Dictionary = {}
var _legacy_pending_removed: Dictionary = {}
var _legacy_pending_full := false
var _legacy_history: Array = []
var _legacy_retained_ids := 0
var versions_by_id: Dictionary:
	get: return native_journal.export_versions() if native_active else _legacy_versions_by_id
	set(value): _legacy_versions_by_id = value
var pending: Dictionary:
	get: return native_journal.export_pending() if native_active else _legacy_pending
	set(value): _legacy_pending = value
var pending_removed: Dictionary:
	get: return native_journal.export_removed() if native_active else _legacy_pending_removed
	set(value): _legacy_pending_removed = value
var pending_full: bool:
	get: return native_journal.is_full() if native_active else _legacy_pending_full
	set(value): _legacy_pending_full = value
var history: Array:
	get: return native_journal.export_history() if native_active else _legacy_history
	set(value): _legacy_history = value
var retained_ids: int:
	get: return native_journal.retained_ids() if native_active else _legacy_retained_ids
	set(value): _legacy_retained_ids = value
var delta_cache: Dictionary = {}
var performance_probe: Variant = null
var comparison_enabled := false
var comparison_records: Dictionary = {}
var comparison_versions: Dictionary = {}

func reset() -> void:
	if native_enabled and native_journal != null:
		native_reference = null
		native_journal.set_reference_capture(false)
		native_journal.reset()
		_sync_native_head()
		delta_cache.clear()
		comparison_records.clear()
		comparison_versions.clear()
		return
	epoch += 1
	revision = 0
	_legacy_versions_by_id.clear()
	_legacy_pending.clear()
	_legacy_pending_removed.clear()
	_legacy_pending_full = false
	_legacy_history.clear()
	_legacy_retained_ids = 0
	delta_cache.clear()
	comparison_records.clear()
	comparison_versions.clear()

static func field_mask(field: String) -> int:
	match field:
		"pos", "facing", "formation_forward": return POSITION
		"task": return ACTIVITY | COMBAT | CONTROL
		"order": return ACTIVITY | CONTROL
		"hp": return COMBAT | CONTROL
		"team": return OWNERSHIP | ACTIVITY | COMBAT | ECONOMY | APPEARANCE | CONTROL
	match field:
		"previous_pos", "anim", "anim_event_frame": return 0
		"footprint_radius": return POSITION | ACTIVITY | COMBAT | CONTROL
		"target", "actual_velocity", "minimum_clearance", "push_priority", "movement_domain", "terrain_restriction": return POSITION | ACTIVITY | CONTROL
		"path", "path_index", "stuck_ticks", "cohesion_speed_scale", "cooldown", "work", "faith": return ACTIVITY | CONTROL
		"state", "death_phase", "combat_enabled", "retaliation_target_id", "target_id", "attack_autonomous", "stance", "combat_pursuit", "behavior_tags", "components": return ACTIVITY | COMBAT | APPEARANCE | CONTROL
		"production_queue", "construction_progress", "construction_remaining", "builders", "amount", "cargo", "source_unit_id", "unit_lineage": return ECONOMY | APPEARANCE | CONTROL
	return APPEARANCE | CONTROL

func mark(entity_id: int, mask: int) -> void:
	if native_enabled and native_journal != null:
		native_journal.mark(entity_id, mask)
		return
	mask &= ALL
	if entity_id < 0 or mask == 0:
		return
	if (int(_legacy_pending.get(entity_id, 0)) & mask) == mask: return
	var versions: PackedInt64Array = _legacy_versions_by_id.get(entity_id, PackedInt64Array())
	if versions.is_empty():
		if _legacy_versions_by_id.size() >= MAX_TRACKED_IDS:
			_legacy_pending.clear()
			_legacy_pending_removed.clear()
			_legacy_pending_full = true
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
	_legacy_versions_by_id[entity_id] = versions
	if performance_probe != null:
		performance_probe.increment("entities.mark_calls")
	if _legacy_pending_full:
		return
	_legacy_pending[entity_id] = int(_legacy_pending.get(entity_id, 0)) | mask
	if _legacy_pending.size() > MAX_PENDING_IDS:
		_legacy_pending.clear()
		_legacy_pending_removed.clear()
		_legacy_pending_full = true

func remove(entity_id: int) -> void:
	if native_enabled and native_journal != null:
		native_journal.remove(entity_id)
		return
	mark(entity_id, ALL)
	_legacy_versions_by_id.erase(entity_id)
	if not _legacy_pending_full:
		_legacy_pending_removed[entity_id] = true

func flush() -> void:
	if native_enabled and native_journal != null:
		native_journal.flush()
		_sync_native_head()
		return
	if _legacy_pending.is_empty() and not _legacy_pending_full:
		return
	delta_cache.clear()
	var before := revision
	revision += 1
	var entry := {"from": before, "to": revision, "full": _legacy_pending_full, "masks": _legacy_pending, "removed": _legacy_pending_removed}
	_legacy_history.append(entry)
	_legacy_retained_ids += _legacy_pending.size()
	if performance_probe != null:
		performance_probe.increment("entities.published_ids", _legacy_pending.size())
		if _legacy_pending_full: performance_probe.increment("entities.full.pending_overflow")
	_legacy_pending = {}
	_legacy_pending_removed = {}
	_legacy_pending_full = false
	while _legacy_history.size() > MAX_BATCHES or _legacy_retained_ids > MAX_RETAINED_IDS:
		var expired: Dictionary = _legacy_history.pop_front()
		_legacy_retained_ids -= expired["masks"].size()

func revision_for(entity_id: int, mask: int = ALL) -> int:
	if native_enabled and native_journal != null: return int(native_journal.revision_for(entity_id, mask))
	var versions: PackedInt64Array = _legacy_versions_by_id.get(entity_id, PackedInt64Array())
	var result := -1
	for group in range(versions.size()):
		if mask & (1 << group): result = maxi(result, int(versions[group]))
	return result

func changes_since(before: int) -> Dictionary:
	if native_enabled and native_journal != null:
		var result: Dictionary = native_journal.changes_since(before)
		_sync_native_head()
		_compare_native_delta(before, result)
		return result
	flush()
	if delta_cache.has(before):
		if performance_probe != null: performance_probe.increment("entities.delta_cache_hits")
		# Each consumer still owns mutable containers, including CacheDependency's
		# outer stamp. A consumer edit cannot poison another reader's cached delta.
		return delta_cache[before].duplicate(true)
	var result := _collect_changes_since(before)
	if not bool(result["full"]) and result["ids"].size() <= MAX_DELTA_CACHE_IDS:
		if delta_cache.size() >= MAX_DELTA_CACHE_ENTRIES: delta_cache.clear()
		delta_cache[before] = result.duplicate(true)
	return result


func read_changes_since(before: int) -> Dictionary:
	# The descriptor belongs to the reader; ids/masks/removed_ids may be shared
	# immutable collections. Mutating consumers keep using changes_since().
	if native_enabled and native_journal != null and native_journal.has_method("read_changes_since"):
		var result: Dictionary = native_journal.read_changes_since(before)
		_sync_native_head()
		_compare_native_delta(before, result)
		return result
	return changes_since(before)


func is_dirty() -> bool:
	return native_journal.is_dirty() if native_active else not _legacy_pending.is_empty() or _legacy_pending_full


func version_source() -> Variant:
	# Borrowed only by synchronous native readers; never part of an AI/UI DTO.
	if native_active: return native_journal if native_direct_readers else versions_by_id
	return _legacy_versions_by_id


func _sync_native_head() -> void:
	epoch = int(native_journal.get_epoch())
	revision = int(native_journal.get_revision())


func begin_native_comparison() -> void:
	if not native_active: return
	_seed_native_reference()
	native_reference_checks = 0
	native_reference_mismatches = 0
	native_reference_resets = 0
	native_journal.set_reference_capture(true)


func _seed_native_reference() -> void:
	native_reference = get_script().new()
	native_reference.native_enabled = false
	native_reference.native_journal = null
	var state: Dictionary = native_journal.export_state()
	for field in state: native_reference.set(field, state[field])


func _compare_native_delta(before: int, result: Dictionary) -> void:
	if native_reference == null: return
	var captured: Dictionary = native_journal.take_reference_events()
	if bool(captured["overflow"]):
		native_reference_resets += 1
		_seed_native_reference()
		return
	var events: PackedInt64Array = captured["events"]
	for index in range(0, events.size(), 3):
		match int(events[index]):
			0: native_reference.mark(int(events[index+1]), int(events[index+2]))
			1: native_reference.remove(int(events[index+1]))
			2: native_reference.flush()
			3: native_reference.reset()
	var expected: Dictionary = native_reference.changes_since(before)
	var mismatch := expected != result or epoch != int(native_reference.epoch) or revision != int(native_reference.revision)
	var ids: Array = result["ids"]
	for id in ids.slice(0,32):
		for group in range(GROUP_COUNT):
			mismatch = mismatch or revision_for(int(id), 1 << group) != int(native_reference.revision_for(int(id), 1 << group))
	if not ids.is_empty() or bool(result["full"]): native_reference_checks += 1
	if mismatch:
		native_reference_mismatches += 1
		push_error("Native entity journal differs from the reference history/versions")
	if native_reference_checks >= 128:
		native_journal.set_reference_capture(false)
		native_reference = null


func _collect_changes_since(before: int) -> Dictionary:
	var result := {"revision": revision, "full": false, "exact": true, "ids": [], "masks": {}, "removed_ids": [], "reason": ""}
	if before == revision: return result
	if before < 0 or before > revision:
		return _full("new_consumer")
	var covered := before
	var masks: Dictionary = {}
	var removed: Dictionary = {}
	# Readers normally need only the last one or two batches. Locate their
	# cursor without walking the complete retained _legacy_history on every query.
	var first := 0
	var last := _legacy_history.size()
	while first < last:
		var middle := (first + last) / 2
		if int(_legacy_history[middle]["to"]) <= before: first = middle + 1
		else: last = middle
	for index in range(first, _legacy_history.size()):
		var entry: Dictionary = _legacy_history[index]
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
