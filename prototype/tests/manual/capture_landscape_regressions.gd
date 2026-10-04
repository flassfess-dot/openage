extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440, 960)
	var scene = load("res://random_map_preview.tscn").instantiate()
	root.add_child(scene)
	scene.seed_input.value = 41689
	var directory := "res://qa/landscape-20261003"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for profile in ["mediterranean", "islands", "small_islands", "coastal", "highlands", "hill_country"]:
		for i in range(scene.profiles.size()):
			if scene.profiles[i]["id"] == profile: scene.profile_choice.select(i)
		scene.size_choice.select(3 if profile in ["mediterranean", "islands", "small_islands", "highlands"] else 1)
		scene.generate_map()
		if not scene.generated.get("valid", false):
			push_error(str(scene.generated.get("errors", [])))
			quit(1)
			return
		await save_frame(directory.path_join(profile + "-overview.png"))
		var data: Dictionary = scene.generated["map_data"]
		if profile in ["highlands", "hill_country"]:
			var cliffs: Array = data["cliff_obstructions"].filter(func(item): return item["source_frame"] in [1, 2, 4, 5])
			if not cliffs.is_empty():
				var point: Vector2 = cliffs[cliffs.size() / 2]["position"]
				scene.zoom = 1.65
				scene.view_offset = Vector2(720, 530) - scene.elevation.world_to_screen(point, scene.zoom, Vector2.ZERO)
				scene._refresh(false)
				await save_frame(directory.path_join(profile + "-cliffs.png"))
		if profile == "coastal":
			var shoals: Array = data["scenery"].filter(func(item): return item["decoration_key"] == "ror_shallows")
			if not shoals.is_empty():
				var point: Vector2 = shoals[0]["position"] - Vector2(0.4, 0.4)
				var boat := {"id": 99999, "kind": "fishing_boat", "team": 1, "pos": point, "texture_key": "fishing_boat", "direction": Vector2.RIGHT}
				var info: Dictionary = scene.catalog.unit_frame_info(boat, "idle", 0.0)
				if info.get("texture") == null:
					push_error("Fishing boat artwork is unavailable")
					quit(1)
					return
				scene.objects.append({"position": point, "reference": true, "frame_info": info})
				scene.zoom = 2.2
				scene.view_offset = Vector2(720, 530) - scene.elevation.world_to_screen(point, scene.zoom, Vector2.ZERO)
				scene._refresh(false)
				await save_frame(directory.path_join("fishing-boat-shoal.png"))
		print("Captured " + profile)
	quit(0)

func save_frame(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
