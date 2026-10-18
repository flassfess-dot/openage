extends SceneTree

const DIRECTORY := "res://qa/world-generator-20261018"

func _initialize() -> void:
	call_deferred("capture")

# Render already validated fixtures, without generating a visual seed series.
func capture() -> void:
	root.size = Vector2i(1920, 1280)
	for profile in ["small_islands", "mediterranean", "narrows", "highlands"]:
		var preview = load("res://random_map_preview.tscn").instantiate()
		preview.preview_fixture = DIRECTORY.path_join(profile + "-large.bin")
		root.add_child(preview)
		if not preview.generated.get("valid", false):
			push_error("Cached world preview failed: %s" % profile)
			quit(1)
			return
		for i in range(preview.profiles.size()):
			if preview.profiles[i]["id"] == profile: preview.profile_choice.select(i)
		preview.size_choice.select(2)
		preview._refresh(false)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(DIRECTORY.path_join(profile + "-overview.png"))
		preview.free()
		await process_frame
		print("Rendered current world profile: %s" % profile)
	quit(0)
