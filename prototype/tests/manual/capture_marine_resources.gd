extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440, 960)
	var scene = load("res://random_map_preview.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.seed_input.value = 41689
	for index in range(scene.profiles.size()):
		if scene.profiles[index]["id"] == "mediterranean": scene.profile_choice.select(index)
	scene.generate_map()
	if not scene.generated.get("valid", false):
		push_error("Marine preview generation failed")
		quit(1)
		return
	var directory := "res://qa/marine-resources-20260930"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for kind in ["shore_fish", "deep_fish", "whale"]:
		var matches: Array = scene.objects.filter(func(item): return item.has("animated_resource") and item["animated_resource"]["kind"] == kind)
		if matches.is_empty():
			push_error("Missing marine preview object: " + kind)
			quit(1)
			return
		var item: Dictionary = matches[0]
		var largest := -1
		# Capture an actual visible point in the original surfacing cycle.
		for step in range(201):
			var time := float(step) * 0.1
			var info: Dictionary = scene.catalog.resource_frame_info(item["animated_resource"], time)
			if info.get("texture") == null: continue
			var area: int = info["texture"].get_image().get_used_rect().get_area()
			if area > largest:
				largest = area
				scene.animation_time = time
		scene.zoom = 2.27
		scene.view_offset = Vector2(720, 520) - scene.elevation.world_to_screen(item["position"], scene.zoom, Vector2.ZERO)
		scene._refresh(false)
		await save_frame(directory.path_join(kind + ".png"))
		print("Captured %s at source animation time %.2f" % [kind, scene.animation_time])
	scene._fit_view()
	await save_frame(directory.path_join("mediterranean-overview.png"))
	var report := FileAccess.open(directory.path_join("population.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"seed":41689, "profile":"mediterranean", "resources":scene.generated["map_data"]["marine_resources"]}, "  "))
	quit(0)

func save_frame(path: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
