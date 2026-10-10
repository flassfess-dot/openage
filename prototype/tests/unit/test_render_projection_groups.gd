extends SceneTree
const Cache := preload("res://scripts/render_entity_projection_cache.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var journal := Journal.new()
	var cache := Cache.new()
	var source := {"id": 7, "team": 1, "entity_type": "building", "kind": "house", "pos": Vector2(8, 8), "hp": 100.0, "max_hp": 100.0, "anim": 0.0, "anim_state": "Idle", "footprint": {"half_size": Vector2.ONE}, "components": {"ownership": {"civilization_id": 13}}}
	journal.mark(7, Journal.ALL)
	var first: Dictionary = cache.project(source, journal)
	check(is_same(first, cache.project(source, journal)), "unchanged facts reuse the same immutable row")
	source["hp"] = 75.0
	journal.mark(7, Journal.COMBAT | Journal.CONTROL)
	var damaged: Dictionary = cache.project(source, journal)
	check(damaged["hp"] == 75.0 and first["hp"] == 100.0, "damage does not mutate an old publication")
	check(is_same(damaged["footprint"], first["footprint"]), "damage preserves unrelated immutable geometry")
	source["anim"] = 0.25
	var animated: Dictionary = cache.project(source, journal)
	check(animated["anim"] == 0.25 and damaged["anim"] == 0.0, "animation advances independently of factual versions")
	check(is_same(animated["footprint"], damaged["footprint"]), "animation does not rebuild nested geometry")
	source["pos"] = Vector2(9, 8)
	journal.mark(7, Journal.POSITION)
	var moved: Dictionary = cache.project(source, journal)
	check(moved["pos"] == Vector2(9, 8) and first["pos"] == Vector2(8, 8), "position updates preserve old rows")
	for failure in failures: push_error(failure)
	print("Render projection groups: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
