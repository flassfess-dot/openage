extends RefCounted
const CacheDependency := preload("res://scripts/cache_dependency.gd")
const RenderWorld := preload("res://scripts/render_world.gd")
## A bounded ownership handoff, not a worker snapshot of a mutable world.
## The caller must relinquish EVERY live controller/world reference until take().
var thread := Thread.new()
var wake := Semaphore.new()
var completed := Semaphore.new()
var mutex := Mutex.new()
var pending := false
var done := false
var stopping := false
var handoff_requested := false
var accepts_time := false
var offered_seconds := 0.0
var offered_frame := 0
var preview: Dictionary = {}
const MAX_SLICES_PER_HANDOFF := 3
var request: Array = []
var result: Dictionary = {}
var autosave_service: RefCounted
# Source/cache ownership follows the world until take(); input contains UI values.
var presentation_request: Dictionary = {}
# Check handoff requests between bounded AI capture portions. A completed
# fixed step can publish a detached pose while the owner advances the next.
const CAPTURE_BUDGET_USEC := 8000
const ADVANCE_BUDGET_USEC := 16000
const MAX_CATCHUP_BUDGET_USEC := 32000
var cooperative_preparation_enabled := true
var catchup_budget_enabled := true
var profile_handoffs := "--profile-owner-handoffs" in OS.get_cmdline_user_args()
var handoff_probe: Variant = null
var completed_usec := 0
var taken_usec := 0

func submit(controller, runtime, delta: float, player: int, enemy: int, frame: int) -> bool:
	if pending: return false
	if profile_handoffs:
		handoff_probe = controller.performance_probe if controller.performance_probe != null else controller.get("fixed_tick_observer")
		if handoff_probe != null and taken_usec > 0:
			handoff_probe.observe_microseconds("owner.handoff.main", Time.get_ticks_usec() - taken_usec)
	if not thread.is_started():
		if thread.start(Callable(self, "_run")) != OK: return false
	request = [controller, runtime, delta, player, enemy, frame, autosave_service, presentation_request]
	mutex.lock()
	accepts_time = bool(presentation_request.get("stream", false))
	offered_seconds = 0.0
	offered_frame = frame
	handoff_requested = false
	mutex.unlock()
	presentation_request = {}
	pending = true
	wake.post()
	return true

func offer_time(seconds: float, frame: int) -> bool:
	mutex.lock()
	var accepted := accepts_time and not handoff_requested
	if accepted:
		offered_seconds += seconds
		offered_frame = frame
	mutex.unlock()
	return accepted

func take_preview() -> Dictionary:
	mutex.lock()
	var value := preview
	preview = {}
	mutex.unlock()
	return value

func ready() -> bool:
	mutex.lock()
	var value := done
	mutex.unlock()
	return pending and (value or not thread.is_alive())

func take() -> Dictionary:
	if not pending: return {}
	mutex.lock()
	handoff_requested = true
	mutex.unlock()
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
	if profile_handoffs:
		taken_usec = Time.get_ticks_usec()
		if handoff_probe != null and completed_usec > 0:
			handoff_probe.observe_microseconds("owner.handoff.result_wait", taken_usec - completed_usec)
		handoff_probe = null
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
		var state := {}
		var last_packet := {}
		for slice in range(MAX_SLICES_PER_HANDOFF):
			state = _advance(job)
			if state.has("presentation"): last_packet = state["presentation"]
			if slice + 1 >= MAX_SLICES_PER_HANDOFF or not _can_publish_between_steps(job, state): break
			var preview_data := _preview_packet(job, state)
			var controller = job[0]
			var speed: float = controller.get_speed_multiplier()
			mutex.lock()
			var owed: float = controller.accumulator_seconds + offered_seconds * speed
			if handoff_requested or owed + 0.000001 < controller.FIXED_STEP_SECONDS:
				mutex.unlock()
				break
			preview = preview_data
			job[2] = offered_seconds
			job[5] = offered_frame
			offered_seconds = 0.0
			mutex.unlock()
			job[7]["cached_tick"] = state["tick"]
		if not state.has("presentation") and last_packet.get("tick") == state["tick"]:
			state["presentation"] = last_packet
		mutex.lock()
		accepts_time = false
		state["unused_seconds"] = offered_seconds
		offered_seconds = 0.0
		preview = {}
		result = state
		if profile_handoffs: completed_usec = Time.get_ticks_usec()
		done = true
		mutex.unlock()
		completed.post()


