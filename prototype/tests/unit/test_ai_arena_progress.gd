extends SceneTree
const Runner=preload("res://tools/ai_arena_runner.gd")
const World=preload("res://scripts/simulation_world.gd")
const Controller=preload("res://scripts/game_controller.gd")
var failures: Array[String]=[]
func _initialize() -> void:
	var world=World.new(Vector2i(24,24))
	var actor: Dictionary=world.add_unit(1,"clubman",Vector2(5.5,5.5),false)
	var initial:=Runner.progress_signature(world)
	actor["task"]="gather"
	check(Runner.progress_signature(world)==initial,"a stuck gather order cannot mask the absence of actual progress")
	actor["pos"]+=Vector2(0.1,0)
	check(Runner.progress_signature(world)!=initial,"real movement counts even without a gameplay event")
	check(not Runner.legitimate_timer(world),"idle conquest has no countdown exemption")
	world.victory_system.hold_seconds["wonder:1"]=125.0
	check(Runner.legitimate_timer(world),"legitimate Wonder/artifact holding is not STALLED")
	world.victory_system.hold_seconds["wonder:1"]=0.0
	world.configure_victory_rules([{"type":"score","time_limit_seconds":900.0}])
	check(Runner.legitimate_timer(world),"score deadline is a legitimate finite wait")
	world.victory_system.elapsed_seconds=901.0
	check(not Runner.legitimate_timer(world),"expired deadlines cannot hide a stall")
	world.configure_victory_rules([{"type":"conquest"}])
	world.add_unit(2,"clubman",Vector2(21.5,21.5),false)
	var controller=Controller.new(world)
	controller.advance_frame(0.25,1,2,1)
	check(controller.tick_index==1,"an evaluator step cannot overshoot its fixed-tick limit while draining frame debt")
	controller.advance_frame(0.25,1,2,1)
	check(controller.tick_index==2,"pending frame debt still respects the requested one-tick boundary")
	world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
