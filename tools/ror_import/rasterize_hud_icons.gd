extends SceneTree

# Offline helper for bake_hud_icons.py. Render the drawing
# and its flat material mask with the same SVG rasterizer.
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected the directory containing the temporary SVGs.")
		quit(1)
		return
	var directory := args[0]
	var count := 0
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() != "svg":
			continue
		var path := directory.path_join(file)
		var image := Image.new()
		if image.load_svg_from_string(FileAccess.get_file_as_string(path), 4.0) != OK or image.get_size() != Vector2i(200, 200):
			push_error("Expected 50×50 SVG artwork: " + path)
			quit(1)
			return
		if image.save_png(path.get_basename() + ".png") != OK:
			push_error("Could not save rasterized artwork: " + path)
			quit(1)
			return
		count += 1
	quit(0 if count > 0 else 1)
