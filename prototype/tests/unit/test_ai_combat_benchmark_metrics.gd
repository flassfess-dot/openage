extends SceneTree
const Metrics=preload("res://tools/ai_combat_benchmark.gd")
func _initialize() -> void:
	var ours: Array=[{"team":1,"hp":80.0,"max_hp":100.0}]
	var enemies: Array=[{"team":1,"hp":70.0,"max_hp":100.0}]
	var passed:=is_equal_approx(Metrics.retained_fraction(enemies,2),0.0) and is_equal_approx(Metrics.retained_fraction(ours,1),0.8) and Metrics.outcome_margin(ours,enemies)>0.0
	ours[0]["team"]=2; enemies[0]["team"]=2
	passed=passed and Metrics.outcome_margin(ours,enemies)<0.0 and is_equal_approx(Metrics.retained_fraction(ours,1),0.0)
	if not passed: push_error("conversion must change battle ownership and count as loss of the initial roster")
	print("Ownership-aware combat benchmark metrics: ",passed); quit(0 if passed else 1)
