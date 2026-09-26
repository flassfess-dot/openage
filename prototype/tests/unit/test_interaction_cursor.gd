extends SceneTree

const InteractionCursor := preload("res://scripts/interaction_cursor.gd")

var failures: Array[String] = []
var worker := {"id": 1, "kind": "villager", "team": 1, "behavior_tags": ["worker"]}
var soldier := {"id": 2, "kind": "clubman", "team": 1, "behavior_tags": ["military"]}
var priest := {"id": 3, "kind": "priest", "team": 1, "behavior_tags": ["converter"], "components": {"conversion": {"enabled": true}}}
var trader := {"id": 4, "kind": "trade_boat", "team": 1, "components": {"trade": {"enabled": true, "target_building_source_id": 45}}}


func _initialize() -> void:
	assert_semantic([], {"entity_type": "unit", "id": 1, "team": 1}, "select", "friendly entity can be selected")
	assert_semantic([soldier], {"entity_type": "unit", "id": 8, "team": 2}, "attack", "enemy unit advertises attack")
	assert_semantic([priest], {"entity_type": "unit", "id": 8, "team": 2}, "convert", "enemy unit advertises conversion to Priest")
	assert_semantic([worker], {"entity_type": "resource", "id": 9}, "gather", "resource advertises gather to worker")
	assert_semantic([soldier], {"entity_type": "resource", "id": 9}, "default", "military cursor ignores resources")
	assert_semantic([worker], {"entity_type": "building", "id": 10, "team": 1, "hp": 30.0, "max_hp": 100.0}, "select", "friendly building remains selectable on hover")
	assert_semantic([soldier], null, "move", "ground advertises movement for selected units")
	assert_semantic([trader], {"entity_type": "building", "id": 11, "team": 2, "unit_lineage": [45]}, "trade", "foreign Dock advertises trade to a Trade Boat")

	if failures.is_empty():
		print("I3-004 interaction cursor tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_semantic(selected: Array, hovered: Variant, expected: String, context: String) -> void:
	var result := InteractionCursor.resolve(selected, hovered, Vector2(4, 5), 1)
	if String(result.get("semantic", "")) != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, result])
