class_name RoRLockstepSession
extends RefCounted

const ReplaySystem := preload("res://scripts/replay_system.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")

const PROTOCOL_VERSION := 1
const MAX_PLAYERS := 8
const MAX_FRAME_COMMANDS := 128
const MAX_FRAME_LEAD := 120
const MAX_CHAT_LENGTH := 256
const MAX_CHAT_HISTORY := 100
const MAX_HASH_CHECKPOINTS := 128

var controller
var local_team: int = 0
var teams: Array[int] = []
var simulation_seed: int = 0
var match_fingerprint: String = ""
var hash_interval: int = 40
var phase := "unconfigured"
var last_error := ""
var first_divergence: Dictionary = {}
var ready_teams: Dictionary = {}
var frames: Dictionary = {}
var local_hashes: Dictionary = {}
var remote_hashes: Dictionary = {}
var chat_messages: Array[Dictionary] = []
var codec := ReplaySystem.new()


func configure(requested_controller, definition: Dictionary, seed: int, participant_teams: Array[int], requested_local_team: int, requested_hash_interval: int = 40) -> String:
	if requested_controller == null or requested_controller.simulation_world == null:
		return "controller_missing"
	var sorted_teams := participant_teams.duplicate()
	sorted_teams.sort()
	if sorted_teams.size() < 2 or sorted_teams.size() > MAX_PLAYERS or sorted_teams.any(func(team): return int(team) <= 0) or _has_duplicate_teams(sorted_teams):
		return "participants_invalid"
	if requested_local_team != 0 and requested_local_team not in sorted_teams:
		return "local_team_invalid"
	if seed <= 0:
		return "seed_invalid"
	controller = requested_controller
	local_team = requested_local_team
	teams = sorted_teams
	simulation_seed = seed
	match_fingerprint = GameSaveArchive.fingerprint(definition)
	hash_interval = maxi(1, requested_hash_interval)
	phase = "handshake"
	last_error = ""
	first_divergence.clear()
	ready_teams.clear()
	frames.clear()
	local_hashes.clear()
	remote_hashes.clear()
	chat_messages.clear()
	if local_team > 0:
		ready_teams[local_team] = true
	controller.set_speed_multiplier(1.0)
	controller.start_recording(seed, false)
	return ""


func hello_packet() -> Dictionary:
	if phase not in ["handshake", "running"]:
		return {}
	return {
		"kind": "hello", "protocol_version": PROTOCOL_VERSION,
		"replay_version": ReplaySystem.FORMAT_VERSION,
		"sender_team": local_team, "role": "spectator" if local_team == 0 else "player",
		"teams": teams.duplicate(), "seed": simulation_seed, "hash_interval": hash_interval,
		"match_fingerprint": match_fingerprint,
	}


func receive_packet(packet: Dictionary) -> String:
	if phase == "aborted":
		return last_error
	match String(packet.get("kind", "")):
		"hello": return _receive_hello(packet)
		"frame": return _receive_frame(packet)
		"hash": return _receive_hash(packet)
		"chat": return _receive_chat(packet)
		"abort":
			if int(packet.get("protocol_version", -1)) != PROTOCOL_VERSION or int(packet.get("sender_team", -1)) not in teams:
				return "abort_sender_invalid"
			_abort("peer_aborted:%d" % int(packet.get("sender_team", -1)))
			return last_error
		_: return "packet_kind_invalid"


func frame_packet(tick: int, commands: Array) -> Dictionary:
	if phase != "running" or local_team <= 0 or tick <= int(controller.tick_index) or tick > int(controller.tick_index) + MAX_FRAME_LEAD or commands.size() > MAX_FRAME_COMMANDS:
		return {}
	var records: Array = []
	for command in commands:
		if command == null or int(command.tick) != tick:
			return {}
		if String(command.command_type()) == "population_limit" and local_team != teams[0]:
			return {}
		records.append({"type": String(command.command_type()), "unit_ids": command.unit_ids.duplicate(), "params": codec.encode_variant(command.params)})
	var packet := {"kind": "frame", "protocol_version": PROTOCOL_VERSION, "sender_team": local_team, "tick": tick, "commands": records}
	if not _receive_frame(packet).is_empty():
		return {}
	return packet


func can_advance() -> bool:
	if phase != "running":
		return false
	var next_tick := int(controller.tick_index) + 1
	var tick_frames: Dictionary = frames.get(next_tick, {})
	return teams.all(func(team): return tick_frames.has(int(team)))


