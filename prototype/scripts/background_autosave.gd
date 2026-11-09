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
const ProcessChannel := preload("res://scripts/autosave_process_channel.gd")
const Snapshot := preload("res://scripts/simulation_snapshot.gd")
const Lifecycle := preload("res://scripts/match_lifecycle_service.gd")
const DIGEST_SLICE_USEC := 2000
const INTERVAL_SECONDS := 60.0
const FIRST_SAVE_SECONDS := 15.0
const RECOVERY_SLICE_USEC := 2000
const RECOVERY_YIELD_USEC := 8000
var elapsed := 0.0
var next_save := FIRST_SAVE_SECONDS
var enabled := true
var busy := false
var last_error := ""
var last_diagnostic: Dictionary = {}
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
var _seed_command_count := 0
var _process_channel
var _process_fallback := false
var worker_process_isolated := false
var recovery_full_ai_views := false
var last_initialization_us := 0
var _capture_input: Dictionary = {}
var _capture_state: Dictionary = {}
var _capture_world: WeakRef
var _capture_job: Variant = null
var _capture_epoch := -1
# The isolated helper only stages a file; its parent service owns publication.
var defer_commit_to_parent := false
var _header_definition: Dictionary = {}

func seed_from(world, controller, definition: Dictionary, map: Dictionary, catalogs: Dictionary) -> void:
	shutdown()
	elapsed = 0.0
	next_save = FIRST_SAVE_SECONDS
	last_tick = -1
	last_error = ""
	last_diagnostic = {}
	last_initialization_us = 0
	# Loading work only. Every packed array, including learned navigation cells,
	# must be detached before the live match resumes.
	_process_channel = ProcessChannel.new()
	var process_available: bool = _process_channel.supported()
	_seed = {"checkpoint": Checkpoint.capture(world, controller, definition, map, not process_available), "catalogs": catalogs if process_available else catalogs.duplicate(true), "replay": controller.replay_recorder.to_dictionary(), "recovery_full_ai_views": recovery_full_ai_views}
	# Checkpoint.capture already detached this definition during loading. Retain
	# that immutable copy for owner-thread headers instead of borrowing the UI.
	_header_definition = _seed["checkpoint"]["match_definition"]
	_sent_commands = controller.replay_recorder.issuance_records.size()
	_seed_command_count = _sent_commands
	_clean_abandoned_staging()
	_stage = save_path.get_base_dir().path_join(".autosave-%d-%d.pending" % [OS.get_process_id(), get_instance_id()])
	_stop = false
	_process_fallback = false
	if process_available and _process_channel.prepare(_seed, _stage, _seed_command_count):
		_seed = {}
	else:
		if process_available:
			_seed["checkpoint"]=Checkpoint.capture(world,controller,definition,map)
			_seed["catalogs"]=catalogs.duplicate(true)
		_process_channel = null
	var error := _thread.start(_run_process if _process_channel != null else _run, Thread.PRIORITY_LOW)
	if error != OK:
		_seed = {}
		last_error = "autosave_thread:%d" % error
		push_warning(last_error)

func advance(delta: float, playable: bool) -> bool:
	if not enabled or not _thread.is_started() or not playable: return false
	elapsed += maxf(0.0, delta)
	return elapsed >= next_save and not busy

func submit(input: Dictionary, world, controller, deferred: bool = false) -> bool:
	if busy or not _thread.is_started(): return false
	var started := Time.get_ticks_usec()
	var recorder = controller.replay_recorder
	if _process_channel != null and not _process_fallback and _process_channel.needs_reseed(): _sent_commands=_seed_command_count
	input["sent_from"]=_sent_commands
	input["new_commands"] = recorder.issuance_records.slice(_sent_commands).duplicate(true)
	input["sent_until"] = recorder.issuance_records.size()
	next_save = elapsed + INTERVAL_SECONDS
	if deferred and ClassDB.class_exists("RoRResourceDigest"):
		_capture_input = input
		_capture_world = weakref(world)
		_capture_epoch = world.cache_epoch
		busy = true
	else:
		input["anchor"] = state_anchor(world, controller)
		_publish_capture(input)
	last_capture_us = Time.get_ticks_usec() - started
	return true


