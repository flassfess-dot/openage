extends SceneTree

const CompositeGraphic := preload("res://scripts/composite_graphic.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_real_town_center_delta()
	test_build_and_damage_stages()

	if failures.is_empty():
		print("G-006 composite graphic tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_real_town_center_delta() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var town_center: Dictionary = catalog.gamespec_data["units"]["town_center"]["animations"]["idle"]
	var parts: Array = catalog.get_composite_parts(int(town_center["graphic_id"]), 0, 0.0)
	assert_equal(parts.size(), 1, "town center has one available delta")
	if not parts.is_empty():
		assert_equal(parts[0]["graphic_id"], 599, "town center accent graphic ID")
		assert_equal(parts[0]["asset_name"], "graphic_599", "town center accent asset")
		assert_true(parts[0]["texture"] != null, "town center accent texture loaded")
		assert_true(parts[0]["hotspot"] is Vector2, "delta has independent hotspot")


func test_build_and_damage_stages() -> void:
	assert_equal(CompositeGraphic.construction_stage(0.0, 4), 0, "empty construction stage")
	assert_equal(CompositeGraphic.construction_stage(0.5, 4), 2, "half construction stage")
	assert_equal(CompositeGraphic.construction_stage(1.0, 4), 3, "complete construction stage")
	assert_equal(CompositeGraphic.damage_state(0.8), "intact", "intact state")
	assert_equal(CompositeGraphic.damage_state(0.4), "damaged", "damaged state")
	assert_equal(CompositeGraphic.damage_state(0.2), "critical", "critical state")
	assert_equal(CompositeGraphic.effect_kinds(0.2), ["smoke", "fire"], "critical effect composition")
	assert_equal(CompositeGraphic.delta_visible(-1, 7, 3), true, "all-angle delta")
	assert_equal(CompositeGraphic.delta_visible(1, 4, 3), true, "matching angle delta")
	assert_equal(CompositeGraphic.delta_visible(2, 4, 3), false, "non-matching angle delta")


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)
