extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var registry = catalog.building_presentations

	assert_equal(registry.imported_frame_count(598, 1), 3, "Town Center base frames")
	assert_equal(registry.imported_frame_count(82, 2), 4, "team-colored common construction stages")
	test_distinct_buildings(catalog)
	test_composite_only_house(catalog)
	test_construction_graphics(catalog)
	test_foundation_preview_switching(catalog)
	test_damage_and_age_upgrade(catalog)
	test_player_colors(catalog)

	if failures.is_empty():
		print("G-008 building presentation registry tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_distinct_buildings(catalog) -> void:
	var expected := {
		"town_center": [109, 598],
		"barracks": [12, 13],
		"granary": [68, 863],
		"storage_pit": [103, 515],
		"archery_range": [87, 873],
	}
	var asset_names: Dictionary = {}
	for kind in expected:
		var ids: Array = expected[kind]
		var info: Dictionary = catalog.building_frame_info(building(kind, ids[0], ids[1]), 0.0)
		assert_true(info.get("texture") != null, "%s base texture is loaded" % kind)
		assert_equal(int(info.get("graphic_id", -1)), ids[1], "%s uses source graphic ID" % kind)
		if int(catalog.graphics_catalog_data.get("graphics", {}).get(str(ids[1]), {}).get("angle_count", 1)) > 1:
			assert_equal(int(info.get("source_direction", -1)), 0, "%s keeps the Stone Age facet until source technology selects another one" % kind)
		asset_names[String(info.get("asset_name", ""))] = true
	assert_equal(asset_names.size(), expected.size(), "building kinds do not collapse to the Town Center texture")
	var tool_center := building("town_center", 109, 598)
	tool_center["presentation_facing"] = 2
	assert_equal(int(catalog.building_frame_info(tool_center).get("source_direction", -1)), 2, "technology-selected Town Center facet overrides the Stone Age default")


func test_composite_only_house(catalog) -> void:
	var info: Dictionary = catalog.building_frame_info(building("house", 70, 817), 0.35)
	assert_equal(info.get("texture"), null, "house root has no fake base texture")
	var graphic_ids: Array = info.get("composite_parts", []).map(func(part): return int(part.get("graphic_id", -1)))
	assert_equal(graphic_ids, [407, 411, 412, 324], "house is composed from its four declared delta layers")


func test_construction_graphics(catalog) -> void:
	var barracks := building("barracks", 12, 13)
	barracks["state"] = "foundation"
	barracks["construction_stage"] = 2
	var common: Dictionary = catalog.building_frame_info(barracks)
	assert_equal(common.get("asset_name"), "graphic_82_p1", "Barracks uses common construction graphic")
	assert_equal(int(common.get("frame_index", -1)), 2, "foundation progress selects exact common stage")

	var house := building("house", 70, 817)
	house["state"] = "foundation"
	house["construction_stage"] = 3
	var house_info: Dictionary = catalog.building_frame_info(house)
	assert_equal(house_info.get("asset_name"), "graphic_86_p1", "House uses its own construction graphic")
	assert_equal(int(house_info.get("frame_index", -1)), 3, "House completion selects final stage")


func test_foundation_preview_switching(catalog) -> void:
	# Main's placement ghost has neither an entity ID nor a source_unit_id.
	# Select Dock first, then change kinds with the same catalog/cache alive.
	catalog.building_presentations.source_records_by_key.clear()
	var kinds := ["dock", "house", "barracks", "wall", "dock"]
	var graphics := [85, 86, 82, 77, 85]
	for index in range(kinds.size()):
		var ghost := {"kind": kinds[index], "team": 1, "pos": Vector2(20, 20), "state": "foundation", "construction_stage": 0}
		var info: Dictionary = catalog.building_frame_info(ghost, 0.0)
		assert_equal(info.get("graphic_id"), graphics[index], "%s preview after Dock uses its construction graphic" % kinds[index])
		assert_equal(info.get("asset_name"), "graphic_%d_p1" % graphics[index], "%s preview uses the matching source texture" % kinds[index])
		assert_equal(info.get("frame_index"), 0, "%s preview stays at the initial construction stage" % kinds[index])
		assert_true(info.get("texture") != null, "%s preview texture loads" % kinds[index])
	var other_team := {"kind": "house", "team": 2, "state": "foundation", "construction_stage": 0}
	assert_equal(catalog.building_frame_info(other_team).get("asset_name"), "graphic_86_p2", "preview switching retains player colours")


func test_damage_and_age_upgrade(catalog) -> void:
	var damaged := building("town_center", 109, 598)
	damaged["hp"] = 240.0
	var damaged_info: Dictionary = catalog.building_frame_info(damaged, 0.35)
	var damage_parts: Array = damaged_info.get("composite_parts", []).filter(func(part): return int(part.get("graphic_id", -1)) in [131, 132, 133])
	assert_equal(damage_parts.size(), 1, "only one mutually exclusive damage layer is rendered")
	if not damage_parts.is_empty():
		assert_equal(int(damage_parts[0].get("graphic_id", -1)), 132, "60 percent damage selects the 50-percent source layer")

	var upgraded := building("town_center", 71, 885)
	var upgraded_info: Dictionary = catalog.building_frame_info(upgraded)
	assert_equal(int(upgraded_info.get("graphic_id", -1)), 885, "age upgrade uses entity display graphic")
	assert_true(upgraded_info.get("texture") != null, "Tool Age Town Center graphic is loaded")


func test_player_colors(catalog) -> void:
	var player_one: Dictionary = catalog.building_frame_info(building("barracks", 12, 13, 1))
	var player_two: Dictionary = catalog.building_frame_info(building("barracks", 12, 13, 2))
	assert_equal(player_one.get("asset_name"), "graphic_13_p1", "player one palette asset")
	assert_equal(player_two.get("asset_name"), "graphic_13_p2", "player two palette asset")


func building(kind: String, source_unit_id: int, graphic_id: int, team: int = 1) -> Dictionary:
	return {
		"id": source_unit_id,
		"kind": kind,
		"team": team,
		"source_unit_id": source_unit_id,
		"display_graphic_id": graphic_id,
		"state": "complete",
		"construction_stage": 3,
		"hp": 600.0,
		"max_hp": 600.0,
		"components": {"ownership": {"civilization_id": 13}},
	}


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