func _publish_capture(input: Dictionary) -> void:
	if _process_channel == null or _process_fallback: _sent_commands = int(input["sent_until"])
	_mutex.lock()
	_job = input
	busy = true
	_mutex.unlock()
	_wake.post()


func needs_owner_capture() -> bool:
	return not _capture_input.is_empty()


func supports_deferred_header() -> bool:
	return ClassDB.class_exists("RoRResourceDigest") and not _header_definition.is_empty()


func prepare_capture_on_owner(world, controller, runtime = null) -> void:
	if _capture_input.is_empty() or not _capture_state.is_empty(): return
	if _capture_world.get_ref() != world or world.cache_epoch != _capture_epoch or int(_capture_input["tick"]) != controller.tick_index or world.resource_digest_job != null:
		_fail_capture(world, "autosave_capture_generation_changed")
		return
	if bool(_capture_input.get("deferred_header", false)):
		if runtime == null:
			_fail_capture(world, "autosave_capture_owner_unavailable")
			return
		var request := _capture_input
		_capture_input = Lifecycle.new().capture_save_header(controller, runtime.players, runtime.decisions, request["path"], request["slot_name"], request["match_path"], _header_definition, request["view"], request["controller"], false)
		for field in ["sent_from", "sent_until", "new_commands"]: _capture_input[field] = request[field]
	var job: Variant = ClassDB.instantiate("RoRResourceDigest")
	if not job.begin(world.get_resources()):
		var input := _capture_input
		_capture_input = {}
		_capture_world = null
		input["anchor"] = state_anchor(world, controller)
		_publish_capture(input)
		return
	_capture_job = job
	world.resource_digest_job = job
	# This owner handoff is still exactly the header's source tick. Small
	# sections are consumed here; resources preserve it with before-write hashes.
	_capture_state = Snapshot.autosave_checksum_state(world, controller, true)
	if "--profile-autosave-capture" in OS.get_cmdline_user_args():
		for arg in OS.get_cmdline_user_args():
			if not arg.begins_with("--autosave-entity-diagnostics="): continue
			var records: Dictionary = {}
			for text_id in arg.trim_prefix("--autosave-entity-diagnostics=").split(","):
				if records.size() >= 64: break
				var entity: Variant = world.find_unit(int(text_id))
				if entity != null: records[int(text_id)] = entity.duplicate(true)
			_capture_input["debug_units"] = records


func advance_capture_on_owner(world, controller) -> void:
	if _capture_input.is_empty(): return
	if _capture_job == null:
		# Only the simulation owner starts the source-boundary capture. A UI
		# fallback must never inherit its potentially expensive first portion.
		_fail_capture(world, "autosave_capture_generation_changed" if int(_capture_input["tick"]) != controller.tick_index else "autosave_capture_owner_unavailable")
		return
	if _capture_world.get_ref() != world or world.cache_epoch != _capture_epoch or not is_same(world.resource_digest_job, _capture_job):
		_fail_capture(world, "autosave_capture_generation_changed")
		return
	if not _capture_job.advance(DIGEST_SLICE_USEC): return
	_capture_state["world"]["resources"] = _capture_job.take()
	world.resource_digest_job = null
	var input := _capture_input
	input["anchor"] = {"version": 2, "state_sha256": Snapshot.finish_autosave_checksum(_capture_state)}
	if "--profile-autosave-capture" in OS.get_cmdline_user_args(): input["debug_hash_sections"] = _capture_state
	_clear_capture()
	_publish_capture(input)


func _clear_capture() -> void:
	if _capture_job != null: _capture_job.cancel()
	var world = _capture_world.get_ref() if _capture_world != null else null
	if world != null and is_same(world.resource_digest_job, _capture_job): world.resource_digest_job = null
	_capture_job = null
	_capture_world = null
	_capture_input = {}
	_capture_state = {}
	_capture_epoch = -1


