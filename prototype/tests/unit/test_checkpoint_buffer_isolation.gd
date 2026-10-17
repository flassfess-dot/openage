extends SceneTree
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
func _initialize() -> void:
	var world := World.new(Vector2i(8,8))
	var controller := Controller.new(world)
	world.fog_of_war.ensure_player(1)
	var planner = world.movement_system.knowledge.planner(world, 1)
	var checkpoint := Checkpoint.capture(world, controller, {}, {"size": world.map_size})
	planner.grid.learned[0] = 1
	var passed := int(checkpoint["knowledge"][1]["grid"]["learned"][0]) == 0
	world.shutdown_derived_state()
	if not passed: push_error("A captured checkpoint must not share its learned-cell buffer with the live world")
	print("Checkpoint buffer isolation: ", passed)
	quit(0 if passed else 1)
