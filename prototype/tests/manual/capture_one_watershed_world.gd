extends SceneTree

const DIRECTORY := "res://qa/continental-one-20261018"

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(2400, 1600)
	var started := Time.get_ticks_usec()
	var preview = load("res://random_map_preview.tscn").instantiate()
	root.add_child(preview)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if not preview.generated.get("valid", false):
		FileAccess.open(DIRECTORY.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify({"valid": false, "errors": preview.generated.get("errors", [])}, "\t"))
		push_error("Continental preview failed: %s" % [preview.generated.get("errors", [])])
		quit(1)
		return
	var data: Dictionary = preview.generated["map_data"]
	var file := FileAccess.open(DIRECTORY.path_join("map.bin"), FileAccess.WRITE)
	file.store_var(preview.generated)
	file.close()
	var report := {"valid": true, "seed": data["seed"], "size": str(data["size"]), "generator_version": data["generator_version"],
		"composition": data["ecology"]["composition"], "quality": preview.generated["map_quality"], "diagnostics": preview.generated["generation_diagnostics"],
		"lakes": data["lakes"].map(func(lake): return {"center": str(lake["center"]), "area": lake["area"], "origin": lake["origin"]}),
		"fords": data["fords"].map(func(ford): return {"center": str(ford["center"]), "bank_a": str(ford["bank_a"]), "bank_b": str(ford["bank_b"]), "discharge": ford["discharge"]}),
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	FileAccess.open(DIRECTORY.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	await _draw()
	root.get_texture().get_image().save_png(DIRECTORY.path_join("continental-400-overview.png"))
	if not data["fords"].is_empty():
		var ford: Dictionary = data["fords"][0]
		_focus(preview, Vector2(ford["center"]) + Vector2.ONE * 0.5, 0.95)
		await _draw()
		root.get_texture().get_image().save_png(DIRECTORY.path_join("ford-detail.png"))
	if not data["lakes"].is_empty():
		var lakes: Array = data["lakes"].duplicate()
		lakes.sort_custom(func(a, b): return int(a["area"]) > int(b["area"]))
		_focus(preview, Vector2(lakes[0]["center"]), 0.60)
		await _draw()
		root.get_texture().get_image().save_png(DIRECTORY.path_join("lake-detail.png"))
	print("Single continental preview captured: %d lakes, %d fords" % [data["lakes"].size(), data["fords"].size()])
	quit(0)

func _focus(preview, at: Vector2, zoom: float) -> void:
	preview.zoom = zoom
	preview.view_offset = Vector2(1200, 850) - preview.elevation.world_to_screen(at, zoom, Vector2.ZERO)
	preview._refresh(false)

func _draw() -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
