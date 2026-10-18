extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Renderer := preload("res://scripts/render_world.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Item := preload("res://scripts/render_item.gd")
const Picking := preload("res://scripts/picking_service.gd")
const World := preload("res://scripts/simulation_world.gd")
var failures: Array[String] = []
var variants := 0

func _initialize() -> void:
	var catalog := Catalog.new()
	catalog.load()
	check(catalog.enable_environment_pack(), "real environment assets load")
	for family in ["oak", "pine"]:
		for frame in range(catalog.environment_pack.object_variant_count(family)):
			verify(catalog, {"id": variants+1, "kind": "tree", "pos": Vector2(6.5, 6.5), "amount": 75,
				"environment_asset": family, "environment_variant": frame}, true)
	var native: Dictionary = {}
	for family in ["broadleaf", "conifer", "palm", "accents"]:
		var spec: Dictionary = Landscape.theme()["tree_palettes"][family]
		for row in spec.get("native", spec.get("variants", [])): native[int(row["graphic_id"])] = row
	var separate := 0
	for graphic_id in native:
		var graphic: Dictionary = catalog.graphics_catalog_data["graphics"][str(graphic_id)]
		var expected: bool = graphic["deltas"].any(func(delta): return int(catalog.graphics_catalog_data["graphics"].get(str(int(delta["graphic_id"])), {}).get("layer", -1)) == 0)
		separate += int(expected)
		verify(catalog, {"id": variants+1, "kind": "tree", "pos": Vector2(6.5, 6.5), "amount": 75,
			"source_unit_id": native[graphic_id]["unit_id"], "source_graphic_id": graphic_id, "source_graphic_asset_name": "graphic_%d" % graphic_id,
			"source_depleted_asset_name": "tree_stump", "source_depleted_graphic_id": 600, "source_frame": 0}, expected)
	check(separate == 9, "all nine native DAT tree-shadow dependencies are exercised")
	check(variants == 26, "all eight imported variants and eighteen native tree graphics are exercised")
	var world := World.new(Vector2i(24, 24))
	world.set_gamespec(catalog.gamespec_data)
	world.set_object_catalog(catalog.object_catalog_data)
	world.set_runtime_catalog(catalog.runtime_catalog_data)
	var worker: Dictionary = world.add_unit(1, "villager", Vector2(5.5,5.5), false)
	var ordinary: Dictionary = world.add_resource("tree", Vector2(10.5,10.5), 75)
	check(catalog.resource_frame_info(Snapshot._compact_render_entity(ordinary)).has("shadow"), "default and legacy tree aliases resolve their original DAT shadow")
	for imported in [false, true]:
		var tree: Dictionary = world.add_resource("tree", Vector2(6.5, 5.5), 75)
		if imported:
			tree["environment_asset"] = "oak"
			tree["environment_variant"] = 0
		else:
			tree["source_graphic_id"] = 603
			tree["source_graphic_asset_name"] = "graphic_603"
		world.gathering_system.chop_tree(tree, worker)
		check(tree["tree_phase"] == "chopping" and float(tree["hp"]) > 0, "real lumberjack strike leaves a standing canopy")
		check(catalog.resource_frame_info(Snapshot._compact_render_entity(tree)).has("shadow"), "real lumberjack strike preserves imported and native canopy shadows")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Tree shadow pipeline: %d variants, %d native delta shadows, %d failures" % [variants, separate, failures.size()])
	quit(0 if failures.is_empty() else 1)

func verify(catalog, source: Dictionary, expected: bool) -> void:
	variants += 1
	var renderer := Renderer.new()
	var no_ids: Array[int] = []
	var provider := func(_kind, row): return catalog.resource_frame_info(row)
	for phase in ["", "standing", "chopping", "falling", "felled", "stump"]:
		var tree := source.duplicate(true)
		tree["tree_phase"] = phase
		if phase == "stump": tree["amount"] = 0; tree["visible_when_depleted"] = true
		var compact := Snapshot._compact_render_entity(tree)
		var info: Dictionary = catalog.resource_frame_info(compact)
		var visible: bool = expected and phase in ["", "standing", "chopping"]
		var label := "%s/%d/%s" % [source.get("environment_asset", source.get("source_graphic_asset_name", "")), source.get("environment_variant", 0), phase]
		check(info.has("shadow") == visible, label + ": descriptor retains a shadow for the entire upright life")
		for zoom in [1.0, 1.5, 2.0]:
			var project := func(at): return Vector2((at.x-at.y)*32, (at.x+at.y)*16)*zoom + Vector2(400, 50)
			for repeat in range(2):
				var items := renderer.create_world_drawables({"resources": [compact]}, project, 1, provider, no_ids, 1, no_ids, zoom, Rect2(0,0,1200,1200))
				var shadows: Array = items.filter(func(item): return item["kind"] == "resource_shadow")
				check(shadows.size() == int(visible), label + ": real render/cache emits exactly the required shadow")
				if shadows.is_empty(): continue
				var shadow: Dictionary = shadows[0]
				check(shadow["layer"] == Item.Layer.SHADOW and shadow.has("sprite_command"), label + ": shadow reaches sprite submission below actors")
				check(shadow["world_anchor"] == source["pos"] and shadow["screen_position"] == project.call(source["pos"]), label + ": shadow stays attached during zoom")
				check(not Picking.SELECTABLE_DRAWABLES.has("resource_shadow"), "tree shadows cannot enlarge picking bounds")
		if visible:
			var texture: Texture2D = info["shadow"]["texture"]
			var image := texture.get_image()
			var partial_alpha := false
			var bytes := image.get_data()
			for index in range(3, bytes.size(), 4):
				if bytes[index] > 0 and bytes[index] < 255: partial_alpha = true; break
			check(partial_alpha, label + ": source shadow is nonempty and translucent")

func check(value: bool, context: String) -> void:
	if not value and context not in failures: failures.append(context)
