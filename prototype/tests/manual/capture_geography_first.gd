extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440, 960)
	var preview = load("res://random_map_preview.tscn").instantiate()
	root.add_child(preview)
	preview.geography_first = true
	var directory := "res://qa/geography-first-20261018"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for fixture in [["islands", 41721], ["coastal", 104729], ["highlands", 41721]]:
		for i in range(preview.profiles.size()):
			if preview.profiles[i]["id"] == fixture[0]: preview.profile_choice.select(i)
		preview.seed_input.value = fixture[1]
		preview.generate_map()
		if not preview.generated.get("valid", false):
			push_error("Geography capture failed: %s" % [preview.generated.get("errors", [])])
			quit(1)
			return
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(String(fixture[0]) + "-overview.png"))
		print("Captured geography-first " + String(fixture[0]))
	quit(0)
