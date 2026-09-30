extends SceneTree


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var scene: PackedScene = load("res://launcher.tscn")
	var launcher = scene.instantiate()
	root.add_child(launcher)
	await _settle()
	_save_capture("launcher-main-16x9.png")
	launcher._show_single_player_menu()
	await _settle()
	_save_capture("launcher-single-player-16x9.png")
	launcher._show_random_map_menu()
	await _settle()
	_save_capture("launcher-random-map-16x9.png")
	launcher._show_loading_screen("СОЗДАНИЕ СЛУЧАЙНОЙ КАРТЫ", "Формирование природных областей")
	launcher.generation_progress_bar.value = 47.0
	await _settle()
	_save_capture("launcher-loading-16x9.png")

	root.size = Vector2i(1024, 768)
	launcher._show_main_menu()
	await _settle()
	_save_capture("launcher-main-4x3.png")

	root.size = Vector2i(1600, 700)
	launcher._show_loading_screen("СОЗДАНИЕ СЛУЧАЙНОЙ КАРТЫ", "Размещение ресурсов")
	launcher.generation_progress_bar.value = 81.0
	await _settle()
	_save_capture("launcher-loading-ultrawide.png")
	launcher.free()
	quit(0)


func _settle() -> void:
	await process_frame
	await process_frame
	await process_frame


func _save_capture(filename: String) -> void:
	var output_directory := ProjectSettings.globalize_path("res://../dist/qa")
	DirAccess.make_dir_recursive_absolute(output_directory)
	var error := root.get_texture().get_image().save_png(output_directory.path_join(filename))
	if error != OK:
		push_error("Could not save launcher capture %s: %s" % [filename, error_string(error)])
