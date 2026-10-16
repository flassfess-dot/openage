extends SceneTree

const Renderer := preload("res://scripts/render_world.gd")

var failures: Array[String] = []
var texture: Texture2D
var offset := Vector2(400, 100)
var zoom := 1.0

func project(point: Vector2) -> Vector2:
	return Vector2((point.x - point.y) * 32, (point.x + point.y) * 16) * zoom + offset

func frame_info(_kind: String, _entity: Dictionary) -> Dictionary:
	return {"texture": texture, "hotspot": Vector2(8, 20)}

func _initialize() -> void:
	texture = ImageTexture.create_from_image(Image.create(16, 24, false, Image.FORMAT_RGBA8))
	for native in [true, false]:
		var renderer := Renderer.new()
		if not native: renderer.native_render_kernel = null
		var building := {"id": 1, "kind": "house", "entity_type": "building", "pos": Vector2(3, 3), "hp": 100, "team": 1}
		var scene := {"resources": [], "buildings": [building]}
		for selected in [false, true]:
			var ids: Array[int] = [1]
			var selected_ids: Array[int] = []
			var preview_ids: Array[int] = []
			if selected: selected_ids.assign(ids)
			else: preview_ids.assign(ids)
			for phase in range(4):
				offset += Vector2(7, -3)
				zoom = 1.0 + phase * 0.25
				var items := renderer.create_world_drawables(scene, project, 1, frame_info, preview_ids, 1, selected_ids, zoom)
				check_controls(items, "building cache native=%s selected=%s phase=%d" % [native, selected, phase])
				if native:
					items = renderer.refresh_camera_drawables(project, 1, zoom, Rect2(0, 0, 1280, 720))
					check_controls(items, "camera reuse")
		# Animated resources refresh their descriptors every publication. Their
		# selection records carry those descriptors too, but must remain outlines.
		var carcass := {"id": 2, "kind": "gazelle", "entity_type": "resource", "pos": Vector2(4, 4), "amount": 100, "behavior_tags": ["carcass"], "death_phase": "carcass"}
		var resource_ids: Array[int] = [2]
		for tick in range(3):
			var items := renderer.create_world_drawables({"resources": [carcass], "tick": tick}, project, 1, frame_info, resource_ids, 1, [], zoom)
			check_controls(items, "animated resource refresh tick=%d" % tick)
	for failure in failures: push_error(failure)
	print("Render control feedback: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check_controls(items: Array, label: String) -> void:
	var selections := items.filter(func(item): return item["kind"] == "selection")
	check(not selections.is_empty(), label + ": selection reaches render queue")
	for item in selections:
		check(not item.has("sprite_command"), label + ": selection cannot bypass its outline/blink renderer")
	check(items.any(func(item): return item["kind"] in ["building", "resource"] and item.has("sprite_command")), label + ": body retains optimized sprite submission")

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
