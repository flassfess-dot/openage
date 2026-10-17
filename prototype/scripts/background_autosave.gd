extends RefCounted
# A private simulation follows the recorded commands from one detached loading
# checkpoint. Capturing/compressing the large world never runs in a game frame.
const World := preload("res://scripts/simulation_world.gd")
const Controller := preload("res://scripts/game_controller.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Checkpoint := preload("res://scripts/game_checkpoint.gd")
const Loading := preload("res://scripts/navigation_loading.gd")
const SaveTask := preload("res://scripts/background_save_task.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const INTERVAL_SECONDS := 60.0
const FIRST_SAVE_SECONDS := 15.0
const RECOVERY_SLICE_USEC := 2000
const RECOVERY_YIELD_USEC := 8000
var elapsed := 0.0
var next_save := FIRST_SAVE_SECONDS
var enabled := true
var busy := false
var last_error := ""
var last_tick := -1
var last_capture_us := 0
var last_worker_us := 0
var worker_pool_shared := true
var save_path := Archive.AUTOSAVE_PATH
var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _stop := false
var _seed: Dictionary = {}
var _job: Dictionary = {}
var _result: Dictionary = {}
var _stage := ""
var _sent_commands := 0

func seed_from(world, controller, definition: Dictionary, map: Dictionary, catalogs: Dictionary) -> void:
	shutdown()
	elapsed = 0.0
	next_save = FIRST_SAVE_SECONDS
	last_tick = -1
	last_error = ""
	# Loading work only. Every packed array, including learned navigation cells,
	# must be detached before the live match resumes.
	_seed = {"checkpoint": Checkpoint.capture(world, controller, definition, map), "catalogs": catalogs.duplicate(true), "replay": controller.replay_recorder.to_dictionary()}
	_sent_commands = controller.replay_recorder.issuance_records.size()
	_clean_abandoned_staging()
	_stage = save_path.get_base_dir().path_join(".autosave-%d-%d.pending" % [OS.get_process_id(), get_instance_id()])
	_stop = false
	var error := _thread.start(_run, Thread.PRIORITY_LOW)
	if error != OK:
		_seed = {}
		last_error = "autosave_thread:%d" % error
		push_warning(last_error)

func advance(delta: float, playable: bool) -> bool:
	if not enabled or not _thread.is_started() or not playable: return false
	elapsed += maxf(0.0, delta)
	return elapsed >= next_save and not busy

func submit(input: Dictionary, world, controller) -> bool:
	if busy or not _thread.is_started(): return false
	var started := Time.get_ticks_usec()
	var recorder = controller.replay_recorder
	input["new_commands"] = recorder.issuance_records.slice(_sent_commands).duplicate(true)
	input["anchor"] = state_anchor(world, controller)
	_sent_commands = recorder.issuance_records.size()
	last_capture_us = Time.get_ticks_usec() - started
	next_save = elapsed + INTERVAL_SECONDS
	_mutex.lock()
	_job = input
	busy = true
	_mutex.unlock()
	_wake.post()
	return true

func poll() -> Dictionary:
	_mutex.lock()
	var result := _result
	_result = {}
	_mutex.unlock()
	if result.is_empty(): return {}
	busy = false
	last_worker_us = int(result.get("worker_us", 0))
	worker_pool_shared = bool(result.get("worker_pool_shared", true))
	var error := int(result.get("error", ERR_INVALID_DATA))
	if error == OK: error = Archive.commit_autosave(_stage, save_path)
	if error == OK:
		last_tick = int(result["tick"])
		last_error = ""
	else:
		last_error = String(result.get("detail", "write_failed:%d" % error))
		next_save = elapsed + 10.0
		push_warning("Автосохранение: " + last_error)
	result["error"] = error
	result["path"] = save_path
	return result

func _cancelled() -> bool:
	_mutex.lock()
	var stopped := _stop
	_mutex.unlock()
	return stopped

func _run() -> void:
	# Do not allocate a second world until an autosave is actually due.
	_wake.wait()
	if _cancelled(): return
	var seed := _seed
	_seed = {}
	var data: Dictionary = seed["checkpoint"]
	var catalogs: Dictionary = seed["catalogs"]
	var world := World.new(data["world"]["map_size"], true)
	# Keep recovery work on this low-priority thread. It must not fan out into
	# the shared pool used by authoritative movement in the visible match.
	world.task_coordinator.enabled = false
	world.set_gamespec(catalogs["gamespec"])
	world.set_terrain_catalog(catalogs["terrain"], false)
	world.set_object_catalog(catalogs["objects"])
	world.set_graphics_catalog(catalogs["graphics"])
	world.set_runtime_catalog(catalogs["runtime"])
	var controller := Controller.new(world)
	controller.set_command_result_limit(1024)
	var valid := Checkpoint.restore(data, world, controller)
	var definition: Dictionary = data["match_definition"]
	var map: Dictionary = data["map_definition"]
	var history: Dictionary = seed["replay"]
	var preparation := Loading.new()
	preparation.coordinator.enabled = false
	# Loading also establishes durable fog/resource memory for AI observers.
	# Recovery must follow that contract even though its orders are recorded.
	preparation.begin(world, definition.get("players", []), false)
	var preparation_slice := Time.get_ticks_usec()
	while not preparation.poll(world) and not _cancelled():
		if Time.get_ticks_usec() - preparation_slice >= RECOVERY_SLICE_USEC:
			OS.delay_usec(RECOVERY_YIELD_USEC)
			preparation_slice = Time.get_ticks_usec()
	preparation.shutdown()
	# The durable fog/resource observation above is required for checkpoint
	# equality. Recovery never asks AI to plan, so release its derived views.
	world.ai_navigation_knowledge.clear()
	seed = {}
	data = {}
	var codec := Replay.new()
	var first := true
	while true:
		if not first: _wake.wait()
		first = false
		if _cancelled(): break
		_mutex.lock()
		var input := _job
		_job = {}
		_mutex.unlock()
		if input.is_empty(): continue
		var started := Time.get_ticks_usec()
		var target := int(input["tick"])
		var records: Array = input["new_commands"]
		history["commands"].append_array(records)
		history["commands"].sort_custom(func(a, b):
			if int(a["tick"]) != int(b["tick"]): return int(a["tick"]) < int(b["tick"])
			return int(a["sequence_id"]) < int(b["sequence_id"])
		)
		var cursor := 0
		var slice_started := Time.get_ticks_usec()
		while valid and controller.tick_index <= target and not _cancelled():
			while cursor < records.size() and int(records[cursor].get("issued_tick", 0)) <= controller.tick_index:
				controller.enqueue_command(codec.command_from_record(records[cursor]), false)
				cursor += 1
			if controller.tick_index == target: break
			valid = controller._run_fixed_tick(int(definition.get("local_team", 1)), 2)
			controller.event_stream.prune_through(controller.event_stream.latest_sequence())
			# Low OS priority alone cannot prevent allocator/cache contention
			# between two GDScript simulations. Leave regular gaps for the match.
			if Time.get_ticks_usec() - slice_started >= RECOVERY_SLICE_USEC:
				OS.delay_usec(RECOVERY_YIELD_USEC)
				slice_started = Time.get_ticks_usec()
		if _cancelled(): break
		var result := {"error": int(ERR_INVALID_DATA), "tick": target, "detail": "autosave_replay_mismatch"}
		if valid and input["anchor"] == state_anchor(world, controller):
			input["path"] = _stage
			input["atomic_replace"] = true
			input["replay"] = history
			input["checkpoint"] = Checkpoint.capture(world, controller, definition, map)
			result = SaveTask.run(input)
		result["worker_us"] = Time.get_ticks_usec() - started
		result["worker_pool_shared"] = world.task_coordinator.enabled
		# Release materialized checkpoint storage on the worker.
		input = {}
		_mutex.lock()
		_result = result
		_mutex.unlock()
	world.shutdown_derived_state()

static func state_anchor(world, controller) -> Dictionary:
	var actors: Array = []
	for list in [world.units, world.buildings, world.get_embarked_units()]:
		for entity in list:
			actors.append([entity.get("id"), entity.get("team"), entity.get("pos"), entity.get("hp"), entity.get("task"), entity.get("target_id"), entity.get("production_queue", []).duplicate(true)])
	return Replay.new().encode_variant({"tick": controller.tick_index, "rng": world.simulation_rng.state, "next_id": world.entity_id_sequence.peek(), "sequence": controller.next_command_sequence, "actors": actors, "stockpiles": world.economy_system.resource_stockpiles_by_team.duplicate(true), "over": world.battle_over})

func _clean_abandoned_staging() -> void:
	var directory := DirAccess.open(save_path.get_base_dir())
	if directory == null: return
	for filename in directory.get_files():
		if not filename.begins_with(".autosave-") or not (filename.ends_with(".pending") or filename.ends_with(".pending.tmp") or filename.ends_with(".pending.bak")): continue
		var pid := int(filename.trim_prefix(".autosave-").get_slice("-", 0))
		if pid > 0 and not OS.is_process_running(pid): directory.remove(filename)

func shutdown() -> void:
	if _thread.is_started():
		_mutex.lock()
		_stop = true
		_mutex.unlock()
		_wake.post()
		_thread.wait_to_finish()
	_thread = Thread.new()
	_wake = Semaphore.new()
	_seed = {}
	_job = {}
	_result = {}
	busy = false
	for suffix in ["", ".tmp", ".bak"]:
		if not _stage.is_empty() and FileAccess.file_exists(_stage + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(_stage + suffix))
