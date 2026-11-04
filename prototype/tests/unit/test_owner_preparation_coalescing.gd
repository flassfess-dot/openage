extends SceneTree
const Owner := preload("res://scripts/simulation_owner.gd")
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
class Queue extends RefCounted:
	var active := true
	var prepared := false
	var preparation_budget_usec := 7000
	var preparation_usec_left := 0
	var source_tick := 0
	var apply_tick := 1
	func is_prepared() -> bool: return prepared
class Runtime extends RefCounted:
	var render_frame_override := -1
	var capture_budget_override := -1
	var decisions := Queue.new()
	var preparation := {"captures":{}}
	var error := ""
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
func _initialize() -> void:
	for mode in ["capture","worker","atomic"]:
		var world := World.new(Vector2i(16,16))
		var controller := Controller.new(world)
		var runtime := Runtime.new()
		var owner := Owner.new()
		var calls := [0]
		runtime.decisions.prepared = mode=="worker"
		controller.set_before_fixed_tick(func(_tick):
			calls[0]+=1
			if mode=="atomic": OS.delay_usec(owner.MAX_CATCHUP_BUDGET_USEC+1000)
			if mode=="capture" and calls[0]>=3:
				runtime.decisions.active=false
				runtime.decisions.prepared=true
				return {"ready":true}
			return {"ready":false})
		owner.submit(controller,runtime,0.05,1,2,1)
		var result: Dictionary=owner.take()
		if mode=="capture":
			check(calls[0]==3 and result["tick"]==1,"small captures complete in one handoff and elapsed time advances exactly one tick")
		else:
			check(calls[0]==1 and result["tick"]==0,"ready worker waits and over-budget producers do not spin")
		check(runtime.render_frame_override==-1 and runtime.capture_budget_override==-1 and runtime.decisions.preparation_budget_usec==7000,"capture overrides restore after every handoff")
		owner.shutdown()
		world.shutdown_derived_state()
	for failure in failures: push_error(failure)
	print("Owner preparation coalescing: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
