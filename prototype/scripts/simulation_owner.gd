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
# Return ownership to presentation between observation portions instead of
# keeping one source boundary for a 50-100 ms batch. Individual producers are
# still atomic, so this is a latency ceiling rather than a correctness timeout.
const CAPTURE_BUDGET_USEC := 8000
const ADVANCE_BUDGET_USEC := 16000
const MAX_CATCHUP_BUDGET_USEC := 32000
const MAX_PREPARATION_PORTIONS := 4
var cooperative_preparation_enabled := true
var catchup_budget_enabled := true

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
		# The render thread keeps its retained snapshot while we own the world.
		# A bounded larger window lets an overdue simulation perform two cheap
		# steps instead of losing another render frame after each individual tick.
		var owed_seconds: float = controller.accumulator_seconds + minf(0.25, maxf(0.0, float(job[2]))) * controller.get_speed_multiplier()
		var request_budget: int = MAX_CATCHUP_BUDGET_USEC if catchup_budget_enabled and owed_seconds >= controller.FIXED_STEP_SECONDS * 2.0 else ADVANCE_BUDGET_USEC
		controller.frame_simulation_budget_usec = request_budget
		controller.yield_ready_tick_for_presentation = false
		var started := Time.get_ticks_usec()
		var source_tick: int = controller.tick_index
		var message: String = controller.advance_frame(float(job[2]), int(job[3]), int(job[4]))
		# A partial read capture has not advanced the source tick. Use the rest
		# of this ownership window instead of waiting for another rendered frame
		# between every small portion. Elapsed game time is submitted only once.
		var portions := 1
		while cooperative_preparation_enabled and portions < MAX_PREPARATION_PORTIONS and controller.tick_index == source_tick and controller.preparation_waiting and runtime.decisions.active and not runtime.decisions.is_prepared() and String(runtime.error).is_empty():
			var remaining := request_budget - (Time.get_ticks_usec() - started)
			if remaining <= 0: break
			runtime.capture_budget_override = mini(CAPTURE_BUDGET_USEC, remaining)
			runtime.decisions.preparation_usec_left = runtime.capture_budget_override
			message = controller.advance_frame(0.0, int(job[3]), int(job[4]))
			portions += 1
		if controller.performance_probe != null:
			controller.performance_probe.observe_microseconds("owner.request", Time.get_ticks_usec() - started)
			controller.performance_probe.increment("owner.preparation_extra_portions", portions - 1)
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
