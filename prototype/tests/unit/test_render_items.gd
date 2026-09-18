extends SceneTree

const RenderItem := preload("res://scripts/render_item.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const EnvironmentPresentationField := preload("res://scripts/environment_presentation_field.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_required_render_item_fields()
	test_stable_layer_sorting_and_overlays()
	test_health_bars_follow_selection_visibility()
	test_retained_queue_refreshes_interpolated_anchors()
	test_presentation_marker_is_a_non_selectable_drawable()
	test_objective_is_a_non_selectable_drawable()
	test_environment_field_culls_and_renders_non_selectable_items()

	if failures.is_empty():
		print("G-001/G-002/G-003 render item tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_required_render_item_fields() -> void:
	var item := RenderItem.create("unit", RenderItem.Layer.UNIT_BUILDING, Vector2(2, 3), 48.0, 17, {}, {"frame_index": 4, "hotspot": Vector2(9, 22)}, 1.5, Color.BLUE, 0.75)
	for field in RenderItem.REQUIRED_FIELDS:
		assert_true(item.has(field), "RenderItem provides %s" % field)
	assert_equal(item["frame"], 4, "frame copied from descriptor")
	assert_equal(item["hotspot"], Vector2(9, 22), "hotspot copied from descriptor")
	assert_equal(item["opacity"], 0.75, "opacity retained")


func test_stable_layer_sorting_and_overlays() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var first: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), true)
	var second: Dictionary = world.add_unit(1, "archer", Vector2(4.0, 4.0), false)
	world.add_resource("tree", Vector2(9.0, 9.0), 75)
	var renderer = RenderWorld.new()
	var items: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position * 10.0, 1.0, Callable(self, "fake_frame_info"))

	for index in range(1, items.size()):
		assert_true(not RenderItem.less(items[index], items[index - 1]), "items are sorted at index %d" % index)
	var bodies := items.filter(func(item): return item["kind"] == "unit")
	assert_equal(bodies.size(), 2, "two unit body items")
	assert_equal(bodies[0]["stable_id"], first["id"], "stable ID resolves equal-depth order")
	assert_equal(bodies[1]["stable_id"], second["id"], "second stable ID follows")
	assert_equal(items.filter(func(item): return item["kind"] == "selection").size(), 1, "selection is a separate overlay")
	assert_equal(items.filter(func(item): return item["kind"] == "health_bar").size(), 1, "health bar is a separate overlay")
	var resource_item: Dictionary = items.filter(func(item): return item["kind"] == "resource")[0]
	assert_true(resource_item["layer"] < bodies[0]["layer"], "resource layer precedes units")


func test_health_bars_follow_selection_visibility() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var friendly: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	var enemy: Dictionary = world.add_unit(2, "clubman", Vector2(6.0, 6.0), false)
	enemy["hp"] = maxf(1.0, float(enemy["max_hp"]) - 1.0)
	enemy.get("components", {}).get("health", {})["current"] = enemy["hp"]
	var renderer = RenderWorld.new()
	var hidden_bars: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position * 10.0, 1.0, Callable(self, "fake_frame_info"), [], 1, [])
	assert_equal(hidden_bars.filter(func(item): return item["kind"] == "health_bar").size(), 0, "unselected friendly and damaged enemy do not leak persistent health bars")
	var selected_bars: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position * 10.0, 1.0, Callable(self, "fake_frame_info"), [], 1, [int(friendly["id"])])
	var health_items := selected_bars.filter(func(item): return item["kind"] == "health_bar")
	assert_equal(health_items.size(), 1, "selected unit exposes exactly one health bar")
	assert_equal(int(health_items[0]["stable_id"]), int(friendly["id"]), "health bar belongs to the selected unit")


