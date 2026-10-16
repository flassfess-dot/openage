extends SceneTree

func _initialize() -> void:
	root.add_child.call_deferred(load("res://tests/manual/verify_interface_player_colors.gd").new())
