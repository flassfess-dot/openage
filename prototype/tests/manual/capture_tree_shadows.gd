extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Renderer := preload("res://scripts/render_world.gd")
const Landscape := preload("res://scripts/random_map_landscape.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const OUTPUT := "res://qa/tree-shadows-20261019"

class Fixture extends "res://main.gd":
	var fixture_items: Array = []
	var captions: Array = []
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func current_world_drawables() -> Array: return fixture_items
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 1200), Color("78914c"))
		draw_world_objects()
		for caption in captions:
			draw_string(ThemeDB.fallback_font, caption[0], caption[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

var catalog := Catalog.new()
var rows: Array = []
var game

func _initialize() -> void:
	call_deferred("capture")

func project(at: Vector2) -> Vector2:
	return Vector2(100 + at.x * 170, 220 + at.y * 220)

func capture() -> void:
	root.size = Vector2i(1440, 1200)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	catalog.load()
	if not catalog.enable_environment_pack(): quit(1); return
	game = Fixture.new()
	game.resource_catalog = catalog
	game.render_world = Renderer.new()
	game.view_zoom = 1.25
	game.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(game)
	for phase_index in range(2):
		var index := 0
		for family in ["oak", "pine"]:
			for frame in range(catalog.environment_pack.object_variant_count(family)):
				var phase := "standing" if phase_index == 0 else "chopping"
				var at := Vector2(index, phase_index)
				rows.append({"id": rows.size()+1, "kind": "tree", "pos": at, "amount": 75, "tree_phase": phase,
					"environment_asset": family, "environment_variant": frame})
				game.captions.append([project(at)+Vector2(-65, 45), "%s %d / %s" % [family, frame, phase]])
				index += 1
	var native: Dictionary = {}
	for family in ["broadleaf", "conifer", "palm", "accents"]:
		for variant in Landscape.theme()["tree_palettes"][family].get("native", Landscape.theme()["tree_palettes"][family].get("variants", [])):
			native[int(variant["graphic_id"])] = variant
	var index := 0
	for graphic_id in native:
		var at := Vector2(index % 8, 2 + index / 8)
		rows.append({"id": rows.size()+1, "kind": "tree", "pos": at, "amount": 75, "tree_phase": "standing", "source_unit_id": native[graphic_id]["unit_id"],
			"source_graphic_id": graphic_id, "source_graphic_asset_name": "graphic_%d" % graphic_id, "source_frame": 0})
		game.captions.append([project(at)+Vector2(-65, 45), "RoR / %d" % graphic_id])
		index += 1
	var compact: Array = rows.map(func(row): return Snapshot._compact_render_entity(row))
	var provider := func(_kind, row): return catalog.resource_frame_info(row)
	var no_ids: Array[int] = []
	game.fixture_items = game.render_world.create_world_drawables({"resources": compact}, project, 1, provider, no_ids, 1, no_ids, game.view_zoom)
	var name := "before" if "--before" in OS.get_cmdline_user_args() else "after"
	await save(name + ".png")
	var with_shadows: Image = root.get_texture().get_image()
	var full_items: Array = game.fixture_items
	game.fixture_items = full_items.filter(func(item): return item["kind"] != "resource_shadow")
	await save(name + "-without-separate-shadows.png")
	var without_shadows: Image = root.get_texture().get_image()
	var report: Array = []
	for row in rows:
		var info := catalog.resource_frame_info(row)
		var changed := 0
		var anchor := Vector2i(project(row["pos"]))
		for y in range(anchor.y - 45, anchor.y + 30):
			for x in range(anchor.x - 80, anchor.x + 35):
				if with_shadows.get_pixel(x, y) != without_shadows.get_pixel(x, y): changed += 1
		var source_shadow_pixels := 0
		if row.has("source_graphic_asset_name"):
			var metadata: Array = catalog.source_resource_frame_metadata.get(row["source_graphic_asset_name"], [])
			if not metadata.is_empty(): source_shadow_pixels = int(metadata[0].get("semanticPixels", {}).get("shadow", 0))
		report.append({"family": row.get("environment_asset", row.get("source_graphic_asset_name", "")), "variant": row.get("environment_variant", 0),
			"phase": row["tree_phase"], "separate_shadow": info.has("shadow"), "visible_shadow_pixels": changed, "embedded_source_shadow_pixels": source_shadow_pixels})
	FileAccess.open(OUTPUT.path_join(name + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	if name == "after": await capture_generated_preview()
	quit()

func capture_generated_preview() -> void:
	game.hide()
	var preview = load("res://random_map_preview.tscn").instantiate()
	preview.preview_fixture = "res://qa/world-generator-20261018/continental-standard.bin"
	preview.terrain.async_rebuilds = false
	root.add_child(preview)
	var data: Dictionary = preview.generated["map_data"]
	var trees: Array = data["resources"].filter(func(row): return row.get("kind") == "tree")
	var natives: Array = trees.filter(func(row): return not row.has("environment_asset") and row.get("source_graphic_id") == 603)
	var imported: Array = trees.filter(func(row): return row.has("environment_asset"))
	var target: Dictionary = natives[0]
	var best := 0
	for candidate in natives:
		var nearby := imported.filter(func(row): return Vector2(row["position"]).distance_to(candidate["position"]) < 4.0).size()
		if nearby > best: best = nearby; target = candidate
	preview.zoom = 2.0
	preview.view_offset = Vector2(720, 700) - preview.elevation.world_to_screen(target["position"], preview.zoom, Vector2.ZERO)
	preview._refresh(false)
	for unused in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join("after-random-map.png"))
	print("Random map preview: %s seed=%d center=%s nearby_AoE2=%d" % [data["size"], data["seed"], target["position"], best])

func save(name: String) -> void:
	game.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(name))
