extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1440, 960)
	var scene = load("res://environment_preview.tscn").instantiate()
	root.add_child(scene)
	var directory := "res://qa/environment-pack"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for mode in range(3):
		scene.set_mode(mode)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var filename := directory.path_join(["landscape.png", "objects.png", "surfaces.png"][mode])
		var error := root.get_texture().get_image().save_png(filename)
		if error != OK:
			push_error("Capture failed: " + filename)
			quit(1)
			return
		print("Saved " + filename)
	quit(0)
