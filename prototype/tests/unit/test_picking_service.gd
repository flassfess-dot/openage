extends SceneTree

const PickingService := preload("res://scripts/picking_service.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_stack_uses_render_order_and_deduplicates_composites()
	test_transparent_sprite_falls_back_to_footprint()
	test_zero_health_berry_is_pickable()
	test_box_prioritizes_mobile_units()

	if failures.is_empty():
		print("I3-001 picking service tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_stack_uses_render_order_and_deduplicates_composites() -> void:
	var service := PickingService.new()
	var texture := solid_texture(Color.WHITE)
	var resource := entity(1, 0, "berries", Vector2(20, 20))
	var unit := entity(2, 2, "clubman", Vector2(20, 20))
	var building := entity(3, 1, "town_center", Vector2(20, 20))
	building["state"] = "foundation"
	var drawables := [
		drawable("resource", resource, texture, 1),
		drawable("building", building, texture, 2),
		drawable("building_part", building, texture, 3),
		drawable("unit", unit, texture, 4),
	]
	var hits: Array = service.hit_stack(Vector2(20, 20), drawables, Callable(self, "identity_projection"), 1.0)
	assert_equal(hits.size(), 3, "composite building is one logical hit")
	assert_equal(hits[0].get("id"), 2, "topmost rendered unit wins")
	assert_equal(hits[1].get("entity_type"), "foundation", "building state maps to foundation context")
	assert_equal(hits[2].get("entity_type"), "resource", "lower resource remains in hit stack")
	assert_equal(service.context_entity(hits[1]).get("entity_type"), "foundation", "context copy preserves logical type")


func test_transparent_sprite_falls_back_to_footprint() -> void:
	var service := PickingService.new()
	var unit := entity(7, 1, "villager", Vector2(50, 50))
	unit["selection_radius"] = Vector2(0.4, 0.4)
	var hits: Array = service.hit_stack(
		Vector2(50, 55),
		[drawable("unit", unit, solid_texture(Color(1, 1, 1, 0)), 1)],
		Callable(self, "identity_projection"),
		1.0
	)
	assert_equal(hits.size(), 1, "selection footprint keeps transparent frame clickable")
	assert_equal(hits[0].get("hit_method"), "footprint", "fallback method is observable")


func test_zero_health_berry_is_pickable() -> void:
	var service := PickingService.new()
	var berry := entity(8, 0, "berries", Vector2(20, 20))
	berry["hp"] = 0.0 # The RoR source object (unit 59) declares zero HP.
	berry["amount"] = 150
	var hits := service.hit_stack(Vector2(20, 20), [drawable("resource", berry, solid_texture(Color.WHITE), 1)], Callable(self, "identity_projection"), 1.0)
	assert_equal(hits.size(), 1, "zero-HP berry bush remains available for mouse commands")
	berry["amount"] = 0
	hits = service.hit_stack(Vector2(20, 20), [drawable("resource", berry, solid_texture(Color.WHITE), 1)], Callable(self, "identity_projection"), 1.0)
	assert_equal(hits.size(), 1, "a resource intentionally still rendered after depletion remains inspectable")


func test_box_prioritizes_mobile_units() -> void:
	var service := PickingService.new()
	var unit := entity(10, 1, "villager", Vector2(12, 12))
	var building := entity(11, 1, "town_center", Vector2(14, 14))
	var drawables := [drawable("building", building, null, 1), drawable("unit", unit, null, 2)]
	var hits: Array = service.box_hits(Rect2(Vector2(0, 0), Vector2(30, 30)), drawables, Callable(self, "identity_projection"), 1)
	assert_equal(hits.size(), 1, "mobile entities have box priority")
	assert_equal(hits[0].get("id"), 10, "unit selected instead of building")


func entity(id: int, team: int, kind: String, position: Vector2) -> Dictionary:
	return {
		"id": id,
		"team": team,
		"kind": kind,
		"pos": position,
		"hp": 10.0,
		"selection_radius": Vector2(0.3, 0.3),
		"footprint": {"selection_radius": Vector2(0.3, 0.3)},
	}


func drawable(kind: String, value: Dictionary, texture: Texture2D, order: int) -> Dictionary:
	return {
		"kind": kind,
		"stable_id": int(value["id"]),
		"world_anchor": value["pos"],
		"hotspot": Vector2(2, 2),
		"data": value,
		"frame_info": {"texture": texture, "hotspot": Vector2(2, 2), "mirrored": false},
		"draw_order": order,
	}


func solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func identity_projection(value: Vector2) -> Vector2:
	return value


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
