extends SceneTree
const Predictor := preload("res://scripts/ai_combat_predictor.gd")
var failures: Array[String] = []

func unit(id: int,hp: float,damage: float,position: Vector2,reach: float=0.0) -> Dictionary:
	return {"id":id,"kind":"test","hp":hp,"pos":position,"movement_domain":"land","combat_enabled":true,"target_domains":["land"],"ai_profile":{"enabled":true,"damage":damage,"period":1.0,"range":reach,"speed":1.0,"max_hp":hp}}

func _initialize() -> void:
	var ours: Array = [unit(1,100.0,10.0,Vector2(4,4),4.0)]
	var enemies: Array = [unit(2,30.0,3.0,Vector2(5,4))]
	var before := var_to_bytes([ours,enemies])
	var prediction := Predictor.evaluate(ours,enemies)
	check(float(prediction["attack_ratio"])>1.0,"obvious ranged advantage predicted")
	check(var_to_bytes([ours,enemies])==before,"prediction never mutates observed input")
	check(Predictor.evaluate(ours,enemies)==prediction,"deterministic fixed-budget prediction")
	var mass: Array = []
	for index in range(500): mass.append(unit(index,30.0,3.0,Vector2(index%24,index/24)))
	var representatives := Predictor.representatives(mass)
	check(representatives.size()<=64,"representative budget bounded")
	var count := 0.0
	for actor in representatives: count+=float(actor["_count"])
	check(is_equal_approx(count,500.0),"large armies aggregated without discarding mass")
	for failure in failures: push_error(failure)
	print("Combat prediction: ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
