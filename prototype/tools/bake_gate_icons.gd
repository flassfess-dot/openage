extends SceneTree

# Bake native game geometry and textures, with the same 50 px close crop as
# the imported building portraits. Run with a graphical Godot runtime:
# godot --path prototype --script res://tools/bake_gate_icons.gd
const Catalog := preload("res://scripts/resource_catalog.gd")
const GateCatalog := preload("res://scripts/gate_catalog.gd")
const Presentation := preload("res://scripts/gate_presentation.gd")
const CIVILIZATIONS := [1, 2, 3, 10, 13]

class Thumbnail extends Node2D:
	var parts: Array = []
	var terrain: Array = []
	var scale_factor := 0.43
	var origin := Vector2(32, 32)

	func _draw() -> void:
		for tile in terrain:
			draw_texture_rect(tile.texture, tile.rect, false)
		for part in parts:
			if part.has("gate_polygon"):
				draw_set_transform(origin, 0, Vector2.ONE * scale_factor)
				draw_polygon(part.gate_polygon, PackedColorArray([part.get("gate_color", Color.WHITE)]), part.get("gate_uv", PackedVector2Array()), part.get("texture"))
				draw_set_transform(Vector2.ZERO)
			elif part.get("texture") != null:
				var point: Vector2 = origin + (Vector2(part.get("screen_offset", Vector2.ZERO)) - Vector2(part.get("hotspot", Vector2.ZERO))) * scale_factor
				draw_texture_rect(part.texture, Rect2(point, part.texture.get_size() * scale_factor), false)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Gate icons require the graphical renderer")
		quit(1)
		return
	var catalog := Catalog.new()
	catalog.load()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(50, 50)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	var canvas := Thumbnail.new()
	viewport.add_child(canvas)
	var directory := "res://assets/ui/gates"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for icon_id in range(GateCatalog.ICON_VARIANTS.size()):
		var group := 0 if icon_id == 0 else (icon_id - 1) / 2
		var tier := 0 if icon_id == 0 else (icon_id - 1) % 2 + 1
		var civilization: int = CIVILIZATIONS[group]
		var source_id: int = 10000 + GateCatalog.WALL_IDS[tier]
		for player in range(1, 9):
			var gate := {"kind": "gate", "pos": Vector2.ZERO, "team": player, "source_unit_id": source_id, "state": "complete", "hp": 100.0, "max_hp": 100.0, "gate_axis": 0, "gate_open_fraction": 0.0, "components": {"ownership": {"civilization_id": civilization}}}
			var info: Dictionary = catalog.building_frame_info(gate, 0)
			canvas.parts = info.composite_parts.duplicate()
			canvas.parts.sort_custom(func(a, b):
				var a_shadow: bool = a.get("presentation_layer", "") == "shadow"
				var b_shadow: bool = b.get("presentation_layer", "") == "shadow"
				if a_shadow != b_shadow: return a_shadow
				return Presentation.project(a.get("depth_world_offset", Vector2.ZERO)).y < Presentation.project(b.get("depth_world_offset", Vector2.ZERO)).y)
			var leaf: PackedVector2Array = canvas.parts.filter(func(part): return part.has("gate_leaf"))[0].gate_polygon
			var center := Vector2.ZERO
			for point in leaf: center += point
			center /= leaf.size()
			# Center the opening, retaining the close, cropped masonry at the edges.
			canvas.origin = Vector2(25, 30) - (center + Vector2(18, 9)) * canvas.scale_factor
			canvas.terrain.clear()
			for y in range(-6, 7):
				for x in range(-6, 7):
					var terrain_name := "sand" if x + y < 1 else "grass"
					var texture: Texture2D = catalog.terrain_all_textures[terrain_name][posmod(x * 3 + y * 5, 8)]
					var point := Vector2(25, 31) + Presentation.project(Vector2(x, y)) * canvas.scale_factor - Vector2(32, 16) * canvas.scale_factor
					canvas.terrain.append({"texture": texture, "rect": Rect2(point, Vector2(65, 33) * canvas.scale_factor)})
			canvas.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var image := viewport.get_texture().get_image()
			var path := "%s/%s-p%d.png" % [directory, GateCatalog.ICON_VARIANTS[icon_id], player]
			if image.save_png(path) != OK:
				push_error("Could not save " + path)
				quit(1)
				return
	print("Baked 11 gate portraits in all 8 player colors")
	quit(0)
