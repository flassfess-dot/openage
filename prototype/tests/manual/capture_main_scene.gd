extends SceneTree

# Deterministic presentation capture for HUD and world-layout review. This is a
# manual L3 tool, not part of the automated test suite and does not rebuild the
# imported source-resource cache.

const DEFAULT_SIZE := Vector2i(800, 600)
const DEFAULT_OUTPUT := "res://qa/main-scene-capture.png"


func _initialize() -> void:
	var requested_size := DEFAULT_SIZE
	var output_path := DEFAULT_OUTPUT
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			requested_size = parse_size(argument.trim_prefix("--size="))
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")

	var viewport := SubViewport.new()
	viewport.size = requested_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var scene: PackedScene = load("res://main.tscn")
	viewport.add_child(scene.instantiate())
	for _frame in range(6):
		await process_frame

	var image := viewport.get_texture().get_image()
	var result := image.save_png(output_path)
	if result != OK:
		push_error("Failed to save presentation capture %s: %s" % [output_path, error_string(result)])
		quit(1)
		return
	print("Presentation capture saved: %s (%dx%d)" % [output_path, requested_size.x, requested_size.y])
	quit(0)


func parse_size(value: String) -> Vector2i:
	var parts := value.to_lower().split("x", false)
	if parts.size() != 2:
		return DEFAULT_SIZE
	var parsed := Vector2i(int(parts[0]), int(parts[1]))
	return parsed if parsed.x >= 320 and parsed.y >= 240 else DEFAULT_SIZE
