extends SceneTree
const Journal := preload("res://scripts/entity_change_journal.gd")
const Probe := preload("res://scripts/performance_probe.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var journal := Journal.new()
	journal.mark(7, Journal.ALL)
	journal.flush()
	var cursor := journal.revision
	journal.mark(7, Journal.POSITION)
	journal.mark(7, Journal.POSITION | Journal.COMBAT)
	journal.mark(8, Journal.CONTROL)
	var first := journal.changes_since(cursor)
	check(first["ids"] == [7, 8] and first["masks"][7] == (Journal.POSITION | Journal.COMBAT), "repeated writes coalesce by ID and group")
	check(journal.changes_since(cursor) == first, "independent consumers read identical non-consuming deltas")
	check(journal.revision == cursor + 1, "one publication has one revision")
	var second_cursor := journal.revision
	journal.mark(7, Journal.POSITION)
	check(journal.changes_since(second_cursor)["ids"] == [7], "a write after publication in the same tick remains visible")
	check(first["masks"][7] == (Journal.POSITION | Journal.COMBAT), "old delta remains detached from later batches")
	var removed_cursor := journal.revision
	journal.remove(7)
	check(journal.changes_since(removed_cursor)["removed_ids"] == [7], "deletion tombstone survives publication")
	check(journal.revision_for(7) == -1, "removed versions do not accumulate")
	for index in range(Journal.MAX_BATCHES + 1):
		journal.mark(8, Journal.POSITION)
		journal.flush()
	check(journal.history.size() <= Journal.MAX_BATCHES and journal.changes_since(second_cursor)["reason"] == "history_overflow", "lagging consumers request full synchronization")
	journal.reset()
	for id in range(Journal.MAX_PENDING_IDS + 1): journal.mark(id, Journal.POSITION)
	check(journal.pending.size() <= Journal.MAX_PENDING_IDS, "pending IDs have a hard limit")
	check(journal.changes_since(0)["reason"] == "pending_overflow", "large batches have an explicit full-sync fallback")
	check(journal.revision_for(Journal.MAX_PENDING_IDS, Journal.POSITION) > 0, "overflow does not discard live entity versions")
	journal.reset()
	var entity := {"id": 1, "pos": Vector2.ZERO, "task": "idle", "hp": 10.0, "team": 1}
	journal.mark(1, Journal.ALL)
	journal.flush()
	journal.set_comparison_enabled(true, [entity])
	entity["pos"] = Vector2.ONE
	check(not journal.compare([entity]).is_empty(), "debug oracle catches a missing position notification")
	journal.mark(1, Journal.POSITION)
	journal.flush()
	entity["pos"] = Vector2(2, 2)
	journal.mark(1, Journal.POSITION)
	journal.flush()
	check(journal.compare([entity]).is_empty(), "debug oracle accepts explicit changes")
	var stats := Probe.summarize([0, 50000, 50001, 100001, 200001])
	check(stats["p99"] == 200001 and stats["over_50ms"] == 3 and stats["over_100ms"] == 2 and stats["over_200ms"] == 1, "tail statistics include strict threshold exceedances")
	for failure in failures: push_error(failure)
	print("Entity change journal: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
