extends SceneTree
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1440, 960)
	var directory := "res://qa/decorations-20260930"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var scene = load("res://random_map_preview.tscn").instantiate()
	root.add_child(scene)
	for profile in ["grasslands", "mediterranean", "highlands", "islands"]:
		for i in range(scene.profiles.size()):
			if scene.profiles[i]["id"] == profile: scene.profile_choice.select(i)
		scene.seed_input.value = 41689
		scene.generate_map()
		await photograph(directory + "/" + profile + "-overview.png")
		var items: Array = scene.generated["map_data"]["scenery"]
		for group in ["grass", "shore", "trail"]:
			var selected: Array = items.filter(func(item):
				var key: String = item["decoration_key"]
				return key in ["ror_grass", "undergrowth"] if group == "grass" else key in ["ror_shallows", "coastal_rocks", "ror_sea_rocks"] if group == "shore" else item["ecology_role"] == "route_detail")
			if selected.is_empty(): continue
			var at: Vector2 = selected[selected.size() / 2]["position"]
			scene.zoom = 2.0
			scene.view_offset = Vector2(720, 510) - scene.elevation.world_to_screen(at, scene.zoom, Vector2.ZERO)
			scene._refresh(false)
			await photograph(directory + "/" + profile + "-" + group + ".png")
	scene.queue_free()
	await process_frame
	var gallery = load("res://environment_preview.tscn").instantiate()
	root.add_child(gallery)
	for key in ["ror_grass", "undergrowth", "overgrown_trail", "ror_cracks", "bones"]:
		gallery.decoration_choice.select(gallery.decoration_keys.find(key))
		gallery.set_mode(3)
		await photograph(directory + "/gallery-" + key + ".png")
	gallery.queue_free()
	await process_frame
	print("Decoration screenshots captured")
	quit()

func photograph(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
