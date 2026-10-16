extends SceneTree

func _initialize() -> void:
	var verifier = load("res://tests/manual/verify_gate_occlusion.gd")
	if verifier == null or not verifier.can_instantiate():
		quit(1)
		return
	root.add_child.call_deferred(verifier.new())
