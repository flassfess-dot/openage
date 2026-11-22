extends SceneTree

const OUTPUT := "res://qa/map-climates"
const SEED := 41721

func _initialize() -> void:
	call_deferred("capture")


func capture() -> void:
	root.size = Vector2i(1280, 768)
	var preview = load("res://random_map_preview.tscn").instantiate()
	root.add_child(preview)
	if not preview.catalog.environment_pack.enabled:
		push_error("The rendered climate capture requires imported environment textures")
		quit(1)
		return
	var output := OUTPUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): output = arg.trim_prefix("--capture-dir=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var samples := "--regional-samples" in OS.get_cmdline_user_args()
	var climates := ["anatolia", "aegean"] if samples else ["temperate", "nile"]
	var pair: Array[Image] = []
	var geometry := {}
	for climate in climates:
		var profile := "highlands" if climate == "anatolia" else "mediterranean" if climate == "aegean" else "grasslands"
		for i in range(preview.profiles.size()):
			if preview.profiles[i]["id"] == profile: preview.profile_choice.select(i)
		for i in range(preview.climate_choice.item_count):
			if preview.climate_choice.get_item_metadata(i) == climate: preview.climate_choice.select(i)
		preview.seed_input.value = SEED
		if preview.generated.get("settings", {}).get("map_type_id") != profile or preview.generated.get("settings", {}).get("climate_id") != climate:
			preview.generate_map()
		if not preview.generated.get("valid", false):
			push_error(str(preview.generated.get("errors", [])))
			quit(1)
			return
		var data: Dictionary = preview.generated["map_data"]
		if data.get("climate_id", "temperate") != climate:
			push_error("Unexpected generated climate")
			quit(1)
			return
		var start: Vector2 = preview.generated["definition"]["players"][0]["start"]
		var focus: Vector2 = data["fords"][0]["center"] if not samples else regional_focus(data, climate)
		var landmarks := {"size": data["size"], "terrain": data["terrain_ids"], "levels": data["vertex_levels"],
			"start": start, "fords": data["fords"], "woodland": data["forest_mask"]}
		if not samples and not geometry.is_empty() and landmarks != geometry:
			push_error("The two shots do not have the same geography")
			quit(1)
			return
		geometry = landmarks
		while preview.terrain.is_scene_preparing(): await process_frame
		for child in preview.get_children():
			if child is CanvasLayer: child.hide()
		preview.zoom = 1.1
		preview.view_offset = Vector2(640, 410) - preview.elevation.world_to_screen(focus, preview.zoom, Vector2.ZERO)
		preview.markers = preview.markers.filter(func(m): return m["text"] in ["ИГРОК 1", "БРОД 1"])
		preview._refresh(false)
		for frame in range(8): await process_frame
		preview.animation_time = 0.0
		preview.object_layer.queue_redraw()
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		var name := "%s-%s-%d.png" % [profile, climate, SEED]
		if frame.save_png(output.path_join(name)) != OK:
			push_error("Could not write " + name)
			quit(1)
			return
		print("CLIMATE_CAPTURE ", name, " camera=", focus, " start=", start, " hash=", data["content_hash"])
		pair.append(frame)
	if not samples:
		var panel := Image.create(pair[0].get_width() * 2, pair[0].get_height(), false, pair[0].get_format())
		for i in range(pair.size()):
			panel.blit_rect(pair[i], Rect2i(Vector2i.ZERO, pair[i].get_size()), Vector2i(i * pair[i].get_width(), 0))
		if panel.save_png(output.path_join("temperate-nile-41721.png")) != OK:
			quit(1)
			return
	quit(0)


func regional_focus(data: Dictionary, climate: String) -> Vector2:
	# Find a snow line or a cove with both land and water inside the same shot.
	var size: Vector2i = data["size"]
	var best_score := -1.0
	var best := Vector2(size) * 0.5
	for y in range(23, size.y - 23, 2):
		for x in range(23, size.x - 23, 2):
			var first := 0
			var second := 0
			var third := 0
			for dy in range(-7, 8, 2):
				for dx in range(-7, 8, 2):
					var id: int = data["climate_surfaces"][(y + dy) * size.x + x + dx]
					if climate == "anatolia":
						if id in [1110, 1111, 1113]: first += 1
						elif id in [1003, 1104, 1112]: second += 1
					else:
						if id in [1, 4, 15, 22]: first += 1
						elif id in [1120, 1123]: second += 1
						elif id in [1121, 1122]: third += 1
			var score := float(mini(first, second)) if climate == "anatolia" else float(mini(first, mini(second, third)))
			if score > best_score:
				best_score = score
				best = Vector2(x + 0.5, y + 0.5)
	return best
