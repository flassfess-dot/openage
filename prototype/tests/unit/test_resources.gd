extends SceneTree

const RenderWorld := preload("res://scripts/render_world.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	test_original_resource_contract()
	test_source_forest_presentation()
	test_source_forest_variants_and_fallback()
	test_corrupt_source_forest_frames_are_rejected()
	test_footprints_and_overlap_resolution()
	test_depletion_and_navigation_release()

	if failures.is_empty():
		print("T-005 forest and resource tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func test_original_resource_contract() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var objects: Dictionary = catalog.object_catalog_data.get("objects", {})
	var tree: Dictionary = objects.get("0:144", {})
	var berries: Dictionary = objects.get("0:59", {})
	var stump: Dictionary = objects.get("0:130", {})
	assert_equal(tree.get("resources", {}).get("storage", [])[0].get("amount"), 75.0, "tree contains original 75 wood")
	assert_equal(tree.get("links", {}).get("dead_unit_id"), 130, "tree becomes original dead-unit 130")
	assert_equal(stump.get("graphics", {}).get("idle"), 600, "dead tree resolves to stump graphic")
	assert_equal(berries.get("resources", {}).get("storage", [])[0].get("amount"), 150.0, "berry bush contains original 150 food")


func test_source_forest_presentation() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var source_tree := {
		"id": 7001,
		"kind": "tree",
		"amount": 40,
		"source_frame": -1,
		"source_graphic_id": 650,
		"source_graphic_asset_name": "graphic_650",
		"source_depleted_graphic_id": 634,
		"source_depleted_asset_name": "graphic_634",
	}
	var live_frame: Dictionary = catalog.resource_frame_info(source_tree)
	assert_equal(live_frame.get("asset_name"), "graphic_650", "static forest node uses its exact source tree graphic")
	assert_true(live_frame.get("texture") != null, "source tree texture is loadable")
	source_tree["amount"] = 0
	var depleted_frame: Dictionary = catalog.resource_frame_info(source_tree)
	assert_equal(depleted_frame.get("asset_name"), "graphic_634", "depleted forest node uses its source death/stump sequence")
	assert_equal(depleted_frame.get("frame_index"), 4, "depleted forest node settles on the final source stump frame")


func test_source_forest_variants_and_fallback() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var first_variant := {"id": 7101, "kind": "tree", "source_unit_id": 391, "amount": 75}
	var second_variant := {"id": 7102, "kind": "tree", "source_unit_id": 392, "amount": 75}
	var unavailable_source := {"id": 7103, "kind": "tree", "source_unit_id": 393, "amount": 75}
	assert_equal(catalog.resource_frame_info(first_variant).get("asset_name"), "graphic_928", "first Punic tree variant resolves its source asset")
	assert_equal(catalog.resource_frame_info(second_variant).get("asset_name"), "graphic_929", "second Punic tree variant resolves its source asset")
	assert_equal(catalog.resource_frame_info(unavailable_source).get("asset_name"), "tree", "missing source SLP uses the declared semantic tree fallback")


func test_corrupt_source_forest_frames_are_rejected() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var source_tree := {
		"id": 7001,
		"kind": "tree",
		"amount": 75,
		"source_unit_id": 140,
		"source_graphic_id": 607,
		"source_graphic_asset_name": "graphic_607",
	}
	var frame: Dictionary = catalog.resource_frame_info(source_tree)
	var texture: Texture2D = frame.get("texture")
	assert_equal(frame.get("asset_name"), "graphic_607", "oak variant keeps its exact source asset")
	assert_equal(frame.get("frame_index"), 0, "oak variant ignores corrupt trailing source frames")
	assert_true(texture != null and texture.get_width() < 256 and texture.get_height() < 256, "oak variant never exposes a full-screen framebuffer artifact")


func test_footprints_and_overlap_resolution() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_object_catalog(catalog.object_catalog_data)
	var first: Dictionary = world.add_resource("tree", Vector2(8, 8), 75)
	var second: Dictionary = world.add_resource("tree", Vector2(8, 8), 75)
	assert_approx(float(first["footprint_radius"]), 0.2, "tree uses original movement radius")
	var minimum_distance := float(first["footprint_radius"]) + float(second["footprint_radius"]) + 0.02
	assert_true(first["pos"].distance_to(second["pos"]) >= minimum_distance, "coincident resources are separated deterministically")
	assert_equal(first.get("footprint", {}).get("occupied_cells", []).size(), 1, "resource exposes occupied cells")


func test_depletion_and_navigation_release() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load_generated_data()
	var world = SimulationWorld.new(Vector2i(16, 16))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var tree: Dictionary = world.add_resource("tree", Vector2(8, 8), 5)
	var berries: Dictionary = world.add_resource("berries", Vector2(10, 8), 1)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(7.5, 8.5), false)
	world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, 1), false)
	var tree_cell := Vector2i(floori(tree["pos"].x), floori(tree["pos"].y))
	var berry_cell := Vector2i(floori(berries["pos"].x), floori(berries["pos"].y))
	assert_true(not world.navigation_grid.is_walkable(tree_cell), "live tree blocks navigation")
	assert_true(world.find_resource(int(tree["id"])) == tree, "resource id index resolves the original static node dictionary")
	for unused in range(4):
		world.gather(int(tree["id"]), worker)
	assert_equal(tree["amount"], 1, "first gather leaves exact remainder")
	assert_equal(tree["depletion_stage"], 1, "resource enters low stage")
	world.gather(int(tree["id"]), worker)
	assert_equal(tree["amount"], 0, "second gather consumes only remaining amount")
	assert_equal(tree["state"], "depleted", "tree enters depleted state")
	assert_true(world.navigation_grid.is_walkable(tree_cell), "depleted tree releases navigation immediately")
	assert_equal(roundi(worker["carried_amount"]), 5, "harvest fills worker inventory instead of global stockpile")
	world.deposit_carried_resources(worker)
	assert_equal(world.get_wood(), 125, "wood reaches stockpile only at deposit")
	world.worker_role_system.apply(worker, world.worker_role_system.profile_for_resource_type(worker, 0), false)
	world.gather(int(berries["id"]), worker)
	assert_equal(world.get_food(), 180, "carried berry is not credited before deposit")
	world.deposit_carried_resources(worker)
	assert_equal(world.get_food(), 181, "last berry deposits its actual remainder")
	assert_true(world.navigation_grid.is_walkable(berry_cell), "depleted berries release navigation")
	var renderer = RenderWorld.new()
	var items := renderer.create_world_drawables(world, func(position: Vector2) -> Vector2: return position, 1.0, func(_kind: String, _data: Variant) -> Dictionary: return {})
	var resource_ids: Array = items.filter(func(item): return item["kind"] == "resource").map(func(item): return item["stable_id"])
	assert_true(resource_ids.has(tree["id"]), "depleted tree leaves a stump drawable")
	assert_true(not resource_ids.has(berries["id"]), "depleted berry bush disappears")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func assert_approx(actual: float, expected: float, context: String) -> void:
	if not is_equal_approx(actual, expected):
		failures.append("%s: expected %.4f, got %.4f" % [context, expected, actual])
