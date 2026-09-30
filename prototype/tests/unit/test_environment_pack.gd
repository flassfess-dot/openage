extends SceneTree

const World := preload("res://scripts/simulation_world.gd")
const Minimap := preload("res://scripts/minimap_terrain_raster.gd")

const Catalog := preload("res://scripts/resource_catalog.gd")
const Terrain := preload("res://scripts/environment_terrain.gd")
const Renderer := preload("res://scripts/terrain_renderer.gd")
const Elevation := preload("res://scripts/terrain_elevation.gd")
const Rules := preload("res://scripts/terrain_rules.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
const TerrainCanvas := preload("res://scripts/terrain_canvas.gd")

var errors: Array[String] = []
var catalog = Catalog.new()


func _initialize() -> void:
	if not FileAccess.file_exists("res://assets/generated/environment/aoe2_temperate/manifest.json"):
		if "--require-pack" in OS.get_cmdline_user_args():
			push_error("Required optional environment pack has not been imported")
			quit(1)
		else:
			print("Environment pack integration tests skipped: optional pack not installed")
			quit(0)
		return
	catalog.load()
	var elevation = Elevation.new(Vector2i(3, 3))
	var provider := func(_cell): return 0
	var original := Renderer.tile_drawable(Vector2i.ONE, 0, provider, catalog, elevation, 1.0, Vector2.ZERO, 41721)
	check(not catalog.environment_pack.enabled, "pack is opt-in")
	check(original.has("texture") and not original.has("mesh_layers"), "disabled pack uses original renderer")
	check(catalog.enable_environment_pack(), "complete imported pack loads and hashes match")
	if not catalog.environment_pack.enabled:
		_finish()
		return
	_test_assets()
	_test_resources_and_cache()
	_test_tree_ground()
	_test_surfaces()
	_test_transition_mesh()
	_finish()


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _test_assets() -> void:
	var pack = catalog.environment_pack
	check(pack.materials_by_id.size() == 4, "four materials")
	var count := 0
	for key in pack.objects_by_key:
		for variant in range(pack.object_variant_count(key)):
			count += 1
			var item: Dictionary = pack.scenery(key, Vector2.ONE, 1, variant)
			var info: Dictionary = catalog.environment_frame_info(item)
			check(not info.is_empty(), "object renders: %s/%d" % [key, variant])
			var record: Dictionary = pack.manifest["objects"][key]["frames"][variant]
			check(info["texture"].get_size() == Vector2(record["width"], record["height"]), "object dimensions")
			check(Vector2(record["source_hotspot"][0], record["source_hotspot"][1]).distance_to(info["hotspot"] / float(record.get("scale", 2.0 / 3.0))) <= 1.1, "hotspot remains within one source pixel")
	check(count == 129, "8 tree variants and 121 mixed decoration variants")
	for id in pack.materials_by_id:
		var image: Image = pack.material_texture(id).get_image()
		check(image.get_size() == Vector2i(320, 320), "full 10x10 pattern at target density")
		check(not image.detect_alpha(), "material atlas is fully opaque")
	for image_texture in pack.legacy_textures.values():
		check(not image_texture.get_image().detect_alpha(), "bridge atlas has no transparent cracks")
	check(pack.terrain_id("unknown") == -1 and pack.scenery("unknown", Vector2.ZERO, 0).is_empty(), "unknown keys fail explicitly")


func _test_resources_and_cache() -> void:
	var pack = catalog.environment_pack
	var resource: Dictionary = pack.decorate_resource({"id": 1, "kind": "tree", "pos": Vector2.ONE, "amount": 75, "max_amount": 75}, "pine", 4)
	var compact: Dictionary = Snapshot._compact_render_entity(resource)
	check(compact.get("source_graphic_asset_name") == "aoe2_temperate:pine", "compact snapshot retains pack binding")
	check(catalog.resource_frame_info(compact)["frame_index"] == 4, "snapshot retains chosen variant")
	resource["amount"] = 0
	var depleted := catalog.resource_frame_info(resource)
	check(depleted.get("asset_name") == "aoe2_temperate:stump" and depleted.get("frame_index") == 1, "harvested tree becomes deterministic stump")
	check(resource["max_amount"] == 75, "pack does not import AoE2 economy stats")
	var renderer := RenderWorld.new()
	var item: Dictionary = pack.scenery("oak", Vector2.ONE, 1, 0)
	var projection := func(point): return point
	var info_provider := func(kind, data): return catalog.environment_frame_info(data) if kind == "environment" else catalog.resource_frame_info(data)
	var before: Dictionary = renderer._snapshot_environment_drawables([item], projection, info_provider)
	item["asset_name"] = "aoe2_temperate:pine"
	var after: Dictionary = renderer._snapshot_environment_drawables([item], projection, info_provider)
	check(before["static"][0]["frame_info"]["texture"] != after["static"][0]["frame_info"]["texture"], "cache invalidates when family changes at same id/frame")
	resource["amount"] = 75
	var resource_before: Array = renderer._snapshot_resource_drawables([resource], projection, info_provider, [])
	resource["source_frame"] = 0
	var resource_after: Array = renderer._snapshot_resource_drawables([resource], projection, info_provider, [])
	check(resource_before[0]["frame_info"]["texture"] != resource_after[0]["frame_info"]["texture"], "resource cache invalidates when variant changes")


func _test_surfaces() -> void:
	var pack = catalog.environment_pack
	var elevation = Elevation.new(Vector2i(2, 2))
	var masks := [0, 1, 2, 3, 4, 6, 7, 8, 9, 11, 12, 13, 14, 15]
	var corners := [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.ONE, Vector2i.DOWN]
	for id in pack.materials_by_id:
		check(Rules.logical_for_terrain_id(id) == "grass", "new surface remains walkable grass")
		check(Minimap.color_for_terrain_id(id) == Color(pack.materials_by_id[id]["minimap"]), "minimap agrees with material definition")
		check(Rules.is_terrain_accessible([{"accessible_damage_multiplier": [1.0]}], 0, id), "native movement restriction maps to grass")
		check(not Rules.is_terrain_accessible([{"accessible_damage_multiplier": [0.0]}], 0, id), "native inaccessible restriction is retained")
		for mask in masks:
			elevation.clear()
			for i in range(4):
				elevation.set_vertex(corners[i], 1 if mask & (1 << i) else 0)
			var provider := func(_cell): return id
			var tile := Renderer.tile_drawable(Vector2i.ZERO, id, provider, catalog, elevation, 1.0, Vector2.ZERO, 41721)
			check(tile.has("mesh_layers") and tile["mesh_layers"].size() == 1, "material renders every valid corner configuration")
			var layer: Dictionary = tile["mesh_layers"][0]
			for point in layer["points"]:
				check(point.is_finite(), "slope geometry is finite")
			for uv in layer["uvs"]:
				check(uv.x > 0.0 and uv.x < 1.0 and uv.y > 0.0 and uv.y < 1.0, "atlas coordinates stay inside texture")
	var water := func(_cell): return 1
	check(Terrain.affects(Vector2i.ZERO, water, pack), "native water participates in the continuous coastal mesh")


func _test_transition_mesh() -> void:
	var pack = catalog.environment_pack
	var elevation = Elevation.new(Vector2i(4, 4))
	var provider := func(cell): return 1000 if cell.x < 2 else (1001 if cell.y < 2 else 1003)
	for y in range(17):
		var at := Vector2(2.0, 1.0 + y / 16.0)
		var left := Terrain.weights(at - Vector2(0.00001, 0), provider, pack, 1000)
		var right := Terrain.weights(at + Vector2(0.00001, 0), provider, pack, 1001)
		var total := 0.0
		for id in left:
			total += float(left[id])
			check(absf(float(left[id]) - float(right.get(id, 0.0))) < 0.0002, "shared edge has continuous material weights")
		check(absf(total - 1.0) < 0.00001, "blend weights form an opaque partition")
	var canvas := TerrainCanvas.new()
	root.add_child(canvas)
	canvas.configure(Vector2i(4, 4), 41721, catalog, {"terrain_elevation": elevation}, provider, func(): return Rect2i(0, 0, 4, 4))
	check(canvas.terrain_mesh != null, "actual terrain canvas builds mesh with pack")
	var arrays: Array = canvas.terrain_mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_VERTEX].size() == arrays[Mesh.ARRAY_COLOR].size(), "all old and new vertices have colors")
	check(canvas.terrain_atlas_regions.size() > 0, "new textures enter shared terrain atlas")
	canvas.set_view_state(1.0, Vector2.ZERO, Vector2(640, 480), 1)
	var mesh: ArrayMesh = canvas.terrain_mesh
	canvas.set_view_state(1.5, Vector2(30, 20), Vector2(640, 480), 1)
	check(canvas.terrain_mesh == mesh, "camera movement and zoom reuse world geometry")
	canvas.set_view_state(1.5, Vector2(30, 20), Vector2(640, 480), 2)
	check(canvas.terrain_mesh != mesh, "changed terrain revision rebuilds geometry")
	canvas.free()


func _finish() -> void:
	if errors.is_empty():
		print("Environment pack: assets, snapshots, depletion, cache, transitions, slopes and opt-in tests passed")
	else:
		for error in errors:
			push_error(error)
	quit(0 if errors.is_empty() else 1)


func _test_tree_ground() -> void:
	for material_id in catalog.environment_pack.materials_by_id:
		var world := World.new(Vector2i(8, 8))
		var cell := Vector2i(4, 4)
		world.map_terrain_ids[cell] = material_id
		var tree: Dictionary = world.add_resource("tree", Vector2(4.5, 4.5), 75)
		tree.merge(catalog.environment_pack.decorate_resource(tree, "oak", 1), true)
		check(world.terrain_id_at_cell(cell) == material_id, "live tree preserves its chosen ground material")
		check(not world.navigation_grid.is_walkable(cell), "imported tree retains normal movement obstruction")
		check(not catalog.resource_frame_info(tree).is_empty(), "live world tree uses pack presentation")
		tree["amount"] = 0
		world.unregister_forest_resource(tree)
		check(world.terrain_id_at_cell(cell) == material_id, "ground remains the same after tree depletion")
