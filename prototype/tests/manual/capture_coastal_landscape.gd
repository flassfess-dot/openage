extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440, 960)
	var scene = load("res://random_map_preview.tscn").instantiate()
	root.add_child(scene)
	scene.seed_input.value = 41689
	var directory := "res://qa/coastline-20260930"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for profile in ["mediterranean", "coastal", "islands"]:
		for i in range(scene.profiles.size()):
			if scene.profiles[i]["id"] == profile: scene.profile_choice.select(i)
		scene.generate_map()
		if not scene.generated.get("valid", false):
			quit(1)
			return
		await save_frame(directory.path_join(profile + "-overview.png"))
		var data: Dictionary = scene.generated["map_data"]
		var coast := Vector2.ZERO
		var nearest := INF
		var target := Vector2(scene.map_size) * Vector2(0.5, 0.65 if profile == "mediterranean" else 0.5)
		for i in range(data["terrain_ids"].size()):
			if data["terrain_ids"][i] != 2: continue
			var point := Vector2(i % scene.map_size.x + 0.5, i / scene.map_size.x + 0.5)
			if point.distance_to(target) < nearest:
				nearest = point.distance_to(target)
				coast = point
		scene.zoom = 2.27
		scene.view_offset = Vector2(720, 540) - scene.elevation.world_to_screen(coast, scene.zoom, Vector2.ZERO)
		scene._refresh(false)
		await save_frame(directory.path_join(profile + "-coast.png"))
		var shoals: Array = data["water_features"]["sandbar_anchors"]
		if not shoals.is_empty():
			scene.view_offset = Vector2(720, 540) - scene.elevation.world_to_screen(Vector2(shoals[0]), scene.zoom, Vector2.ZERO)
			scene._refresh(false)
			await save_frame(directory.path_join(profile + "-shallows.png"))
		print("Captured coast %s seed 41689" % profile)
	quit(0)

func save_frame(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
