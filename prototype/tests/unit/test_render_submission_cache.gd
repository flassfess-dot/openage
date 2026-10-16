extends SceneTree
const Renderer := preload("res://scripts/render_world.gd")
const Item := preload("res://scripts/render_item.gd")
var failures: Array[String] = []
var offset := Vector2.ZERO
var scale := 1.0
var elevated_projection := false
var texture: Texture2D
func project(point: Vector2) -> Vector2:
	var height := float(int(point.x) % 3) * 12.0 if elevated_projection else 0.0
	return Vector2((point.x-point.y)*32, (point.x+point.y)*16 - height)*scale + offset
func info(_kind: String, data: Dictionary) -> Dictionary:
	var result := {"texture": texture, "hotspot": Vector2(7, 16), "screen_offset": Vector2(2, -3)}
	if data.get("tree_phase") == "falling": result["rotation"] = 0.5
	return result
func _initialize() -> void:
	texture = ImageTexture.create_from_image(Image.create(16, 20, false, Image.FORMAT_RGBA8))
	var renderer := Renderer.new()
	var tree := {"id": 1, "pos": Vector2(2.2, 4.7), "amount": 100, "kind": "tree"}
	tree.make_read_only()
	var view: Array = [tree]
	view.make_read_only()
	for zoom in [1.0, 2.0, 3.0]:
		scale = zoom
		offset += Vector2(18.3, -21.2)
		var items := renderer.create_world_drawables({"resources":view}, project, 1, info, [], 1, [], zoom)
		check(items[0]["sprite_command"][1] == Rect2(project(tree["pos"]).round() + Vector2(2,-3)*zoom - Vector2(7,16)*zoom, texture.get_size()*zoom), "cached source hotspot and offset follow pan/zoom")
		offset += Vector2(3, 4)
		renderer.refresh_world_drawables(items, project, 1, true)
		check(items[0]["sprite_command"][1].position == project(tree["pos"]).round() + Vector2(2,-3)*zoom - Vector2(7,16)*zoom, "between-tick camera movement refreshes cached texture rectangles")
	var falling := tree.duplicate()
	falling["tree_phase"] = "falling"
	falling.make_read_only()
	view = [falling]
	view.make_read_only()
	var rotated := renderer.create_world_drawables({"resources": view}, project, 1, info, [], 1, [], scale)
	check(not rotated[0].has("sprite_command"), "falling trees retain their rotated draw path")
	# Crops use complete sprite bounds, not the object's anchor cell.
	scale = 1
	offset = Vector2.ZERO
	var viewport := Rect2(-94, 95, 10, 10)
	var clipped := renderer.create_world_drawables({"resources":[tree]}, project, 1, info, [], 1, [], scale, viewport)
	check(not clipped.is_empty(), "a crown crossing the viewport edge remains visible even when its anchor is outside")
	offset = Vector2(1000, 1000)
	clipped = renderer.create_world_drawables({"resources":[tree]}, project, 1, info, [], 1, [], scale, viewport)
	check(clipped.is_empty(), "fully offscreen source sprites are omitted from the depth queue")
	offset = Vector2.ZERO
	clipped = renderer.create_world_drawables({"resources":[tree]}, project, 1, info, [], 1, [], scale, viewport)
	check(not clipped.is_empty(), "camera movement restores entering sprites without waiting for a simulation tick")
	var mutable_tree := tree.duplicate()
	var readonly_outer: Array = [mutable_tree]
	readonly_outer.make_read_only()
	renderer.create_world_drawables({"resources":readonly_outer}, project, 1, info, [], 1, [], scale)
	mutable_tree["tree_phase"] = "falling"
	var mutable_items := renderer.create_world_drawables({"resources":readonly_outer}, project, 1, info, [], 1, [], scale)
	check(not mutable_items[0].has("sprite_command"), "readonly outer arrays cannot hide changes to mutable resource records")
	var reference_renderer := Renderer.new()
	reference_renderer.affine_static_projection = false
	elevated_projection = true
	renderer.clear_caches()
	for step in range(75):
		scale = float(1 + (step / 25) % 3)
		offset = Vector2(133.3 + step * 7.31, -700.2 + step * 3.19)
		var fast := renderer.create_world_drawables({"resources":[tree]}, project, 1, info, [], 1, [], scale)
		var original := reference_renderer.create_world_drawables({"resources":[tree]}, project, 1, info, [], 1, [], scale)
		check(fast[0]["sprite_command"][1] == original[0]["sprite_command"][1], "affine pan and zoom keep the reference pixel rectangle")
	# Immutable camera publications can change one record without rebuilding
	# unchanged trees; removal and re-entry must not retain stale bodies.
	renderer.clear_caches()
	var second_tree := {"id": 2, "pos": Vector2(3, 4), "amount": 100, "kind": "tree"}
	second_tree.make_read_only()
	var published: Array = [tree, second_tree]
	published.make_read_only()
	renderer.create_world_drawables({"resources": published}, project, 1, info, [], 1, [], scale)
	var changed_tree := tree.duplicate()
	changed_tree["amount"] = 90
	changed_tree.make_read_only()
	var changed_view: Array = [changed_tree, second_tree]
	changed_view.make_read_only()
	var delta_items := renderer.create_world_drawables({"resources": changed_view}, project, 1, info, [], 1, [], scale)
	check(delta_items.any(func(item): return item["data"].get("amount") == 90), "incremental amount updates replace the picking/control source")
	var removed_view: Array = [second_tree]
	removed_view.make_read_only()
	delta_items = renderer.create_world_drawables({"resources": removed_view}, project, 1, info, [], 1, [], scale)
	check(delta_items.size() == 1 and delta_items[0]["stable_id"] == 2, "removed legal records cannot leave stale sprites")
	delta_items = renderer.create_world_drawables({"resources": changed_view}, project, 1, info, [], 1, [], scale)
	check(delta_items.size() == 2, "entering records are restored after removal")
	check(renderer.native_render_kernel != null and renderer.native_render_kernel.has_method("merge_render_items"), "current native merge is loaded")
	check(renderer.native_render_kernel.has_method("reproject_static_items"), "current native camera projection is loaded")
	# Mix layers, near-equal depths, wall ties and opposite insertion orders.
	var all: Array = []
	for n in range(1200):
		var data := {"kind": "wall" if n % 3 == 0 else "tree"}
		var p := Vector2(n % 19, n % 23)
		var item := Item.create("resource", n % 6, p, Vector2(0, (n % 11) * 16.0), n, data, {}, float(n % 4), Color.WHITE, 1, n % 2)
		all.append(item)
	var left: Array = []
	var right: Array = []
	for n in range(all.size()):
		if n % 2: left.append(all[n])
		else: right.append(all[n])
	left.sort_custom(Item.less)
	right.sort_custom(Item.less)
	var merged := renderer.merge_sorted_drawables(left, right)
	renderer.native_render_kernel = null
	var reference := renderer.merge_sorted_drawables(left, right)
	check(merged == reference, "native merge keeps the exact reference order, including wall depth ties")
	for failure in failures: push_error(failure)
	print("Render submission cache: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