func _fail_capture(_world, detail: String) -> void:
	var tick := int(_capture_input.get("tick", -1))
	_clear_capture()
	_mutex.lock()
	_result = {"error": int(ERR_INVALID_DATA), "tick": tick, "detail": detail}
	_mutex.unlock()

func poll() -> Dictionary:
	_mutex.lock()
	var result := _result
	_result = {}
	_mutex.unlock()
	if result.is_empty(): return {}
	if result.has("diagnostic"): last_diagnostic = result["diagnostic"]
	busy = false
	if bool(result.get("restart_from_seed",false)): _sent_commands = _seed_command_count
	elif bool(result.get("transport_delivered",false)): _sent_commands = int(result["sent_until"])
	worker_process_isolated = bool(result.get("worker_process_isolated",false))
	last_initialization_us = int(result.get("initialization_us", 0))
	last_worker_us = int(result.get("worker_us", 0))
	worker_pool_shared = bool(result.get("worker_pool_shared", true))
	var error := int(result.get("error", ERR_INVALID_DATA))
	if error == OK and not bool(result.get("committed", false)): error = ERR_INVALID_DATA
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


func _commit_result(result: Dictionary) -> void:
	if int(result.get("error", ERR_INVALID_DATA)) != OK: return
	if _cancelled():
		result["error"] = int(ERR_SKIP)
		result["detail"] = "autosave_cancelled"
		return
	# Atomic rename can wait for filesystem/antivirus I/O. It belongs to this
	# save thread, just like encoding and writing, never to the render frame.
	result["error"] = int(Archive.commit_autosave(_stage, save_path))
	result["committed"] = int(result["error"]) == OK

func _run_process() -> void:
	while true:
		_wake.wait()
		if _cancelled(): break
		_mutex.lock()
		var input := _job
		_job = {}
		_mutex.unlock()
		if input.is_empty(): continue
		var started := Time.get_ticks_usec()
		var result: Dictionary = _process_channel.run_job(input,_cancelled)
		if _cancelled(): break
		# A platform/job restriction preserves the existing thread fallback.
		if bool(result.get("unavailable",false)):
			var seed_message := ProcessChannel.read_message(_stage+".seed")
			if seed_message.get("seed") is Dictionary:
				_seed=seed_message["seed"]
				_mutex.lock()
				_process_fallback=true
				_sent_commands=int(input["sent_until"])
				_job=input
				_mutex.unlock()
				_wake.post()
				_run()
				break
		_commit_result(result)
		result["worker_us"]=Time.get_ticks_usec()-started
		result["worker_pool_shared"]=false
		_mutex.lock()
		_result=result
		_mutex.unlock()
	_process_channel.stop()