func _advance(job: Array) -> Dictionary:
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
	var saves = job[6]
	if saves != null: saves.prepare_capture_on_owner(controller.simulation_world, controller, runtime)
	var message: String = controller.advance_frame(float(job[2]), int(job[3]), int(job[4]))
	# While a source read is unfinished there is no newer world state to
	# present. Continue taking bounded portions on this worker. An explicit
	# request for the world interrupts between portions, and a full planning
	# queue yields instead of polling for capacity. Charge wall time once.
	var portions := 1
	while cooperative_preparation_enabled and controller.tick_index == source_tick and controller.preparation_waiting and not controller.paused and runtime.decisions.active and runtime.decisions.has_runnable_capture() and String(runtime.error).is_empty():
		mutex.lock()
		var interrupted := handoff_requested
		mutex.unlock()
		if interrupted: break
		runtime.capture_budget_override = CAPTURE_BUDGET_USEC
		runtime.decisions.preparation_usec_left = runtime.capture_budget_override
		message = controller.advance_frame(0.0, int(job[3]), int(job[4]))
		portions += 1
	if saves != null: saves.advance_capture_on_owner(controller.simulation_world, controller)
	var request_probe: Variant = controller.performance_probe if controller.performance_probe != null else controller.get("fixed_tick_observer")
	var presentation_started := Time.get_ticks_usec()
	var presentation := _publish_presentation(controller, job[7])
	if request_probe != null:
		if not presentation.is_empty(): request_probe.observe_microseconds("owner.presentation_capture", Time.get_ticks_usec() - presentation_started)
		request_probe.observe_microseconds("owner.request", Time.get_ticks_usec() - started)
		request_probe.increment("owner.preparation_extra_portions", portions - 1)
		if profile_handoffs:
			request_probe.increment("owner.advanced_ticks", controller.tick_index - source_tick)
			request_probe.increment("owner.requests_with_tick" if controller.tick_index != source_tick else "owner.requests_without_tick")
	runtime.render_frame_override = previous_frame
	runtime.capture_budget_override = previous_capture
	runtime.decisions.preparation_budget_usec = previous_preparation
	runtime.decisions.preparation_usec_left = mini(runtime.decisions.preparation_usec_left, previous_preparation)
	controller.frame_simulation_budget_usec = previous_advance
	controller.yield_ready_tick_for_presentation = previous_yield
	var state := {"message":message,"tick":controller.tick_index,"alpha":controller.get_interpolation_alpha(),"waiting":controller.preparation_waiting,"debt":controller.accumulator_seconds,"error":runtime.error}
	if not presentation.is_empty(): state["presentation"] = presentation
	var queue = runtime.decisions
	state.merge({"ai_capture":queue.active and not queue.is_prepared(),"ai_active":queue.active,"apply_tick":queue.apply_tick,"source_tick":queue.source_tick,"capture_phase":runtime.preparation.captures.values()[0]["phase"] if not runtime.preparation.captures.is_empty() else ""})
	return state


func _can_publish_between_steps(job: Array, state: Dictionary) -> bool:
	var query: Dictionary = job[7]
	if not query.get("stream", false) or not state.has("presentation") or not String(state["error"]).is_empty(): return false
	var controller = job[0]
	var world = controller.simulation_world
	if controller.paused or world.battle_over or query["terrain_revision"] != world.terrain_revision or query["terrain_epoch"] != world.cache_epoch or query["elevation_revision"] != world.terrain_elevation.revision: return false
	var snapshot: Dictionary = state["presentation"]["snapshot"]
	if snapshot.get("scenario", {}).get("result", {}).get("over", false) or snapshot.get("match_result", {}).get("over", false): return false
	mutex.lock()
	var due: bool = not handoff_requested and controller.accumulator_seconds + offered_seconds * controller.get_speed_multiplier() + 0.000001 >= controller.FIXED_STEP_SECONDS
	mutex.unlock()
	return due


func _preview_packet(job: Array, state: Dictionary) -> Dictionary:
	var controller = job[0]
	var world = controller.simulation_world
	var query: Dictionary = job[7]
	var team := int(query["team"])
	var packet: Dictionary = state["presentation"]
	var groups := {}
	for id in controller.formation_groups:
		groups[id] = {"preferred_formation_type":controller.formation_groups[id].preferred_formation_type}
	var compact_state := state.duplicate()
	compact_state.erase("presentation")
	# All deltas start at the last exclusive handoff. Replacing an unread
	# packet can never lose an event, a fog cell, or a minimap marker.
	return {
		"state": compact_state, "packet": packet, "groups": groups, "speed": controller.get_speed_multiplier(),
		"events": controller.events_after(query["event_cursor"]),
		"fog": CacheDependency.changes(world, CacheDependency.FOG_VISIBILITY, query["fog_stamp"], team).duplicate(true),
		"markers": world.observer_memory.resource_marker_snapshot(world, team),
	}


func _publish_presentation(controller, query: Dictionary) -> Dictionary:
	if query.is_empty() or int(query["cached_tick"]) == controller.tick_index: return {}
	var world = controller.simulation_world
	var source = query["source"]
	var bounds: Rect2i = query["bounds"]
	var selected: Array = query["selected_ids"]
	# The same legal projection and immutable entity rows already retained by
	# presentation are produced here, before world ownership is handed back.
	# Do not copy the entire explored forest or send a live world to a worker.
	var full_scene := bool(query.get("full_scene", false))
	var scene_probe: Variant = controller.stage_observer if full_scene else null
	var snapshot: Dictionary = source.capture(world, controller.tick_index, int(query["team"]), selected, Rect2(Vector2(bounds.position), Vector2(bounds.size)), false, query["coordinator"], scene_probe, full_scene)
	world.entity_changes.flush()
	var packet := {"snapshot":snapshot,"tick":controller.tick_index,"team":int(query["team"]),"world_id":world.get_instance_id(),"epoch":int(world.entity_changes.epoch),"revision":int(world.entity_changes.revision),"bounds":bounds,"selected_ids":selected,"full_scene":full_scene}
	if full_scene and query.get("prediction_tail", false):
		var limits := {}
		var team := int(query["team"])
		for row in snapshot.get("render_units", snapshot["units"]):
			if int(row.get("team", 0)) != team or row.get("pos") == row.get("previous_pos"): continue
			var id := int(row["id"])
			var actor: Variant = world.find_unit(id)
			if actor == null: continue
			var limit := RenderWorld.final_waypoint_prediction_limit(actor, row)
			if limit >= 0.0: limits[id] = limit
		packet["prediction_limits"] = limits
	return packet
