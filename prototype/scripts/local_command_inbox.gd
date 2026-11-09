extends RefCounted
## One producer (input) and one consumer (the current simulation owner).
## Only the owner assigns sequence numbers and records commands for replay.
const MAX_PENDING := 4096
const MAX_SAMPLES := 64
var pending: Array[Dictionary] = []
# The owner appends receipts before publishing the corresponding events.
var receipts: Array[Dictionary] = []
var mutex := Mutex.new()
# Feedback stays on the main thread even when the command has already arrived.
var by_command: Dictionary = {}
var samples: Array[Dictionary] = []
var samples_by_sequence: Dictionary = {}
var stats := {"queued":0,"delivered":0,"retargeted":0,"capacity_rejections":0,"peak_pending":0,"max_wait_us":0,"sampled_accepted":0,"sampled_rejected":0}

func clear() -> void:
	mutex.lock()
	pending.clear()
	receipts.clear()
	mutex.unlock()
	by_command.clear()
	samples.clear()
	samples_by_sequence.clear()
	for key in stats: stats[key] = 0

func enqueue(command) -> bool:
	if by_command.size() >= MAX_PENDING:
		stats["capacity_rejections"] += 1
		return false
	var id: int = command.get_instance_id()
	var row := {"command":command,"id":id,"received_us":Time.get_ticks_usec(),"requested_tick":int(command.tick)}
	by_command[id] = {}
	mutex.lock()
	pending.append(row)
	mutex.unlock()
	stats["queued"] += 1
	stats["peak_pending"] = maxi(stats["peak_pending"], by_command.size())
	return true

func register_feedback(command, message: String, sound: String, marker: Variant) -> bool:
	var id: int = command.get_instance_id()
	if not by_command.has(id): return false
	by_command[id] = {"message":message,"sound":sound,"marker":marker}
	return true

func receive_on_owner(controller, team: int) -> void:
	mutex.lock()
	if pending.is_empty():
		mutex.unlock()
		return
	var deliveries := pending
	pending = []
	mutex.unlock()
	for row in deliveries:
		var command = row["command"]
		command.tick = maxi(int(row["requested_tick"]), controller.tick_index + 1)
		controller.enqueue_command(command, true, team)
		if controller.local_publication_tick < 0 or command.tick < controller.local_publication_tick:
			controller.local_publication_tick = command.tick
		row["wait_us"] = Time.get_ticks_usec() - int(row["received_us"])
	mutex.lock()
	receipts.append_array(deliveries)
	mutex.unlock()

func deliver(controller, team: int, feedback_router) -> void:
	receive_on_owner(controller, team)
	deliver_receipts(feedback_router)

func deliver_receipts(feedback_router) -> void:
	mutex.lock()
	var arrived := receipts
	receipts = []
	mutex.unlock()
	for row in arrived:
		var command = row["command"]
		var feedback: Dictionary = by_command.get(row["id"], {})
		if not feedback.is_empty():
			feedback_router.register(command, feedback["message"], feedback["sound"], feedback["marker"])
		by_command.erase(row["id"])
		var waited := int(row["wait_us"])
		stats["delivered"] += 1
		if int(command.tick) != int(row["requested_tick"]): stats["retargeted"] += 1
		stats["max_wait_us"] = maxi(stats["max_wait_us"], waited)
		if samples.size() < MAX_SAMPLES:
			var sample := {"type":command.command_type(),"tick":int(command.tick),"sequence":int(command.sequence_id),"wait_us":waited,"outcome":"pending"}
			samples.append(sample)
			samples_by_sequence[int(command.sequence_id)] = sample

func observe_results(events: Array, team: int) -> void:
	if samples_by_sequence.is_empty(): return
	for event in events:
		var kind := String(event.get("type", ""))
		if kind not in ["command_accepted", "command_rejected"]: continue
		var payload: Dictionary = event.get("payload", {})
		if int(payload.get("issuer_id", 0)) != team: continue
		var sequence := int(payload.get("sequence_id", 0))
		var sample: Dictionary = samples_by_sequence.get(sequence, {})
		if sample.is_empty(): continue
		sample["outcome"] = kind
		sample["reason"] = String(payload.get("reason", ""))
		stats["sampled_accepted" if kind == "command_accepted" else "sampled_rejected"] += 1
		samples_by_sequence.erase(sequence)

func report() -> Dictionary:
	var result := stats.duplicate()
	result["pending"] = by_command.size()
	result["samples"] = samples.duplicate(true)
	return result
