extends SceneTree

const MATCH_PATH := "res://tests/fixtures/e3_save_state_matrix_match.json"

var failures: Array[String] = []


func _initialize() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game = scene.instantiate()
	game.match_path = MATCH_PATH
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	var building: Dictionary = game.simulation_world.get_buildings()[0]
	var rectangle: Rect2 = game.building_selection_rectangle(building)
	assert_true(rectangle.size.x > rectangle.size.y and rectangle.size.y > 0.0, "building outline is a nonempty screen-aligned rectangle")
	var outline: PackedVector2Array = game.building_selection_outline(building)
	assert_true(outline.size() == 5 and outline[0].is_equal_approx(outline[4]), "visible outline is a closed isometric footprint")
	assert_true(not outline[0].is_equal_approx(outline[1]) and not is_equal_approx(outline[0].y, outline[1].y), "visible outline follows diamond edges, not the enclosing screen rectangle")
	var half_size := Vector2(building["footprint"]["half_size"])
	var center := Vector2(building["pos"])
	for x_sign in [-1.0, 1.0]:
		for y_sign in [-1.0, 1.0]:
			var corner: Vector2 = game.world_to_screen(center + Vector2(x_sign * half_size.x, y_sign * half_size.y))
			assert_true(rectangle.grow(1.0).has_point(corner), "building outline encloses each footprint corner")
	var drawable_items: Array = game.current_world_drawables()
	assert_true(not drawable_items.any(func(item): return String(item.get("kind", "")) == "shadow" and int(item.get("stable_id", -1)) == int(building["id"])), "building outline has no separate shadow drawable")
	var ghost := {"kind": "house", "team": 1, "pos": Vector2(20.0, 20.0), "state": "foundation", "construction_stage": 0}
	assert_true(game.resource_catalog.building_frame_info(ghost, 0.0).get("texture") != null, "placement preview resolves the source foundation sprite")
	game.free()
	if failures.is_empty():
		print("Building selection rectangle passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append(context)
