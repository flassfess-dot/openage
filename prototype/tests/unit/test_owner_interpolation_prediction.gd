extends SceneTree

const Game := preload("res://main.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var game := Game.new()
	game.owner_state = {"alpha": 0.25}
	game.owner_speed = 1.5
	check(is_equal_approx(game._owner_interpolation_alpha_for_elapsed(0.0), 0.25), "prediction starts at the confirmed interpolation remainder")
	check(is_equal_approx(game._owner_interpolation_alpha_for_elapsed(0.05), 1.75), "prediction follows game speed across a short owner job")
	check(is_equal_approx(game._owner_interpolation_alpha_for_elapsed(0.1), 3.25), "prediction covers the reported 100 ms barrier")
	check(is_equal_approx(game._owner_interpolation_alpha_for_elapsed(0.5), 3.25), "prediction remains bounded when a worker takes longer")
	game.free()
	for failure in failures: push_error(failure)
	print("Owner interpolation prediction: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
