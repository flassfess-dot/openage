extends RefCounted

const MAX_MESSAGE_BYTES := 2147483647
const JOB_TIMEOUT_USEC := 300000000
var kernel: Variant
var base := ""
var nonce := ""
var arguments: Array = []
var available := false
var seed_count := 0
var launched := false

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
	file.store_var({"seed":seed,"nonce":nonce},false)
	var error := file.get_error()
	file.close()
	if error != OK: clear();return false
	arguments = ["--headless","--audio-driver","Dummy","--log-file",base+".worker.log"]
	if not OS.has_feature("template"):
		arguments.append_array(["--path",ProjectSettings.globalize_path("res://"),"--script","res://scripts/autosave_process_entry.gd"])
	arguments.append_array(["--","--background-autosave-worker","--ipc-base="+base])
	available = true
	return true

func needs_reseed() -> bool:
	return launched and not kernel.background_process_running()

func run_job(input: Dictionary, cancel: Callable) -> Dictionary:
	if not kernel.background_process_running():
		if int(input.get("sent_from",-1))!=seed_count: return _failed("autosave_process_restart_required")
		for suffix in [".job",".job.tmp",".result",".result.tmp"]: _remove(suffix)
		var started: Dictionary = kernel.start_background_process(OS.get_executable_path(),arguments)
		if int(started.get("error",ERR_UNAVAILABLE)) != OK:
			var failed := _failed("autosave_process_start:%s" % started)
			failed["unavailable"]=true
			return failed
		launched=true
	var payload := input.duplicate(false)
	payload["ipc_nonce"] = nonce
	var error := write_message(base+".job",payload,kernel)
	if error != OK: return _failed("autosave_process_job:%d" % error)
	var deadline := Time.get_ticks_usec()+JOB_TIMEOUT_USEC
	while not bool(cancel.call()):
		if FileAccess.file_exists(base+".result"):
			var result := read_message(base+".result")
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
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null or file.get_length()<4 or file.get_length()>MAX_MESSAGE_BYTES: return {}
	var data: Variant=file.get_var(false)
	file.close()
	return data if data is Dictionary else {}
