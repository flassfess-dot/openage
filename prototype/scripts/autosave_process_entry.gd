extends SceneTree
func _initialize() -> void:
	root.add_child.call_deferred(load("res://scripts/autosave_process_worker.gd").new())
