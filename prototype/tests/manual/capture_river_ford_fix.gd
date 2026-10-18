extends SceneTree

const DIRECTORY := "res://qa/river-ford-fix-20261019"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1600, 1000)
	var started := Time.get_ticks_usec()
	var preview = load("res://random_map_preview.tscn").instantiate()
	if "--reuse-map" in OS.get_cmdline_user_args():
		var built: Dictionary = FileAccess.open(DIRECTORY.path_join("map.bin"), FileAccess.READ).get_var()
		var data: Dictionary = built["map_data"]
		data["scenery"] = data["scenery"].filter(func(item): return not bool(item.get("ford_detail", false)))
		preload("res://scripts/random_map_hydrology.gd").decorate_fords(data, int(data["seed"]))
		data["content_hash"] = ("watershed_world_v6:" + preload("res://scripts/random_map_landscape.gd").fingerprint(data)).sha256_text()
		FileAccess.open(DIRECTORY.path_join("map.bin"), FileAccess.WRITE).store_var(built)
		preview.preview_fixture = DIRECTORY.path_join("map.bin")
	root.add_child(preview)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if not preview.generated.get("valid", false):
		push_error("River/ford capture failed: %s" % [preview.generated.get("errors", [])])
		quit(1)
		return
	var data: Dictionary = preview.generated["map_data"]
	FileAccess.open(DIRECTORY.path_join("map.bin"), FileAccess.WRITE).store_var(preview.generated)
	if data["fords"].is_empty():
		push_error("Control map must contain an actual river ford")
		quit(1)
		return
	var ford: Dictionary = data["fords"][0]
	_focus(preview, Vector2(ford["center"]) + Vector2.ONE * 0.5, 1.5)
	await _draw()
	root.get_texture().get_image().save_png(DIRECTORY.path_join("ford-detail.png"))
	var mouths: Array = data["rivers"]["nodes"].filter(func(node): return bool(node["is_mouth"]) and not bool(node.get("boundary_outlet", false)))
	mouths.sort_custom(func(a, b): return Vector2(a["cell"]).distance_squared_to(Vector2(118, 94)) < Vector2(b["cell"]).distance_squared_to(Vector2(118, 94)))
	if mouths.is_empty():
		push_error("Control map must contain a real river mouth")
		quit(1)
		return
	_focus(preview, Vector2(mouths[0]["cell"]) + Vector2.ONE * 0.5, 1.2)
	await _draw()
	root.get_texture().get_image().save_png(DIRECTORY.path_join("mouth-detail.png"))
	var report := {"valid": true, "size": str(data["size"]), "seed": data["seed"], "ford": str(ford["center"]),
		"mouth": str(mouths[0]["cell"]), "fords": data["fords"].size(), "mouths": mouths.size(), "hash": data["content_hash"],
		"ford_details": data["scenery"].filter(func(item): return bool(item.get("ford_detail", false))).size(),
		"quality": preview.generated["map_quality"], "elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	FileAccess.open(DIRECTORY.path_join("capture.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0)

func _focus(preview, at: Vector2, zoom: float) -> void:
	preview.zoom = zoom
	preview.view_offset = Vector2(800, 550) - preview.elevation.world_to_screen(at, zoom, Vector2.ZERO)
	preview._refresh(false)

func _draw() -> void:
	for unused in range(8): await process_frame
	await RenderingServer.frame_post_draw
