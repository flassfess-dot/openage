extends SceneTree

const ContextResolver := preload("res://scripts/context_resolver.gd")

var failures: Array[String] = []
var workers := [{"id": 1, "kind": "villager"}]
var military := [{"id": 2, "kind": "clubman"}]


func _initialize() -> void:
	test_attack_and_move()
	test_worker_actions()
	test_priest_conversion()
	test_priest_healing()
	test_transport_boarding()
	test_trade_route()

	if failures.is_empty():
		print("C-005 context resolver tests passed")
		quit(0)
		return

	for failure in failures:
		push_error(failure)
	quit(1)


func test_attack_and_move() -> void:
	var enemy := {"entity_type": "unit", "id": 8, "team": 2}
	assert_equal(ContextResolver.resolve(military, enemy, Vector2.ZERO, 1), {"type": "attack", "target_id": 8}, "enemy resolves to attack")
	var ground := Vector2(6.0, 7.0)
	assert_equal(ContextResolver.resolve(military, null, ground, 1), {"type": "move", "target": ground}, "ground resolves to move")
	var resource := {"entity_type": "resource", "id": 11}
	assert_equal(ContextResolver.resolve(military, resource, ground, 1), {"type": "unsupported", "reason": "no_worker_selected", "message": "Для сбора ресурса выберите работника"}, "military gets explicit resource rejection")
	var enemy_building := {"entity_type": "building", "id": 9, "team": 2}
	assert_equal(ContextResolver.resolve(military, enemy_building, ground, 1), {"type": "attack", "target_id": 9}, "enemy building resolves through the common attack command")


func test_worker_actions() -> void:
	var ground := Vector2(3.0, 4.0)
	var resource := {"entity_type": "resource", "id": 11}
	assert_equal(ContextResolver.resolve(workers, resource, ground, 1), {"type": "gather", "target_id": 11}, "resource resolves to gather")

	var foundation := {"entity_type": "foundation", "id": 12, "building_type": "granary", "pos": Vector2(9.0, 5.0)}
	var build: Dictionary = ContextResolver.resolve(workers, foundation, ground, 1)
	assert_equal(build["type"], "build", "foundation resolves to build")
	assert_equal(build["target"], Vector2(9.0, 5.0), "foundation build target")

	var damaged := {"entity_type": "building", "id": 14, "team": 1, "hp": 75.0, "max_hp": 100.0}
	assert_equal(ContextResolver.resolve(workers, damaged, ground, 1), {"type": "repair", "target_id": 14}, "damaged friendly building resolves to repair")
	var carrying_workers := [{"id": 1, "kind": "villager", "carried_amount": 4.0}]
	assert_equal(ContextResolver.resolve(carrying_workers, damaged, ground, 1), {"type": "return_resources", "target_id": 14}, "carried resources take contextual drop-off precedence")
	var healthy := {"entity_type": "building", "id": 15, "team": 1, "hp": 100.0, "max_hp": 100.0}
	assert_equal(ContextResolver.resolve(workers, healthy, ground, 1), {"type": "unsupported", "reason": "no_context_action", "message": "Для этого здания нет доступной контекстной команды"}, "healthy building reports unavailable context action")


func test_priest_conversion() -> void:
	var priests := [{"id": 3, "kind": "priest", "components": {"conversion": {"enabled": true}}, "behavior_tags": ["converter"]}]
	var enemy := {"entity_type": "unit", "id": 18, "team": 2}
	var enemy_building := {"entity_type": "building", "id": 19, "team": 2}
	assert_equal(ContextResolver.resolve(priests, enemy, Vector2.ZERO, 1), {"type": "convert", "target_id": 18}, "Priest right click resolves to conversion")
	assert_equal(ContextResolver.resolve(priests, enemy_building, Vector2.ZERO, 1), {"type": "convert", "target_id": 19}, "Priest right click on enemy building resolves to conversion")


func test_priest_healing() -> void:
	var priests := [{"id": 3, "kind": "priest", "components": {"healing": {"enabled": true}}, "behavior_tags": ["healer"]}]
	var wounded := {"entity_type": "unit", "id": 20, "team": 1, "hp": 9.0, "max_hp": 25.0}
	assert_equal(ContextResolver.resolve(priests, wounded, Vector2.ZERO, 1), {"type": "heal", "target_id": 20}, "Priest right click on wounded friendly unit resolves to healing")
	var healthy := {"entity_type": "unit", "id": 21, "team": 1, "hp": 25.0, "max_hp": 25.0}
	assert_equal(ContextResolver.resolve(priests, healthy, Vector2(4.0, 5.0), 1), {"type": "move", "target": Vector2(4.0, 5.0)}, "healthy friendly unit does not create a healing order")


func test_transport_boarding() -> void:
	var transport := {"entity_type": "unit", "id": 30, "team": 1, "components": {"cargo": {"enabled": true, "capacity": 4, "passenger_ids": []}}}
	assert_equal(ContextResolver.resolve(military, transport, Vector2.ZERO, 1), {"type": "board", "target_id": 30}, "right click on allied Transport resolves to boarding")


func test_trade_route() -> void:
	var traders := [{"id": 31, "kind": "trade_boat", "components": {"trade": {"enabled": true, "target_building_source_id": 45}}}]
	var foreign_dock := {"entity_type": "building", "id": 32, "team": 2, "unit_lineage": [45, 133]}
	assert_equal(ContextResolver.resolve(traders, foreign_dock, Vector2.ZERO, 1), {"type": "trade", "target_id": 32}, "right click on a foreign Dock resolves to trade")
	var own_dock := {"entity_type": "building", "id": 33, "team": 1, "unit_lineage": [45]}
	assert_equal(ContextResolver.resolve(traders, own_dock, Vector2.ZERO, 1).get("type"), "unsupported", "own Dock cannot become a trade target")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