func _run() -> void:
	# Do not allocate a second world until an autosave is actually due.
	_wake.wait()
	if _cancelled(): return
	var initialization_started := Time.get_ticks_usec()
	var profile_memory := "--profile-save-memory" in OS.get_cmdline_user_args()
	if profile_memory: print("AUTOSAVE recovery begin heap=", OS.get_static_memory_usage(), " memory=", OS.get_memory_info())
	var seed := _seed
	_seed = {}
	var data: Dictionary = seed["checkpoint"]
	var catalogs: Dictionary = seed["catalogs"]
	var world := World.new(data["world"]["map_size"], true)
	# Diagnostic comparison: the visible match may use the complete native
	# actor coordinator, while this recorded-command recovery uses the shared
	# reference stages. The normal save anchor compares their durable state.
	if "--compare-actor-owner-replay" in OS.get_cmdline_user_args():
		world.movement_system.full_actor_pipeline_enabled = false
		world.movement_system.common_movement_pipeline_enabled = false
		print("AUTOSAVE reference actor pipeline native=", world.movement_system.full_actor_pipeline_enabled, " common=", world.movement_system.common_movement_pipeline_enabled)
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
	if "--compare-combat-awareness-owner-replay" in OS.get_cmdline_user_args():
		controller.combat_awareness.native_awareness_enabled = false
		print("AUTOSAVE reference combat awareness native=false")
	if profile_memory: print("AUTOSAVE restored valid=", valid, " heap=", OS.get_static_memory_usage())
	var definition: Dictionary = data["match_definition"]
	var map: Dictionary = data["map_definition"]
	var history: Dictionary = seed["replay"]
	var preparation := Loading.new()
	preparation.coordinator.enabled = false
	preparation.prepare_ai_views = bool(seed.get("recovery_full_ai_views", false))
	# The restored world and retained match/replay roots own everything needed
	# below. Release the source checkpoint and raw catalogs before allocating
	# navigation/visibility views, rather than at the end of their preparation.
	seed = {}
	data = {}
	catalogs = {}
	if profile_memory: print("AUTOSAVE source released heap=", OS.get_static_memory_usage())
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
	if profile_memory: print("AUTOSAVE recovery ready us=", Time.get_ticks_usec() - initialization_started, " heap=", OS.get_static_memory_usage())
	var initialization_us := Time.get_ticks_usec() - initialization_started
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
		var actual_state := Snapshot.autosave_checksum_state(world, controller) if valid else {}
		var actual_anchor := {"version": 2, "state_sha256": Snapshot.finish_autosave_checksum(actual_state)} if valid else {}
		if profile_memory:
			print("AUTOSAVE replay actor state ", JSON.stringify({"tick":controller.tick_index,"actor_calls":world.movement_system.full_actor_pipeline_counters.get("actors",0),"gather_controller_calls":world.movement_system.full_actor_pipeline_counters.get("gather_controller_calls",0),"gather_controller_enabled":world.movement_system.ordered_gather_controller_enabled,"combat_awareness_enabled":controller.combat_awareness.native_awareness_enabled,"combat_awareness_calls":controller.combat_awareness.native_awareness_stats.get("calls",0),"native_read_index":world.entity_read_index.uses_native(),"read_index_stats":world.entity_read_index.native_index.stats() if world.entity_read_index.native_index != null else {},"observer_fog_batch":world.fog_of_war.native_observer_batch_enabled,"observer_fog_batch_calls":world.fog_of_war.observer_batch_calls,"typed_motion_frame":world.movement_system.integration_kernel.typed_motion_stats() if world.movement_system.integration_kernel != null and world.movement_system.integration_kernel.has_method("typed_motion_stats") else {}}))
		if valid and input["anchor"] == actual_anchor:
			if profile_memory:
				print("AUTOSAVE entity journal state ", JSON.stringify({"active":world.entity_changes.native_active,"stats":world.entity_changes.native_journal.stats() if world.entity_changes.native_active else {}}))
				print("AUTOSAVE route preparation state ", JSON.stringify({"enabled":world.movement_system.native_route_preparation_requested,"calls":world.movement_system.full_actor_pipeline_counters.get("route_preparation_calls",0),"fallbacks":world.movement_system.full_actor_pipeline_counters.get("route_preparation_fallbacks",0),"region_reads":world.movement_system.full_actor_pipeline_counters.get("route_region_reads",0)}))
			input["path"] = _stage
			input["atomic_replace"] = true
			input["replay"] = history
			input["checkpoint"] = Checkpoint.capture(world, controller, definition, map, false)
			result = SaveTask.run(input)
		elif valid and input.get("debug_hash_sections") is Dictionary:
			var mismatch: Array = []
			var diagnostic: Dictionary = {}
			for section in ["world", "controller"]:
				var expected: Dictionary = input["debug_hash_sections"][section]
				for field in expected:
					if expected[field] == actual_state[section][field]: continue
					var key := "%s.%s" % [section, field]
					mismatch.append(key)
					var before: Variant = expected[field]
					var after: Variant = actual_state[section][field]
					if before is PackedInt64Array and after is PackedInt64Array:
						var old: Dictionary = {}
						for index in range(0, before.size()-1, 2): old[int(before[index])] = int(before[index+1])
						var ids: Array = []
						for index in range(0, after.size()-1, 2):
							var id := int(after[index])
							if old.get(id) != int(after[index+1]) and ids.size() < 64: ids.append(id)
							old.erase(id)
						for id in old:
							if ids.size() < 64: ids.append(int(id))
						diagnostic[key] = {"different_entity_ids":ids,"expected_count":before.size()/2,"actual_count":after.size()/2}
					else: diagnostic[key] = {"expected":before,"actual":after}
			result["diagnostic"] = diagnostic
			if input.get("debug_units") is Dictionary:
				var fields: Dictionary = {}
				for id in input["debug_units"]:
					var actual: Variant = world.find_unit(int(id))
					if actual == null: continue
					var differences: Array = []
					_diagnose_fields(input["debug_units"][id], actual, "", differences, 0)
					if not differences.is_empty(): fields[str(id)] = differences
				diagnostic["unit_fields"] = fields
			result["detail"] = "autosave_replay_mismatch:" + ",".join(mismatch)
		if not defer_commit_to_parent: _commit_result(result)
		result["worker_us"] = Time.get_ticks_usec() - started
		result["initialization_us"] = initialization_us
		result["worker_pool_shared"] = world.task_coordinator.enabled
		# Release materialized checkpoint storage on the worker.
		input = {}
		_mutex.lock()
		_result = result
		_mutex.unlock()
	world.shutdown_derived_state()


