extends SceneTree

const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	verify_worker_presentations(catalog)
	verify_presentation(catalog)
	verify_gather_and_deposit(catalog, "stone_mine", 2, 102, "stone_mine")
	verify_gather_and_deposit(catalog, "gold_mine", 3, 66, "gold_mine")
	if failures.is_empty():
		print("I12-002 mineral resource integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_worker_presentations(catalog) -> void:
	assert_equal(catalog.worker_resource_animation_state(2, false), "miner_work", "stone selects mining work profile")
	assert_equal(catalog.worker_resource_animation_state(3, false), "miner_work", "gold selects mining work profile")
	assert_equal(catalog.worker_resource_animation_state(2, true), "stone_miner_carry", "stone selects stone carry profile")
	assert_equal(catalog.worker_resource_animation_state(3, true), "gold_miner_carry", "gold selects gold carry profile")
	assert_equal(catalog.unit_animation_frames("villager", "miner_work").size(), 65, "original mining work frames are loaded")
	assert_equal(catalog.unit_animation_frames("villager", "stone_miner_carry").size(), 75, "original stone carry frames are loaded")
	assert_equal(catalog.unit_animation_frames("villager", "gold_miner_carry").size(), 75, "original gold carry frames are loaded")
	assert_true(is_equal_approx(catalog.get_graphic_descriptor("villager", "miner_work").frame_duration, 0.12), "mining timing comes from original graphic 474")


func verify_presentation(catalog) -> void:
	assert_equal(catalog.resource_presentations.frames_by_asset.size(), 14, "resource registry loads every declared resource-owned asset including predator carcasses and source forest variants")
	assert_true(catalog.resource_presentations.frames_by_asset.has("graphic_928") and catalog.resource_presentations.frames_by_asset.has("graphic_929"), "First Punic forest variants participate in the shared resource registry")
	var world = configured_world(catalog)
	var tree: Dictionary = world.add_resource("tree", Vector2(5.0, 5.0), 1)
	var tree_frame: Dictionary = catalog.resource_frame_info(tree)
	assert_equal(tree_frame.get("asset_name"), "tree", "live tree uses declared runtime asset")
	tree["amount"] = 0
	var stump_frame: Dictionary = catalog.resource_frame_info(tree)
	assert_equal(stump_frame.get("asset_name"), "tree_stump", "depleted tree uses declared runtime asset")
	for spec in [
		{"kind": "stone_mine", "asset": "stone_mine"},
		{"kind": "gold_mine", "asset": "gold_mine"},
	]:
		var resource: Dictionary = world.add_resource(String(spec["kind"]), Vector2(8.0 + world.get_resources().size(), 8.0), 20)
		var first: Dictionary = catalog.resource_frame_info(resource)
		var second: Dictionary = catalog.resource_frame_info(resource)
		assert_equal(first.get("asset_name"), spec["asset"], "%s uses its original SLP asset" % spec["kind"])
		assert_true(first.get("texture") != null, "%s texture is loadable" % spec["kind"])
		assert_equal(first.get("frame_index"), second.get("frame_index"), "%s visual variant is deterministic" % spec["kind"])


func verify_gather_and_deposit(catalog, kind: String, resource_type_id: int, source_unit_id: int, expected_asset: String) -> void:
	var world = configured_world(catalog)
	world.add_building(900, "storage_pit", Vector2(12.0, 12.0), 1)
	var resource: Dictionary = world.add_resource(kind, Vector2(8.0, 9.0), 12)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7.2, 9.0), false)
	var before: int = world.get_resource_amount(1, resource_type_id)
	assert_equal(resource.get("source_unit_id"), source_unit_id, "%s keeps original source identity" % kind)
	assert_equal(resource.get("resource_type_id"), resource_type_id, "%s maps to authoritative stockpile type" % kind)
	assert_equal(catalog.resource_frame_info(resource).get("asset_name"), expected_asset, "%s registry is used by simulation entity" % kind)
	world.assign_command_gather([worker], int(resource["id"]))
	for unused in range(2600):
		world.update_units(0.05, 1, 2)
		world.rebuild_spatial_index()
		if int(resource.get("amount", 0)) == 0 and String(worker.get("task", "")) == "idle":
			break
	assert_equal(resource.get("amount"), 0, "%s is exhausted through normal gather loop" % kind)
	assert_equal(world.get_resource_amount(1, resource_type_id), before + 12, "%s reaches stockpile through Storage Pit" % kind)
	assert_true(catalog.resource_frame_info(resource).is_empty(), "%s disappears after depletion" % kind)


func configured_world(catalog):
	var world = SimulationWorld.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_graphics_catalog(catalog.graphics_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	return world


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
