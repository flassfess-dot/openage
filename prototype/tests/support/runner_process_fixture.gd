extends SceneTree

func _initialize() -> void:
	var mode := OS.get_cmdline_user_args()[0]
	if mode == "hang":
		return
	if mode == "error":
		push_error("runner fixture engine error")
	quit(7 if mode == "failure" else 0)