func test_retained_queue_refreshes_interpolated_anchors() -> void:
	var world = SimulationWorld.new(Vector2i(16, 16))
	var unit: Dictionary = world.add_unit(1, "clubman", Vector2(4.0, 4.0), false)
	unit["previous_pos"] = Vector2(2.0, 2.0)
	unit["pos"] = Vector2(4.0, 4.0)
	var renderer = RenderWorld.new()
	var items: Array = renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position * 10.0, 0.0, Callable(self, "fake_frame_info"))
	var original_body: Dictionary = items.filter(func(item): return item["kind"] == "unit")[0]
	assert_equal(original_body["world_anchor"], Vector2(2.0, 2.0), "initial retained queue uses the requested interpolation alpha")
	renderer.refresh_world_drawables(items, func(position: Vector2) -> Vector2: return position * 10.0, 0.5)
	var refreshed_body: Dictionary = items.filter(func(item): return item["kind"] == "unit")[0]
	var refreshed_shadow: Dictionary = items.filter(func(item): return item["kind"] == "shadow")[0]
	assert_equal(refreshed_body["world_anchor"], Vector2(3.0, 3.0), "retained body updates its interpolated anchor without rebuilding descriptors")
	assert_equal(refreshed_shadow["world_anchor"], Vector2(3.0, 3.0), "retained overlays stay attached to the interpolated body")
	assert_equal(refreshed_body["screen_y"], 30.0, "retained queue refreshes the depth key")


func test_presentation_marker_is_a_non_selectable_drawable() -> void:
	var snapshot := {
		"buildings": [],
		"resources": [],
		"projectiles": [],
		"effects": [],
		"units": [],
		"markers": [{"id": -100001, "kind": "scenario_flag", "position": Vector2(4.0, 5.0), "graphic_id": 322, "asset_name": "graphic_322_p1"}],
	}
	var renderer = RenderWorld.new()
	var items: Array = renderer.create_world_drawables(snapshot, func(position: Vector2) -> Vector2: return position * 10.0, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(items.size(), 1, "presentation-only marker creates one render item")
	assert_equal(items[0]["kind"], "marker", "scenario flag remains presentation-only")
	assert_equal(items[0]["stable_id"], -100001, "scenario marker keeps its stable presentation id")
	assert_equal(items.filter(func(item): return item["kind"] == "selection").size(), 0, "scenario marker is not selectable")


func test_objective_is_a_non_selectable_drawable() -> void:
	var snapshot := {
		"buildings": [],
		"resources": [],
		"objectives": [{"id": 41, "kind": "ruin", "pos": Vector2(6.0, 7.0), "active": true, "graphic_id": 504, "asset_name": "graphic_504"}],
		"projectiles": [],
		"effects": [],
		"units": [],
		"markers": [],
	}
	var renderer = RenderWorld.new()
	var items: Array = renderer.create_world_drawables(snapshot, func(position: Vector2) -> Vector2: return position * 10.0, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(items.size(), 1, "active source objective creates one render item")
	assert_equal(items[0]["kind"], "objective", "source Ruin uses the objective presentation path")
	assert_equal(items[0]["stable_id"], 41, "objective keeps its stable runtime id")
	assert_equal(items.filter(func(item): return item["kind"] == "selection").size(), 0, "objective is not selectable")


func test_environment_field_culls_and_renders_non_selectable_items() -> void:
	var field = EnvironmentPresentationField.new()
	field.configure([
		{"id": -200000, "kind": "presentation_scenery", "position": Vector2(2.5, 3.5), "presentation_layer": "scenery"},
		{"id": -200001, "kind": "terrain_feature", "position": Vector2(9.5, 9.5), "presentation_layer": "decal"},
	])
	var visible: Array = field.query(Rect2i(1, 2, 4, 4))
	assert_equal(field.item_count, 2, "environment field indexes every source item once")
	assert_equal(visible.size(), 1, "environment field returns only the visible cell range")
	var snapshot := {"buildings": [], "resources": [], "objectives": [], "projectiles": [], "effects": [], "units": [], "markers": [], "environment": visible}
	var renderer = RenderWorld.new()
	var items: Array = renderer.create_world_drawables(snapshot, func(position: Vector2) -> Vector2: return position * 10.0, 1.0, Callable(self, "fake_frame_info"))
	assert_equal(items.size(), 1, "visible source scenery creates one render item")
	assert_equal(items[0]["kind"], "environment", "source scenery stays in the environment presentation layer")
	assert_equal(items.filter(func(item): return item["kind"] == "selection").size(), 0, "environment item is not selectable")


func fake_frame_info(_kind: String, _data: Variant) -> Dictionary:
	return {"frame_index": 3, "hotspot": Vector2(8, 20), "mirrored": false}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
