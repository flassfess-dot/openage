extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440, 960)
	var preview = load("res://random_map_preview.tscn").instantiate()
	root.add_child(preview)
	var directory := "res://qa/natural-landscape-20261016"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for fixture in [["grasslands", 41721, "standard"], ["grasslands", 7919, "standard"],
		["highlands", 41721, "standard"], ["islands", 41721, "standard"],
		["small_islands", 7919, "standard"], ["coastal", 104729, "standard"],
		["mediterranean", 41721, "standard"], ["continental", 7919, "standard"],
		["grasslands", 41721, "huge"]]:
		for i in range(preview.profiles.size()):
			if preview.profiles[i]["id"] == fixture[0]: preview.profile_choice.select(i)
		for i in range(preview.Settings.catalog()["map_sizes"].size()):
			if preview.Settings.catalog()["map_sizes"][i]["id"] == fixture[2]: preview.size_choice.select(i)
		preview.seed_input.value = fixture[1]
		preview.generate_map()
		if not preview.generated.get("valid", false):
			push_error("Capture invalid: %s %s" % [fixture, preview.generated.get("errors", [])])
			quit(1)
			return
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var label := "%s-%s-%d" % [fixture[0], fixture[2], fixture[1]]
		root.get_texture().get_image().save_png(directory.path_join(label + "-overview.png"))
		var forests: Array = preview.generated["map_data"]["resources"].filter(func(item): return item.get("ecology_role", "") == "forest_core")
		if not forests.is_empty():
			var position: Vector2 = forests[forests.size() / 2]["position"]
			preview.zoom = 1.2
			preview.view_offset = Vector2(720, 490) - preview.elevation.world_to_screen(position, preview.zoom, Vector2.ZERO)
			preview._refresh(false)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join(label + "-detail.png"))
		print("Captured natural landscape: " + label)
	quit(0)
