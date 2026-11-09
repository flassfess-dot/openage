extends SceneTree

# Godot 4.7.2 remote profiler wire format, read from the matching engine tag:
# core/debugger/remote_debugger_peer.cpp; servers/debugger/servers_debugger.cpp.
# Loopback only. Collects actual gameplay; contains no test cases/assertions.
var server := TCPServer.new()
var peer: StreamPeerTCP
var received := PackedByteArray()
var signatures: Dictionary = {}
var aggregate: Dictionary = {}
var final_functions: Array = []
var messages: Dictionary = {}
var error_samples: Array = []
var compiler_warning_count := 0
var warning_overflow_count := 0
var runtime_error_count := 0
var runtime_error_samples: Array = []
var boundary_frames: Array = []
var frames: Array = []
var output := ""
var main_thread := -1
var ready_at := -1
var started_at := -1
var stopped_at := -1
var finished := false
var last_error := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if output.is_empty() or server.listen(26071, "127.0.0.1") != OK:
		push_error("Profiler collector cannot listen or output is missing")
		quit(1)
		return
	var f := FileAccess.open(output + ".ready", FileAccess.WRITE)
	f.store_string(str(OS.get_process_id()))
	print("LISTENING 127.0.0.1:26071")

func _process(_delta: float) -> bool:
	if peer == null:
		if server.is_connection_available():
			peer = server.take_connection()
			peer.big_endian = false
		return false
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if not finished: return _fail("Gameplay disconnected before final profile")
		finish() # Include diagnostics emitted after profiling was stopped.
		quit(0)
		return false
	var available := peer.get_available_bytes()
	if available > 0:
		var data := peer.get_data(available)
		if int(data[0]) != OK: return _fail("Socket read failed")
		received.append_array(data[1])
	while received.size() >= 4:
		var size := received.decode_u32(0)
		if size > 8 * 1024 * 1024: return _fail("Oversized debugger packet")
		if received.size() < size + 4: break
		var packet: Variant = bytes_to_var(received.slice(4, size + 4))
		received = received.slice(size + 4)
		if not packet is Array or packet.size() != 3: return _fail("Malformed debugger envelope")
		_message(packet)
	var now := Time.get_ticks_msec()
	if ready_at >= 0 and started_at < 0 and now - ready_at >= 10000:
		_send("profiler:servers", [true, [512, false]])
		started_at = now
		print("SCRIPT PROFILE START")
	if started_at >= 0 and stopped_at < 0 and now - started_at >= 20000:
		_send("profiler:servers", [false])
		stopped_at = now
		print("SCRIPT PROFILE STOP")
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if not finished: return _fail("Gameplay disconnected before final profile")
		quit(0)
	return false

func _send(command: String, arguments: Array) -> void:
	var payload := var_to_bytes([command, main_thread, arguments])
	peer.put_u32(payload.size())
	peer.put_data(payload)

func _message(packet: Array) -> void:
	var name := String(packet[0])
	var data: Array = packet[2]
	messages[name] = int(messages.get(name, 0)) + 1
	if name == "output":
		if var_to_str(data).contains("READY tick=") and ready_at < 0:
			main_thread = int(packet[1])
			ready_at = Time.get_ticks_msec()
			print("GAMEPLAY READY thread=", main_thread)
	elif name == "error":
		if error_samples.size() < 16: error_samples.append(data)
		if data.size() > 9 and String(data[7]) == "TOO_MANY_WARNINGS":
			warning_overflow_count += 1
		elif data.size() > 9 and bool(data[9]):
			compiler_warning_count += 1
		else:
			runtime_error_count += 1
			if runtime_error_samples.size() < 16: runtime_error_samples.append(data)
	elif name == "servers:function_signature":
		signatures[int(data[1])] = String(data[0])
	elif name == "servers:profile_frame" or name == "servers:profile_total":
		var rows := _functions(data)
		if name == "servers:profile_total":
			final_functions = rows
			finish()
		else:
			# Function calls already running at profiling_start have no start
			# timestamp. Retain the transition evidence but aggregate only after
			# one second, allowing the active owner step to leave that boundary.
			var include := Time.get_ticks_msec() >= started_at + 1000
			if frames.size() < 4096: frames.append({"frame":data[0],"frame_seconds":data[1],"script_seconds":data[5],"included":include})
			if not include:
				if boundary_frames.size() < 32: boundary_frames.append({"frame":data[0],"functions":rows})
				return
			for row in rows:
				var signature := String(row["signature"])
				if not aggregate.has(signature): aggregate[signature] = {"signature":signature,"calls":0,"self_seconds":0.0,"total_seconds":0.0}
				aggregate[signature]["calls"] += row["calls"]
				aggregate[signature]["self_seconds"] += row["self_seconds"]
				aggregate[signature]["total_seconds"] += row["total_seconds"]

func _functions(data: Array) -> Array:
	var cursor := 7
	for _server in range(int(data[6])):
		var slots := int(data[cursor + 1])
		cursor += 2 + slots
	var slots := int(data[cursor])
	cursor += 1
	var result: Array = []
	for offset in range(0, slots, 5):
		var id := int(data[cursor + offset])
		result.append({"signature":signatures.get(id, str(id)),"calls":data[cursor+offset+1],"self_seconds":data[cursor+offset+2],"total_seconds":data[cursor+offset+3],"internal_seconds":data[cursor+offset+4]})
	return result

func finish() -> void:
	finished = true
	var rows := aggregate.values()
	rows.sort_custom(func(a, b): return a["self_seconds"] > b["self_seconds"])
	final_functions.sort_custom(func(a, b): return a["self_seconds"] > b["self_seconds"])
	var f := FileAccess.open(output, FileAccess.WRITE)
	f.store_string(JSON.stringify({"ready_at_ms":ready_at,"started_at_ms":started_at,"stopped_at_ms":stopped_at,"messages":messages,"error_samples":error_samples,"compiler_warning_count":compiler_warning_count,"warning_overflow_count":warning_overflow_count,"runtime_error_count":runtime_error_count,"runtime_error_samples":runtime_error_samples,"boundary_frames":boundary_frames,"aggregate_warmup_ms":1000,"frame_aggregate":rows,"accumulated":final_functions,"accumulated_note":"Contains boundary-spanning calls; prefer warmed frame_aggregate.","frames":frames,"error":last_error}, "\t"))
	print("PROFILE WRITTEN functions=", final_functions.size(), " frames=", frames.size())

func _fail(reason: String) -> bool:
	last_error = reason
	push_error(reason)
	quit(1)
	return false