static func _diagnose_fields(before: Variant, after: Variant, path: String, result: Array, depth: int) -> void:
	if result.size() >= 128: return
	if typeof(before) == typeof(after) and before == after and hash(before) == hash(after): return
	if before is Dictionary and after is Dictionary and depth < 6:
		var keys: Array = before.keys()
		for key in after:
			if not before.has(key): keys.append(key)
		var count := result.size()
		for key in keys:
			if path.is_empty() and String(key) in ["selected","formation_shared_motion","_formation_path_cache","formation_steering_target","formation_shared_isolated"]: continue
			_diagnose_fields(before.get(key), after.get(key), String(key) if path.is_empty() else path+"."+String(key), result, depth+1)
		if count == result.size() and before.keys() != after.keys(): result.append({"field":path+".key_order","expected":before.keys(),"actual":after.keys()})
		return
	var entry := {"field":path,"expected_type":typeof(before),"actual_type":typeof(after),"expected":str(before).left(600),"actual":str(after).left(600)}
	if before is Vector2 or before is float or before is int: entry["expected_bytes"] = var_to_bytes(before).hex_encode()
	if after is Vector2 or after is float or after is int: entry["actual_bytes"] = var_to_bytes(after).hex_encode()
	result.append(entry)

static func state_anchor(world, controller) -> Dictionary:
	return {"version": 2, "state_sha256": preload("res://scripts/simulation_snapshot.gd").autosave_checksum(world, controller)}

func _clean_abandoned_staging() -> void:
	var directory := DirAccess.open(save_path.get_base_dir())
	if directory == null: return
	for filename in directory.get_files():
		if not filename.begins_with(".autosave-") or not [".pending",".pending.tmp",".pending.bak",".pending.seed",".pending.job",".pending.job.tmp",".pending.result",".pending.result.tmp",".pending.worker.log"].any(func(suffix):return filename.ends_with(suffix)): continue
		var pid := int(filename.trim_prefix(".autosave-").get_slice("-", 0))
		if pid > 0 and not OS.is_process_running(pid): directory.remove(filename)

func shutdown() -> void:
	_clear_capture()
	_header_definition = {}
	if _thread.is_started():
		_mutex.lock()
		_stop = true
		_mutex.unlock()
		_wake.post()
		_thread.wait_to_finish()
	if _process_channel != null: _process_channel.clear()
	_process_channel=null
	worker_process_isolated=false
	_thread = Thread.new()
	_wake = Semaphore.new()
	_seed = {}
	_job = {}
	_result = {}
	busy = false
	for suffix in ["", ".tmp", ".bak"]:
		if not _stage.is_empty() and FileAccess.file_exists(_stage + suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(_stage + suffix))