func advance_one() -> Dictionary:
	if not can_advance():
		return {"advanced": false, "reason": "frame_missing"}
	var tick := int(controller.tick_index) + 1
	var tick_frames: Dictionary = frames[tick]
	var local_sequence_ids: Array[int] = []
	for team in teams:
		var frame: Dictionary = tick_frames[team]
		for record_value in frame.get("commands", []):
			var record: Dictionary = record_value.duplicate(true)
			record["tick"] = tick
			record["issuer_id"] = team
			record["sequence_id"] = 0
			var command = codec.command_from_record(record)
			if command == null:
				_abort("command_decode_failed:%d:%d" % [team, tick])
				return {"advanced": false, "reason": last_error}
			controller.enqueue_command(command, true, team)
			if team == local_team:
				local_sequence_ids.append(int(command.sequence_id))
	frames.erase(tick)
	controller.advance_frame(controller.FIXED_STEP_SECONDS, teams[0], teams[1])
	if int(controller.tick_index) != tick:
		_abort("fixed_tick_failed:%d" % tick)
		return {"advanced": false, "reason": last_error}
	var result := {"advanced": true, "tick": tick, "hash_packet": {}, "local_sequence_ids": local_sequence_ids}
	if tick % hash_interval == 0:
		var digest: String = codec.world_state_hash(controller.simulation_world, tick, controller)
		local_hashes[tick] = digest
		_prune_hash_history(tick)
		if local_team > 0:
			result["hash_packet"] = {"kind": "hash", "protocol_version": PROTOCOL_VERSION, "sender_team": local_team, "tick": tick, "sha256": digest}
		_check_hashes_at(tick)
	return result


func chat_packet(message: String, channel: String = "allies") -> Dictionary:
	if phase != "running" or local_team <= 0 or channel not in ["allies", "all"] or message.is_empty() or message.length() > MAX_CHAT_LENGTH:
		return {}
	var recipients: Array[int] = []
	for team in teams:
		if channel == "all" or (controller.simulation_world.are_teams_allied(local_team, team) and controller.simulation_world.are_teams_allied(team, local_team)):
			recipients.append(team)
	return {"kind": "chat", "protocol_version": PROTOCOL_VERSION, "sender_team": local_team, "channel": channel, "recipients": recipients, "text": message}


func abort_packet(reason: String) -> Dictionary:
	_abort(reason)
	return {"kind": "abort", "protocol_version": PROTOCOL_VERSION, "sender_team": local_team, "reason": reason}


func peer_disconnected(team: int) -> String:
	if phase == "aborted":
		return last_error
	if team not in teams:
		return "disconnect_sender_invalid"
	_abort("peer_disconnected:%d" % team)
	return last_error


func _receive_hello(packet: Dictionary) -> String:
	if phase not in ["handshake", "running"]:
		return "handshake_unavailable"
	var sender := int(packet.get("sender_team", -1))
	var announced_teams: Variant = packet.get("teams")
	if int(packet.get("protocol_version", -1)) != PROTOCOL_VERSION or int(packet.get("replay_version", -1)) != ReplaySystem.FORMAT_VERSION or int(packet.get("seed", -1)) != simulation_seed or int(packet.get("hash_interval", -1)) != hash_interval or String(packet.get("match_fingerprint", "")) != match_fingerprint or _normalized_wire_value(announced_teams) != _normalized_wire_value(teams):
		_abort("handshake_mismatch:%d" % sender)
		return last_error
	if sender == 0 and String(packet.get("role", "")) == "spectator":
		if int(controller.tick_index) > 0:
			return "late_spectator_unsupported"
		return ""
	if sender not in teams or String(packet.get("role", "")) != "player":
		return "handshake_sender_invalid"
	ready_teams[sender] = true
	if teams.all(func(team): return ready_teams.has(int(team))):
		phase = "running"
	return ""


func _receive_frame(packet: Dictionary) -> String:
	if phase != "running":
		return "session_not_running"
	var sender := int(packet.get("sender_team", -1))
	var tick := int(packet.get("tick", -1))
	var records: Variant = packet.get("commands")
	if int(packet.get("protocol_version", -1)) != PROTOCOL_VERSION or sender not in teams or tick <= int(controller.tick_index) or tick > int(controller.tick_index) + MAX_FRAME_LEAD or not records is Array or records.size() > MAX_FRAME_COMMANDS:
		return "frame_invalid"
	for record_value in records:
		if not record_value is Dictionary or not record_value.get("unit_ids") is Array or not record_value.get("params") is Dictionary:
			return "frame_command_invalid"
		if String(record_value.get("type", "")) == "population_limit" and sender != teams[0]:
			return "host_only_command"
		var candidate: Dictionary = record_value.duplicate(true)
		candidate["tick"] = tick
		candidate["issuer_id"] = sender
		candidate["sequence_id"] = 0
		if codec.command_from_record(candidate) == null:
			return "frame_command_invalid"
	var normalized_packet: Dictionary = _normalized_wire_value(packet)
	var tick_frames: Dictionary = frames.get(tick, {})
	if tick_frames.has(sender):
		if tick_frames[sender] != normalized_packet:
			_abort("conflicting_frame:%d:%d" % [sender, tick])
			return last_error
		return ""
	tick_frames[sender] = normalized_packet
	frames[tick] = tick_frames
	return ""


