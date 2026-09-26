extends SceneTree

const PlayerControlState := preload("res://scripts/player_control_state.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var units := [
		{"id": 1, "team": 1, "entity_type": "unit", "kind": "swordsman", "source_unit_id": 75, "pos": Vector2(20, 40), "hp": 40.0},
		{"id": 2, "team": 1, "entity_type": "unit", "kind": "swordsman", "source_unit_id": 75, "pos": Vector2(70, 40), "hp": 40.0},
		{"id": 3, "team": 1, "entity_type": "unit", "kind": "swordsman", "source_unit_id": 75, "pos": Vector2(170, 40), "hp": 40.0},
		{"id": 4, "team": 1, "entity_type": "unit", "kind": "swordsman", "source_unit_id": 77, "pos": Vector2(30, 40), "hp": 40.0},
		{"id": 5, "team": 2, "entity_type": "unit", "kind": "swordsman", "source_unit_id": 75, "pos": Vector2(40, 40), "hp": 40.0},
		{"id": 6, "team": 1, "entity_type": "unit", "kind": "swordsman", "source_unit_id": 75, "pos": Vector2(50, 40), "hp": 0.0},
	]
	var project := func(position: Vector2): return position
	var ids: Array[int] = PlayerControlState.same_type_visible_ids(units, units[0], 1, Rect2(0, 20, 100, 100), project)
	assert_equal(ids, [1, 2], "double click includes only living own matching source units in the viewport")
	assert_equal(PlayerControlState.same_type_visible_ids(units, units[4], 1, Rect2(0, 20, 100, 100), project), [], "enemy click cannot expand own selection")
	var fallback := [{"id": 7, "team": 1, "entity_type": "unit", "kind": "scout", "pos": Vector2(20, 40), "hp": 10.0}, {"id": 8, "team": 1, "entity_type": "unit", "kind": "scout", "pos": Vector2(30, 40), "hp": 10.0}]
	assert_equal(PlayerControlState.same_type_visible_ids(fallback, fallback[0], 1, Rect2(0, 20, 100, 100), project), [7, 8], "resolved kind is fallback when source ID is unavailable")
	if failures.is_empty():
		print("P08 viewport selection shortcut tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
