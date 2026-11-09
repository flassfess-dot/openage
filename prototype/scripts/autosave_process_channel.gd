extends RefCounted
const SeedTransport := preload("res://scripts/autosave_seed_transport.gd")

const MAX_MESSAGE_BYTES := 2147483647
const JOB_TIMEOUT_USEC := 300000000
const MESSAGE_READ_RETRY_USEC := 1000000
var kernel: Variant
var base := ""
var nonce := ""
var arguments: Array = []
var available := false
var seed_count := 0
var launched := false
var launch_count := 0

func supported() -> bool:
	if not ClassDB.class_exists("RoRSaveFileKernel"): return false
	if kernel == null: kernel=ClassDB.instantiate("RoRSaveFileKernel")
	return kernel.has_method("background_process_supported") and kernel.background_process_supported()

func prepare(seed: Dictionary, stage: String, recorded_count: int) -> bool:
	seed_count=recorded_count
	if not supported(): return false
	base = ProjectSettings.globalize_path(stage)
	nonce = stage.get_file()+":"+str(Time.get_ticks_usec())
	# Loading work only: no large seed encoding or copy runs during a match.
	if DirAccess.make_dir_recursive_absolute(base.get_base_dir()) != OK: return false
	var file := FileAccess.open(base+".seed",FileAccess.WRITE)
	if file == null: return false
	var envelope := SeedTransport.encode(seed)
	envelope["nonce"] = nonce
	file.store_var(envelope,false)
	var error := file.get_error()
	file.close()
	if error != OK: clear();return false
	arguments = ["--headless","--audio-driver","Dummy","--log-file",base+".worker.log"]
	if not OS.has_feature("template"):
		arguments.append_array(["--path",ProjectSettings.globalize_path("res://"),"--script","res://scripts/autosave_process_entry.gd"])
	arguments.append_array(["--","--background-autosave-worker","--ipc-base="+base])
	if "--profile-save-memory" in OS.get_cmdline_user_args(): arguments.append("--profile-save-memory")
	if "--compare-actor-owner-replay" in OS.get_cmdline_user_args(): arguments.append("--compare-actor-owner-replay")
	if "--compare-combat-awareness-owner-replay" in OS.get_cmdline_user_args(): arguments.append("--compare-combat-awareness-owner-replay")
	available = true
	return true

func needs_reseed() -> bool:
	return launched and not kernel.background_process_running()

func run_job(input: Dictionary, cancel: Callable) -> Dictionary:
	if not kernel.background_process_running():
		if int(input.get("sent_from",-1))!=seed_count: return _failed("autosave_process_restart_required")
		for suffix in [".job",".job.tmp",".result",".result.tmp"]: _remove(suffix)
		if launched and "--profile-save-memory" in OS.get_cmdline_user_args() and FileAccess.file_exists(base+".worker.log"):
			var previous_log := base+".worker-%d.log" % (1+(launch_count-1)%2)
			if FileAccess.file_exists(previous_log): DirAccess.remove_absolute(previous_log)
			DirAccess.rename_absolute(base+".worker.log", previous_log)
		var started: Dictionary = kernel.start_background_process(OS.get_executable_path(),arguments)
		if int(started.get("error",ERR_UNAVAILABLE)) != OK:
			var failed := _failed("autosave_process_start:%s" % started)
			failed["unavailable"]=true
			return failed
		launched=true
		launch_count += 1
	var payload := input.duplicate(false)
	payload["ipc_nonce"] = nonce
	var error := write_message(base+".job",payload,kernel)
	if error != OK: return _failed("autosave_process_job:%d" % error)
	var deadline := Time.get_ticks_usec()+JOB_TIMEOUT_USEC
	var read_deadline := 0
	while not bool(cancel.call()):
		if FileAccess.file_exists(base+".result"):
			var message := read_message_result(base+".result")
			if not bool(message["valid"]):
				if read_deadline == 0: read_deadline = Time.get_ticks_usec() + MESSAGE_READ_RETRY_USEC
				if Time.get_ticks_usec() >= read_deadline: return _failed("autosave_process_result_read:%s" % message["detail"])
				OS.delay_msec(25)
				continue
			var result: Dictionary = message["data"]
			_remove(".result")
			if String(result.get("ipc_nonce","")) != nonce or int(result.get("tick",-1)) != int(input["tick"]) or int(result.get("sent_until",-1)) != int(input["sent_until"]): return _failed("autosave_process_result")
			result["transport_delivered"] = true
			result["worker_process_isolated"] = true
			return result
		if not kernel.background_process_running(): return _failed("autosave_process_exited")
		if Time.get_ticks_usec()>=deadline: return _failed("autosave_process_timeout")
		OS.delay_msec(25)
	return {"error":int(ERR_SKIP),"detail":"autosave_process_cancelled"}

func _failed(detail: String) -> Dictionary:
	kernel.stop_background_process()
	launched=false
	return {"error":int(ERR_CANT_CREATE),"detail":detail,"restart_from_seed":true}

func stop() -> void:
	if kernel != null and kernel.has_method("stop_background_process"): kernel.stop_background_process()

func _remove(suffix: String) -> void:
	if not base.is_empty() and FileAccess.file_exists(base+suffix): DirAccess.remove_absolute(base+suffix)

func clear() -> void:
	stop()
	for suffix in [".seed",".job",".job.tmp",".result",".result.tmp"]: _remove(suffix)
	available = false

static func write_message(path: String, data: Dictionary, native: Variant) -> int:
	var temporary := path+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_var(data,false)
	var error := file.get_error()
	file.close()
	if error != OK: return error
	return int(native.replace_atomic(temporary,path))

static func read_message(path: String) -> Dictionary:
	var message := read_message_result(path)
	return message["data"] if bool(message["valid"]) else {}

static func read_message_result(path: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"valid": false, "detail": "open:%d" % FileAccess.get_open_error()}
	var size := file.get_length()
	if size < 4 or size > MAX_MESSAGE_BYTES:
		file.close()
		return {"valid": false, "detail": "size:%d" % size}
	var data: Variant=file.get_var(false)
	var error := file.get_error()
	file.close()
	if not data is Dictionary or error != OK: return {"valid": false, "detail": "decode:%d:type:%d:size:%d" % [error, typeof(data), size]}
	return {"valid": true, "data": data, "size": size}
