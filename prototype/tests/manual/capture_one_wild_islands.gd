extends SceneTree

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(2400, 1600)
	var started := Time.get_ticks_usec()
	var preview = load("res://random_map_preview.tscn").instantiate()
	root.add_child(preview)
	var directory := "res://qa/river-islands-one-20261018" if preview.river_islands else "res://qa/wild-islands-one-20261018"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if not preview.generated.get("valid", false):
		var failure := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
		failure.store_string(JSON.stringify({"valid": false, "errors": preview.generated.get("errors", [])}, "\t"))
		push_error("One wild-islands map failed: %s" % [preview.generated.get("errors", [])])
		quit(1)
		return
	var data: Dictionary = preview.generated["map_data"]
	var saved := FileAccess.open(directory.path_join("map.bin"), FileAccess.WRITE)
	saved.store_var(preview.generated)
	saved.close()
	var report := {"valid": true, "seed": data["seed"], "size": str(data["size"]), "generator_version": data["generator_version"],
		"starts": preview.generated["definition"]["players"].map(func(player): return {"team": player["team"], "start": str(player["start"])}),
		"composition": data["ecology"]["composition"], "quality": preview.generated["map_quality"], "diagnostics": preview.generated["generation_diagnostics"],
		"elapsed_ms": float(Time.get_ticks_usec() - started) / 1000.0}
	FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("One wild map ready: %s" % [report["starts"]])
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory.path_join("islands-400-overview.png"))
	if preview.river_islands:
		var channels: Array = data["rivers"]["nodes"]
		if not channels.is_empty():
			var node: Dictionary = channels[0]
			var best := -1.0
			var incoming: Dictionary = {}
			for candidate in channels:
				var downstream: Vector2i = candidate["downstream"]
				if not incoming.has(downstream): incoming[downstream] = []
				incoming[downstream].append(float(candidate["discharge"]))
			for candidate in channels:
				var tributaries: Array = incoming.get(candidate["cell"], [])
				if tributaries.size() < 2: continue
				tributaries.sort()
				var score := float(tributaries[-2]) / (1.0 + absf(float(candidate["mouth_distance"]) - 18.0) * 0.05)
				if score > best:
					best = score
					node = candidate
			var at := Vector2(node["cell"]) + Vector2.ONE * 0.5
			preview.zoom = 0.85
			preview.view_offset = Vector2(1200, 850) - preview.elevation.world_to_screen(at, preview.zoom, Vector2.ZERO)
			preview._refresh(false)
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory.path_join("river-detail.png"))
	print("Captured the single wild-islands map")
	quit(0)
