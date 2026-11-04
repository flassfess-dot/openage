extends SceneTree
const Runner=preload("res://tools/ai_arena_runner.gd")
func _initialize() -> void:
	root.add_child.call_deferred(Runner.new())
