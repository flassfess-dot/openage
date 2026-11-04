extends SceneTree
const Frozen=preload("res://ai_baselines/v1/scripts/ai_strategy_state.gd")
const Fast=preload("res://scripts/ai_baseline_acceleration.gd")
var failures: Array[String]=[]
func _initialize() -> void:
	var rng:=RandomNumberGenerator.new(); rng.seed=20261030
	var ordinary:=0; var accelerated:=0
	for trial in range(80):
		var snapshot:={"tick":trial*20,"observer_team":1,"map_size":Vector2i(96,96),"units":[],"buildings":[],"navigation":{"reachable":{"land":[],"water":[]}},"player_state":{"allies":[1],"relations":{2:"enemy"}}}
		for y in range(64):
			for x in range(64):
				if rng.randf()>0.15: snapshot["navigation"]["reachable"]["land" if x<40 else "water"].append(Vector2(x+0.5,y+0.5))
		for id in range(24):
			var team:=1 if id<8 else 2
			snapshot["units"].append({"id":id+1,"team":team,"kind":"test","hp":40.0,"max_hp":40.0,"pos":Vector2(rng.randf_range(2,62),rng.randf_range(2,62)),"movement_domain":"water" if id%3==0 else "land","target_domains":["land","water"],"combat_enabled":true,"ai_profile":{"enabled":true,"damage":4.0,"period":2.0,"range":float(id%10),"speed":0.8}})
		var base=Frozen.new(); var fast=Fast.new(); base.observe(snapshot,1,{}); fast.observe(snapshot,1,{})
		var started:=Time.get_ticks_usec(); var original: Dictionary=base.choose_goal(snapshot,1,{},trial); ordinary+=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec(); var result: Dictionary=fast.choose_goal(snapshot,1,{},trial); accelerated+=Time.get_ticks_usec()-started
		if original!=result or base.canonical_state()!=fast.canonical_state(): failures.append("exact goal/state mismatch at "+str(trial))
	var file:=FileAccess.open("res://qa/ai-competitive/competitive-20261030/baseline_acceleration.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":80,"failures":failures,"original_usec":ordinary,"accelerated_usec":accelerated,"scope":"goal selection only; identical canonical results; frozen source unchanged"},"\t"))
	for failure in failures: push_error(failure)
	print("Exact baseline acceleration: ",failures.size()," failures"); quit(0 if failures.is_empty() else 1)
