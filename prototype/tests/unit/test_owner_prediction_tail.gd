extends SceneTree
const Game := preload("res://main.gd")
var failures: Array[String] = []
func check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
func alpha_at(game, now: int) -> float:
	return game._owner_interpolation_alpha_for_elapsed(float(now-game.owner_alpha_started)*0.000001)
func _initialize() -> void:
	var game := Game.new()
	game._update_owner_prediction_anchor(10,1.0,2.0,1000000)
	game._update_owner_prediction_anchor(11,1.0,2.0,1100000)
	check(is_equal_approx(alpha_at(game,1150000),1.5),"ordinary short handoffs keep the linear trajectory")
	check(is_equal_approx(alpha_at(game,1200000),2.0),"first 100 ms retain confirmed-cadence motion")
	var a := alpha_at(game,1199999)
	var b := alpha_at(game,1200000)
	var c := alpha_at(game,1200001)
	check(absf((b-a)-(c-b))<0.00000001,"tail begins with continuous velocity")
	check(alpha_at(game,1250000)>alpha_at(game,1220000),"a longer capture decelerates instead of freezing")
	check(alpha_at(game,9000000)<=5.0,"the old renderer and requested-speed distance ceiling remains intact")
	var before := alpha_at(game,1350000)
	game._update_owner_prediction_anchor(12,1.0,2.0,1350000)
	check(1.0+alpha_at(game,1350000)+0.000001>=before,"slow publication preserves the straight trajectory")
	check(alpha_at(game,1380000)>alpha_at(game,1350000),"slower cadence does not quench the next confirmed pose")
	var now := 1350000
	for interval in [70000,220000,40000,180000,65000,240000,50000,80000]:
		now+=interval
		var old_clock:=float(game.owner_prediction_tick-1)+alpha_at(game,now)
		game._update_owner_prediction_anchor(game.owner_prediction_tick+1,1.0,2.0,now)
		var new_clock:=float(game.owner_prediction_tick-1)+alpha_at(game,now)
		check(new_clock+0.000001>=old_clock,"mixed real publication intervals do not rewind")
		check(alpha_at(game,now+10000000)<=5.0,"arbitrarily long waits never grow the distance ceiling")
	before=alpha_at(game,now+30000)
	game._update_owner_prediction_anchor(game.owner_prediction_tick,1.0,1.0,now+30000)
	check(is_equal_approx(before,alpha_at(game,now+30000)),"speed change preserves the displayed pose")
	game.owner_prediction_stopped=true
	game._update_owner_prediction_anchor(30,0.25,1.0,9000000)
	check(is_equal_approx(alpha_at(game,9000000),0.25),"resume discards paused wall time")
	game.free()
	for failure in failures: push_error(failure)
	print("Owner bounded prediction tail: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
