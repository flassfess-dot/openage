extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog := ResourceCatalog.new()
	catalog.load()

	var graphics_index: Dictionary = catalog.asset_frame_records_by_archive.get("graphics", {})
	assert_true(graphics_index.has("graphic_598_p1"), "shared frame index exposes the Roman Town Center without scanning the manifest again")
	assert_true(not catalog.audio_asset_files_by_resource_id.is_empty(), "audio resources are indexed during the single manifest pass")
	assert_equal(catalog.unit_presentations.textures.size(), 0, "unit textures remain lazy at startup")
	assert_equal(catalog.building_presentations.textures_by_key.size(), 0, "building textures remain lazy at startup")
	assert_equal(catalog.resource_presentations.frames_by_asset.size(), 0, "resource textures remain lazy at startup")
	assert_equal(catalog.projectile_presentations.frames_by_source.size(), 0, "projectile textures remain lazy at startup")
	assert_equal(catalog.effect_presentations.frames_by_key.size(), 0, "effect textures remain lazy at startup")

	assert_true(catalog.building_presentations.has_graphic(598, 1), "an unloaded building graphic remains discoverable")
	assert_equal(catalog.building_presentations.imported_frame_count(598, 1), 3, "an unloaded building reports its imported frame count")
	var building_info: Dictionary = catalog.building_frame_info({
		"id": 12,
		"kind": "barracks",
		"team": 1,
		"source_unit_id": 12,
		"display_graphic_id": 13,
		"state": "foundation",
		"construction_stage": 0,
		"hp": 350.0,
		"max_hp": 350.0,
		"components": {"ownership": {"civilization_id": 13}},
	})
	assert_equal(building_info.get("asset_name", ""), "graphic_82_p1", "first building access resolves the same source construction graphic")
	assert_true(building_info.get("texture") != null, "first building access loads its requested texture")
	assert_equal(catalog.building_presentations.textures_by_key.size(), 1, "first building access does not decode unrelated buildings")

	assert_true(catalog.resource_presentations.has_presentation("tree"), "an unloaded resource presentation remains discoverable")
	var resource_info: Dictionary = catalog.resource_presentations.frame_info({
		"id": 1,
		"kind": "tree",
		"amount": 75,
		"source_unit_id": 144,
	}, 0.0)
	assert_equal(resource_info.get("asset_name", ""), "tree", "first resource access preserves the source asset selection")
	assert_true(resource_info.get("texture") != null, "first resource access loads its requested texture")
	assert_equal(catalog.resource_presentations.frames_by_asset.size(), 1, "first resource access does not decode unrelated resources")

	if failures.is_empty():
		print("R-004 resource loading policy tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
