extends SceneTree
const Game := preload("res://main.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
func alpha_at(game,now: int) -> float:
	return game._owner_interpolation_alpha_for_elapsed(float(now-game.owner_alpha_started)*0.000001)
func _initialize() -> void:
	for legacy in [true,false]:
		var game:=Game.new()
		game.owner_prediction_tail_enabled=false
		game.owner_prediction_continuity_enabled=not legacy
		game._update_owner_prediction_anchor(10,1.0,2.0,1000000)
		game._update_owner_prediction_anchor(11,1.0,2.0,1100000)
		var before:=alpha_at(game,1140000)
		game._update_owner_prediction_anchor(11,1.0,2.0,1140000)
		var after:=alpha_at(game,1140000)
		check(after<before if legacy else is_equal_approx(after,before),"legacy reproduces and continuity removes the same-pose rewind")
		if not legacy:
			check(game.owner_alpha_started==1100000,"capture portions retain the pose time origin")
			check(is_equal_approx(game.owner_prediction_rate,10.0),"presentation follows confirmed cadence without changing requested speed")
			check(is_equal_approx(alpha_at(game,1800000),2.0),"prediction stops after the original 100 ms window")
			for index in range(2,12):
				var now:=1000000+index*100000
				var old_clock:=float(game.owner_prediction_tick-1)+alpha_at(game,now)
				game._update_owner_prediction_anchor(10+index,1.0,2.0,now)
				var new_clock:=float(game.owner_prediction_tick-1)+alpha_at(game,now)
				check(new_clock+0.000001>=old_clock,"later authoritative ticks never rewind a straight moving trajectory")
			var now:=2140000
			before=alpha_at(game,now)
			game._update_owner_prediction_anchor(game.owner_prediction_tick,1.0,1.0,now)
			check(is_equal_approx(alpha_at(game,now),before),"changing speed does not jump the current pose")
			game.owner_prediction_stopped=true
			game._update_owner_prediction_anchor(21,0.25,1.0,9000000)
			check(is_equal_approx(alpha_at(game,9000000),0.25) and game.owner_alpha_started==9000000,"resume discards the paused wall-time interval")
		game.free()
	for failure in failures: push_error(failure)
	print("Owner prediction continuity: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
