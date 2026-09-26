extends SceneTree

const LockstepSession := preload("res://scripts/lockstep_session.gd")
const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []
var catalog


func _initialize() -> void:
	catalog = ResourceCatalog.new()
	catalog.load()
	for count in [2, 4, 8]:
		verify_loopback(count)
	verify_handshake_rejection()
	verify_conflicting_frame()
	verify_host_only_command()
	verify_actual_desync()
	verify_spectator_and_disconnect_policy()
	if failures.is_empty():
		print("P12 deterministic 2/4/8-player lockstep loopback tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func verify_loopback(count: int) -> void:
	var sessions := create_sessions(count)
	for sender in sessions:
		var hello: Dictionary = JSON.parse_string(JSON.stringify(sender.hello_packet()))
		for receiver in sessions:
			assert_equal(receiver.receive_packet(hello), "", "%d-player handshake accepts the shared match" % count)
	for session in sessions:
		assert_equal(session.phase, "running", "%d-player handshake reaches running state" % count)
	var future_packets: Array[Dictionary] = []
	for session in sessions:
		future_packets.append(session.frame_packet(2, []))
	deliver(sessions, future_packets, true)
	assert_true(not sessions[0].can_advance(), "future reordered frames cannot skip a missing earlier tick")
	var first_packets: Array[Dictionary] = []
	for session in sessions:
		var own_id := int(session.controller.simulation_world.get_units()[session.local_team - 1].get("id", -1))
		var commands: Array = [Commands.StopCommand.new(1, [own_id])]
		if session.local_team == 1:
			commands.append(Commands.PopulationLimitCommand.new(1, 75))
		first_packets.append(session.frame_packet(1, commands))
	var delayed_packet: Dictionary = first_packets.pop_back()
	deliver(sessions, first_packets, true)
	assert_true(not sessions[0].can_advance(), "delayed player frame blocks the next fixed tick")
	var delayed_packets: Array[Dictionary] = [delayed_packet]
	deliver(sessions, delayed_packets, true)
	advance_all(sessions, count, 1)
	for session in sessions:
		for team in range(1, count + 1):
			assert_equal(session.controller.simulation_world.economy_system.get_population_limit(team), 75, "host population-limit command applies identically to every participant")
	advance_all(sessions, count, 2)
	for tick in [3, 4]:
		var packets: Array[Dictionary] = []
		for session in sessions:
			packets.append(session.frame_packet(tick, []))
		deliver(sessions, packets, true)
		advance_all(sessions, count, tick)
	var expected_hash: String = sessions[0].local_hashes[4]
	for session in sessions:
		assert_equal(String(session.local_hashes[4]), expected_hash, "%d-player peers retain identical canonical hash" % count)
		assert_equal(session.phase, "running", "%d-player peers remain synchronized after packet duplicates" % count)
	if count == 2:
		var replay_peer = create_sessions(2)[0]
		var recorded: Dictionary = sessions[0].controller.replay_recorder.to_dictionary()
		assert_true(replay_peer.controller.load_replay(recorded), "authoritative lockstep command stream loads as an ordinary replay")
		assert_true(replay_peer.controller.replay_until_tick(4, 1, 2), "lockstep replay reaches the same fixed tick")
		var verifier := ReplaySystem.new()
		assert_equal(verifier.world_state_hash(replay_peer.controller.simulation_world, 4, replay_peer.controller), expected_hash, "population-limit session command survives deterministic replay")
	if count == 4:
		verify_chat_and_desync(sessions)


func verify_chat_and_desync(sessions: Array) -> void:
	var leader = sessions[0]
	var no_alliance: Dictionary = leader.chat_packet("Готовы?")
	assert_equal(no_alliance.get("recipients", []), [1], "allied chat defaults to the sender without an alliance")
	for session in sessions:
		session.controller.simulation_world.set_alliance(1, 2, true)
	var allied_chat: Dictionary = leader.chat_packet("На помощь")
	assert_equal(allied_chat.get("recipients", []), [1, 2], "default chat addresses mutually allied players only")
	var transmitted_chat: Dictionary = JSON.parse_string(JSON.stringify(allied_chat))
	assert_equal(sessions[1].receive_packet(transmitted_chat), "", "allied chat packet is accepted after serialization")
	assert_equal(sessions[2].receive_packet(transmitted_chat), "", "nonrecipient can ignore an allied chat packet")
	assert_equal(sessions[1].chat_messages.size(), 1, "allied recipient sees the chat")
	assert_equal(sessions[2].chat_messages.size(), 0, "non-allied team does not see the chat")
	for tick in [5, 6]:
		var packets: Array[Dictionary] = []
		for session in sessions:
			packets.append(session.frame_packet(tick, []))
		deliver(sessions, packets, false)
		var hashes: Array[Dictionary] = []
		for session in sessions:
			var result: Dictionary = session.advance_one()
			assert_true(bool(result.get("advanced", false)), "desync fixture advances to tick %d" % tick)
			if not result.get("hash_packet", {}).is_empty():
				hashes.append(result["hash_packet"])
		if tick == 6:
			var forged: Dictionary = hashes[1].duplicate(true)
			forged["sha256"] = "0".repeat(64)
			assert_true(leader.receive_packet(forged).begins_with("desync:"), "first mismatching periodic hash aborts the session")
			assert_equal(int(leader.first_divergence.get("tick", -1)), 6, "desync report identifies the first divergent checkpoint")
			assert_equal(int(leader.first_divergence.get("team", -1)), 2, "desync report identifies the disagreeing peer")
		else:
			deliver(sessions, hashes, false)
	assert_equal(leader.phase, "aborted", "desync freezes the session instead of silently diverging")


func verify_handshake_rejection() -> void:
	var sessions := create_sessions(2)
	var bad_hello: Dictionary = sessions[1].hello_packet().duplicate(true)
	bad_hello["seed"] = 999
	assert_true(sessions[0].receive_packet(bad_hello).begins_with("handshake_mismatch:"), "mismatched seed fails before accepting commands")
	assert_equal(sessions[0].phase, "aborted", "incompatible handshake cannot start a match")
	var interval_sessions := create_sessions(2)
	var bad_interval: Dictionary = interval_sessions[1].hello_packet().duplicate(true)
	bad_interval["hash_interval"] = 80
	assert_true(interval_sessions[0].receive_packet(bad_interval).begins_with("handshake_mismatch:"), "peers cannot disagree about their hash comparison cadence")


func verify_conflicting_frame() -> void:
	var sessions := create_sessions(2)
	for sender in sessions:
		for receiver in sessions:
			receiver.receive_packet(sender.hello_packet())
	var first: Dictionary = sessions[1].frame_packet(1, [])
	assert_equal(sessions[0].receive_packet(first), "", "first remote frame is accepted")
	var conflicting: Dictionary = first.duplicate(true)
	conflicting["commands"] = [{"type": "resign", "unit_ids": [], "params": {}}]
	assert_true(sessions[0].receive_packet(conflicting).begins_with("conflicting_frame:"), "conflicting duplicate frame aborts rather than replacing commands")
	assert_true(not sessions[0].can_advance(), "conflicting transport data freezes simulation")


func verify_host_only_command() -> void:
	var sessions := create_sessions(2)
	for sender in sessions:
		for receiver in sessions:
			receiver.receive_packet(sender.hello_packet())
	assert_true(sessions[1].frame_packet(1, [Commands.PopulationLimitCommand.new(1, 100)]).is_empty(), "remote player cannot emit a host-only population change")
	var forged := {"kind": "frame", "protocol_version": 1, "sender_team": 2, "tick": 1, "commands": [{"type": "population_limit", "unit_ids": [], "params": {"limit": 100}}]}
	assert_equal(sessions[0].receive_packet(forged), "host_only_command", "host rejects a forged population-limit command at the protocol boundary")


func verify_actual_desync() -> void:
	var sessions := create_sessions(2)
	for sender in sessions:
		for receiver in sessions:
			receiver.receive_packet(sender.hello_packet())
	for tick in [1, 2]:
		if tick == 2:
			sessions[1].controller.simulation_world.add_unit(2, "villager", Vector2(14, 14), false)
		var packets: Array[Dictionary] = []
		for session in sessions:
			packets.append(session.frame_packet(tick, []))
		deliver(sessions, packets, false)
		var hashes: Array[Dictionary] = []
		for session in sessions:
			var result: Dictionary = session.advance_one()
			assert_true(bool(result.get("advanced", false)), "divergent peers still reach the comparison checkpoint")
			if not result.get("hash_packet", {}).is_empty():
				hashes.append(result["hash_packet"])
		if tick == 2:
			assert_true(sessions[0].receive_packet(hashes[1]).begins_with("desync:"), "actual divergent world state is detected by periodic hash")
			assert_equal(int(sessions[0].first_divergence.get("tick", -1)), 2, "real desync reports its first hash tick")


func verify_spectator_and_disconnect_policy() -> void:
	var sessions := create_sessions(2, true)
	for sender in sessions:
		var hello: Dictionary = JSON.parse_string(JSON.stringify(sender.hello_packet()))
		for receiver in sessions:
			assert_equal(receiver.receive_packet(hello), "", "spectator joins before the first tick")
	var spectator = sessions[2]
	assert_equal(spectator.phase, "running", "spectator waits for the same player handshake")
	assert_true(spectator.frame_packet(1, []).is_empty(), "spectator cannot submit simulation commands")
	var packets: Array[Dictionary] = []
	for index in range(2):
		packets.append(sessions[index].frame_packet(1, []))
	deliver(sessions, packets, true)
	for session in sessions:
		assert_true(bool(session.advance_one().get("advanced", false)), "spectator observes the same first fixed tick")
	assert_true(spectator.receive_packet(spectator.hello_packet()) == "late_spectator_unsupported", "a spectator cannot join or reconnect mid-match without a checkpoint")
	assert_equal(spectator.peer_disconnected(99), "disconnect_sender_invalid", "unknown peer cannot abort a session")
	assert_equal(spectator.receive_packet({"kind": "abort", "protocol_version": 1, "sender_team": 99}), "abort_sender_invalid", "unknown sender cannot forge a peer abort")
	assert_true(spectator.peer_disconnected(2).begins_with("peer_disconnected:"), "known peer disconnection explicitly aborts until a new match")
	assert_equal(spectator.phase, "aborted", "disconnect freezes the spectator at the same tick")


func create_sessions(count: int, include_spectator: bool = false) -> Array:
	var participants: Array[int] = []
	var players: Array = []
	for team in range(1, count + 1):
		participants.append(team)
		players.append({"team": team, "civilization_id": 13})
	var definition := {"id": "lockstep_fixture", "map": {"seed": 12345, "size": Vector2i(24, 24)}, "players": players}
	var sessions: Array = []
	var local_teams: Array[int] = participants.duplicate()
	if include_spectator:
		local_teams.append(0)
	for local_team in local_teams:
		var world = SimulationWorld.new(Vector2i(24, 24))
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		for team in participants:
			world.add_unit(team, "villager", Vector2(2 + team * 2, 4), false)
		var controller = GameController.new(world)
		var session = LockstepSession.new()
		assert_equal(session.configure(controller, definition, 12345, participants, local_team, 2), "", "loopback peer configures")
		sessions.append(session)
	return sessions


func deliver(sessions: Array, packets: Array[Dictionary], duplicate: bool) -> void:
	for index in range(packets.size() - 1, -1, -1):
		var transmitted: Dictionary = JSON.parse_string(JSON.stringify(packets[index]))
		for session in sessions:
			assert_equal(session.receive_packet(transmitted), "", "reordered transport packet is accepted")
			if duplicate:
				assert_equal(session.receive_packet(transmitted), "", "identical duplicate transport packet is idempotent")


func advance_all(sessions: Array, count: int, tick: int) -> void:
	var hashes: Array[Dictionary] = []
	for session in sessions:
		assert_true(session.can_advance(), "%d-player peer has every frame at tick %d" % [count, tick])
		var result: Dictionary = session.advance_one()
		assert_true(bool(result.get("advanced", false)), "%d-player peer advances tick %d" % [count, tick])
		if not result.get("hash_packet", {}).is_empty():
			hashes.append(result["hash_packet"])
	if not hashes.is_empty():
		deliver(sessions, hashes, true)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