func _receive_hash(packet: Dictionary) -> String:
	if phase != "running" or int(packet.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return "session_not_running"
	var sender := int(packet.get("sender_team", -1))
	var tick := int(packet.get("tick", -1))
	var digest := String(packet.get("sha256", ""))
	if sender not in teams or tick <= 0 or tick > int(controller.tick_index) + MAX_FRAME_LEAD or tick % hash_interval != 0 or digest.length() != 64:
		return "hash_invalid"
	if tick < int(controller.tick_index) - MAX_HASH_CHECKPOINTS * hash_interval:
		_abort("hash_window_expired:%d:%d" % [sender, tick])
		return last_error
	var tick_hashes: Dictionary = remote_hashes.get(tick, {})
	if tick_hashes.has(sender) and String(tick_hashes[sender]) != digest:
		_abort("conflicting_hash:%d:%d" % [sender, tick])
		return last_error
	tick_hashes[sender] = digest
	remote_hashes[tick] = tick_hashes
	_check_hashes_at(tick)
	return last_error if phase == "aborted" else ""


func _check_hashes_at(tick: int) -> void:
	if not local_hashes.has(tick):
		return
	var expected := String(local_hashes[tick])
	var tick_hashes: Dictionary = remote_hashes.get(tick, {})
	for sender in teams:
		if sender == local_team or not tick_hashes.has(sender):
			continue
		var actual := String(tick_hashes[sender])
		if actual != expected:
			first_divergence = {"tick": tick, "team": sender, "local_sha256": expected, "remote_sha256": actual}
			_abort("desync:%d:%d" % [tick, sender])
			return


func _receive_chat(packet: Dictionary) -> String:
	if phase != "running" or int(packet.get("protocol_version", -1)) != PROTOCOL_VERSION:
		return "session_not_running"
	var sender := int(packet.get("sender_team", -1))
	var recipients: Variant = packet.get("recipients")
	var message := String(packet.get("text", ""))
	if sender not in teams or not recipients is Array or String(packet.get("channel", "")) not in ["allies", "all"] or message.is_empty() or message.length() > MAX_CHAT_LENGTH:
		return "chat_invalid"
	var expected_recipients: Array[int] = []
	for team in teams:
		if String(packet.get("channel", "")) == "all" or (controller.simulation_world.are_teams_allied(sender, team) and controller.simulation_world.are_teams_allied(team, sender)):
			expected_recipients.append(team)
	if _normalized_wire_value(recipients) != _normalized_wire_value(expected_recipients):
		return "chat_recipients_invalid"
	if recipients.any(func(team): return int(team) == local_team) or (local_team == 0 and String(packet.get("channel", "")) == "all"):
		chat_messages.append(packet.duplicate(true))
		if chat_messages.size() > MAX_CHAT_HISTORY:
			chat_messages.pop_front()
	return ""


func _prune_hash_history(latest_tick: int) -> void:
	var oldest_retained := latest_tick - MAX_HASH_CHECKPOINTS * hash_interval
	for tick_value in local_hashes.keys():
		if int(tick_value) < oldest_retained:
			local_hashes.erase(tick_value)
	for tick_value in remote_hashes.keys():
		if int(tick_value) < oldest_retained:
			remote_hashes.erase(tick_value)


func _abort(reason: String) -> void:
	if phase == "aborted":
		return
	phase = "aborted"
	last_error = reason


static func _has_duplicate_teams(sorted_teams: Array[int]) -> bool:
	for index in range(1, sorted_teams.size()):
		if sorted_teams[index] == sorted_teams[index - 1]:
			return true
	return false


static func _normalized_wire_value(value: Variant) -> Variant:
	if value is int or value is float:
		return float(value)
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(_normalized_wire_value(item))
		return items
	if value is Dictionary:
		var entries: Dictionary = {}
		for key in value:
			entries[String(key)] = _normalized_wire_value(value[key])
		return entries
	return value
