extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440, 960)
	var scene = load("res://random_map_preview.tscn").instantiate()
	root.add_child(scene)
	var directory := "res://qa/landscape-v2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for profile in ["grasslands", "highlands", "islands"]:
		for i in range(scene.profiles.size()):
			if scene.profiles[i]["id"] == profile: scene.profile_choice.select(i)
		scene.generate_map()
		if not bool(scene.generated.get("valid", false)):
			quit(1)
			return
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(directory.path_join(profile + "-overview.png"))
		# The centre of a generated forest shows actual surfaces at normal gameplay scale.
		var forest: Array = scene.generated["map_data"]["resources"].filter(func(item): return item.get("ecology_role", "") == "forest_core")
		if not forest.is_empty():
			var point: Vector2 = forest[forest.size() / 2]["position"]
			scene.zoom = 1.2
			scene.view_offset = Vector2(720, 490) - scene.elevation.world_to_screen(point, scene.zoom, Vector2.ZERO)
			scene._refresh(false)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join(profile + "-detail.png"))
		if profile == "grasslands":
			var accents: Array = scene.generated["map_data"]["resources"].filter(func(item): return item.has("tree_condition"))
			print("Tree mix: %s; rare accents: %d" % [scene.generated["map_data"]["ecology"]["tree_sources"], accents.size()])
			if not accents.is_empty():
				var point: Vector2 = accents[0]["position"]
				scene.zoom = 1.4
				scene.view_offset = Vector2(720, 490) - scene.elevation.world_to_screen(point, scene.zoom, Vector2.ZERO)
				scene._refresh(false)
				await process_frame
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(directory.path_join("grasslands-rare-tree.png"))
		print("Captured generated " + profile)
	quit(0)
