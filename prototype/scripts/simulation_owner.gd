extends RefCounted
## A bounded ownership handoff, not a worker snapshot of a mutable world.
## The caller must relinquish EVERY live controller/world reference until take().
var thread := Thread.new()
var wake := Semaphore.new()
var completed := Semaphore.new()
var mutex := Mutex.new()
var pending := false
var done := false
var stopping := false
var request: Array = []
var result: Dictionary = {}
const CAPTURE_BUDGET_USEC := 64000
const ADVANCE_BUDGET_USEC := 32000

func submit(controller, runtime, delta: float, player: int, enemy: int, frame: int) -> bool:
	if pending: return false
	if not thread.is_started():
		if thread.start(Callable(self, "_run")) != OK: return false
	request = [controller, runtime, delta, player, enemy, frame]
	pending = true
	wake.post()
	return true

func ready() -> bool:
	mutex.lock()
	var value := done
	mutex.unlock()
	return pending and (value or not thread.is_alive())

func take() -> Dictionary:
	if not pending: return {}
	while not completed.try_wait():
		if not thread.is_alive():
			pending = false
			return {"error":"Simulation owner stopped before completing its tick","failed":true}
		OS.delay_msec(1)
	mutex.lock()
	var output := result
	result = {}
	done = false
	mutex.unlock()
	pending = false
	return output

func shutdown() -> void:
	if pending: take()
	if thread.is_started():
		stopping = true
		wake.post()
		thread.wait_to_finish()

func _run() -> void:
	while true:
		wake.wait()
		if stopping: return
		var job := request
		request = []
		var controller = job[0]
		var runtime = job[1]
		var previous_frame: int = runtime.render_frame_override
		var previous_capture: int = runtime.capture_budget_override
		var previous_preparation: int = runtime.decisions.preparation_budget_usec
		var previous_advance: int = controller.frame_simulation_budget_usec
		var previous_yield: bool = controller.yield_ready_tick_for_presentation
		runtime.render_frame_override = int(job[5])
		runtime.capture_budget_override = CAPTURE_BUDGET_USEC
		runtime.decisions.preparation_budget_usec = CAPTURE_BUDGET_USEC
		controller.frame_simulation_budget_usec = ADVANCE_BUDGET_USEC
		controller.yield_ready_tick_for_presentation = false
		var message: String = controller.advance_frame(float(job[2]), int(job[3]), int(job[4]))
		runtime.render_frame_override = previous_frame
		runtime.capture_budget_override = previous_capture
		runtime.decisions.preparation_budget_usec = previous_preparation
		runtime.decisions.preparation_usec_left = mini(runtime.decisions.preparation_usec_left, previous_preparation)
		controller.frame_simulation_budget_usec = previous_advance
		controller.yield_ready_tick_for_presentation = previous_yield
		var state := {"message":message,"tick":controller.tick_index,"alpha":controller.get_interpolation_alpha(),"waiting":controller.preparation_waiting,"debt":controller.accumulator_seconds,"error":runtime.error}
		var queue = runtime.decisions
		state.merge({"ai_capture":queue.active and not queue.is_prepared(),"ai_active":queue.active,"apply_tick":queue.apply_tick,"source_tick":queue.source_tick,"capture_phase":runtime.preparation.captures.values()[0]["phase"] if not runtime.preparation.captures.is_empty() else ""})
		mutex.lock()
		result = state
		done = true
		mutex.unlock()
		completed.post()
