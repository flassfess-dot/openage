extends Node
const Autosave := preload("res://scripts/background_autosave.gd")
const Channel := preload("res://scripts/autosave_process_channel.gd")
var base := ""
var nonce := ""
var service
var relay := Thread.new()
var relay_error := ""
var sent_until := 0
var last_sequence := 0

func _ready() -> void: call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ipc-base="): base=arg.trim_prefix("--ipc-base=")
	if not base.get_file().begins_with(".autosave-") or not base.ends_with(".pending"):
		get_tree().quit(1);return
	var envelope := Channel.read_message(base+".seed")
	if not envelope.get("seed") is Dictionary or String(envelope.get("nonce","")).is_empty():
		get_tree().quit(1);return
	nonce = envelope["nonce"]
	service = Autosave.new()
	service._seed = envelope["seed"]
	envelope = {}
	service._stage = base
	for record in service._seed["replay"].get("commands",[]): last_sequence=maxi(last_sequence,int(record.get("sequence_id",0)))
	if relay.start(_relay,Thread.PRIORITY_LOW)!=OK: get_tree().quit(1);return
	# The exact existing recovery loop owns one world and follows recorded
	# commands. No AI planning, rendering or shared gameplay pool is added.
	service._run()
	relay.wait_to_finish()
	if not relay_error.is_empty(): push_error(relay_error)
	get_tree().quit(0 if relay_error.is_empty() else 1)

func _relay() -> void:
	var native=ClassDB.instantiate("RoRSaveFileKernel")
	while not service._cancelled():
		if FileAccess.file_exists(base+".job"):
			var input := Channel.read_message(base+".job")
			DirAccess.remove_absolute(base+".job")
			if String(input.get("ipc_nonce",""))!=nonce or not input.get("new_commands") is Array:
				relay_error="autosave_process_invalid_job";_stop_service();break
			var records: Array=[]
			for record in input["new_commands"]:
				if int(record.get("sequence_id",0))>last_sequence:
					records.append(record)
					last_sequence=int(record["sequence_id"])
			input["new_commands"]=records
			sent_until=int(input.get("sent_until",0))
			service._mutex.lock()
			service._job=input
			service._mutex.unlock()
			service._wake.post()
			input = {}
		service._mutex.lock()
		var result: Dictionary=service._result
		service._result={}
		service._mutex.unlock()
		if not result.is_empty():
			result["ipc_nonce"]=nonce
			result["sent_until"]=sent_until
			if Channel.write_message(base+".result",result,native)!=OK:
				relay_error="autosave_process_result_write";_stop_service();break
		OS.delay_msec(25)

func _stop_service() -> void:
	service._mutex.lock()
	service._stop=true
	service._mutex.unlock()
	service._wake.post()
