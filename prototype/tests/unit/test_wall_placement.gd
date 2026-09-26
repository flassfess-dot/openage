extends SceneTree

const WallPlacement := preload("res://scripts/wall_placement.gd")


func _initialize() -> void:
	var horizontal := WallPlacement.cells(Vector2i(4, 7), Vector2i(8, 7))
	assert(horizontal == [Vector2i(4, 7), Vector2i(5, 7), Vector2i(6, 7), Vector2i(7, 7), Vector2i(8, 7)])
	var diagonal := WallPlacement.cells(Vector2i(8, 8), Vector2i(5, 5))
	assert(diagonal == [Vector2i(8, 8), Vector2i(7, 7), Vector2i(6, 6), Vector2i(5, 5)])
	var limited := WallPlacement.cells(Vector2i(0, 0), Vector2i(100, 0), 33)
	assert(limited.size() == 33 and limited[0] == Vector2i.ZERO and limited[-1] == Vector2i(32, 0))
	print("Wall drag geometry tests passed")
	quit(0)
