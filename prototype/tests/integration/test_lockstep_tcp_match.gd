extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameController := preload("res://scripts/game_controller.gd")
const LockstepSession := preload("res://scripts/lockstep_session.gd")
const Relay := preload("res://scripts/lockstep_tcp_relay.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var catalog = ResourceCatalog.new()
	catalog.load()
	var participants: Array[int] = [1, 2]
	var definition := {"id": "tcp_lockstep_fixture", "map": {"seed": 90317, "size": Vector2i(24, 24)}, "players": [{"team": 1}, {"team": 2}]}
	var sessions: Array = []
	for team in participants:
		var world = SimulationWorld.new(Vector2i(24, 24))
		world.set_gamespec(catalog.gamespec_data)
		world.set_terrain_catalog(catalog.terrain_catalog_data)
		world.set_object_catalog(catalog.object_catalog_data)
		world.set_graphics_catalog(catalog.graphics_catalog_data)
		world.set_runtime_catalog(catalog.runtime_catalog_data)
		world.add_unit(1, "villager", Vector2(4, 4), false)
		world.add_unit(2, "villager", Vector2(10, 4), false)
		var session = LockstepSession.new()
		assert_equal(session.configure(GameController.new(world), definition, 90317, participants, team, 10), "", "network peer configures")
		sessions.append(session)
	var host = Relay.new()
	var port := 39752
	while port < 39762 and not host.start_server(port, participants).is_empty():
		port += 1
	if port >= 39762:
		failures.append("TCP match port unavailable")
		finish()
		return
	var client = Relay.new()
	assert_equal(client.connect_client("127.0.0.1", port), "", "remote connects to match host")
	for attempt in range(200):
		host.poll_events()
		if client.connection_ready():
			break
		OS.delay_msec(1)
	assert_true(client.connection_ready(), "remote connection reaches ready state")
	for attempt in range(200):
		host.poll_events()
		if host.peers.size() == 1:
			break
		OS.delay_msec(1)
	assert_equal(host.peers.size(), 1, "host accepts the socket before sending its hello")
	assert_equal(host.send_packet(sessions[0].hello_packet()), "", "host sends versioned handshake")
	assert_equal(client.send_packet(sessions[1].hello_packet()), "", "remote sends versioned handshake")
	for attempt in range(200):
		pump(host, client, sessions)
		if sessions[0].phase == "running" and sessions[1].phase == "running":
			break
		OS.delay_msec(1)
	assert_true(sessions[0].phase == "running" and sessions[1].phase == "running", "real TCP handshake reaches gameplay (host=%s client=%s teams=%s)" % [sessions[0].phase, sessions[1].phase, host.connected_teams()])
	if not failures.is_empty():
		client.close()
		host.close()
		finish()
		return
	for tick in range(1, 101):
		var host_commands: Array = []
		var remote_commands: Array = []
		if tick == 1:
			host_commands.append(Commands.MoveCommand.new(tick, [1], Vector2(6, 4)))
			remote_commands.append(Commands.MoveCommand.new(tick, [2], Vector2(8, 4)))
		if tick == 20:
			host_commands.append(Commands.PopulationLimitCommand.new(tick, 75))
		assert_equal(host.send_packet(sessions[0].frame_packet(tick, host_commands)), "", "host sends its command frame")
		assert_equal(client.send_packet(sessions[1].frame_packet(tick, remote_commands)), "", "remote sends its command frame")
		for attempt in range(200):
			pump(host, client, sessions)
			if sessions[0].can_advance() and sessions[1].can_advance():
				break
			OS.delay_msec(1)
		if not sessions[0].can_advance() or not sessions[1].can_advance():
			failures.append("real TCP frame did not arrive at tick %d" % tick)
			break
		var host_step: Dictionary = sessions[0].advance_one()
		var client_step: Dictionary = sessions[1].advance_one()
		assert_true(bool(host_step.get("advanced", false)) and bool(client_step.get("advanced", false)), "both peers advance the same fixed tick")
		if not host_step["hash_packet"].is_empty():
			host.send_packet(host_step["hash_packet"])
			client.send_packet(client_step["hash_packet"])
			for attempt in range(200):
				pump(host, client, sessions)
				if sessions[0].remote_hashes.has(tick) and sessions[1].remote_hashes.has(tick):
					break
				OS.delay_msec(1)
			assert_true(sessions[0].remote_hashes.has(tick) and sessions[1].remote_hashes.has(tick), "both peers receive periodic hashes")
		if not failures.is_empty():
			break
	assert_equal(sessions[0].phase, "running", "host stays synchronized over actual TCP")
	assert_equal(sessions[1].phase, "running", "client stays synchronized over actual TCP")
	assert_equal(sessions[0].local_hashes.get(100, ""), sessions[1].local_hashes.get(100, ""), "real network match ends on the same canonical hash")
	assert_equal(sessions[1].controller.simulation_world.economy_system.get_population_limit(2), 75, "host population setting reaches the remote simulation")
	client.close()
	host.close()
	finish()


func pump(host, client, sessions: Array) -> void:
	for event in host.poll_events():
		if String(event.get("kind", "")) == "packet":
			var error: String = sessions[0].receive_packet(event["packet"])
			if not error.is_empty():
				failures.append("host packet error: %s" % error)
	for event in client.poll_events():
		if String(event.get("kind", "")) == "packet":
			var error: String = sessions[1].receive_packet(event["packet"])
			if not error.is_empty():
				failures.append("client packet error: %s" % error)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P12 real TCP match command-stream and hash tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
