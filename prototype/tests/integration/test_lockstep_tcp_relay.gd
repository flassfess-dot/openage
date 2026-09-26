extends SceneTree

const Relay := preload("res://scripts/lockstep_tcp_relay.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var host = Relay.new()
	var port := 39741
	var participants: Array[int] = [1, 2, 3]
	while port < 39751 and not host.start_server(port, participants).is_empty():
		port += 1
	if port >= 39751:
		failures.append("TCP loopback port unavailable")
		finish()
		return
	var peer_two = Relay.new()
	var peer_three = Relay.new()
	assert_equal(peer_two.connect_client("127.0.0.1", port), "", "first real TCP client connects")
	assert_equal(peer_three.connect_client("127.0.0.1", port), "", "second real TCP client connects")
	for attempt in range(200):
		host.poll_events()
		if peer_two.connection_ready() and peer_three.connection_ready():
			break
		OS.delay_msec(1)
	assert_true(peer_two.connection_ready() and peer_three.connection_ready(), "both TCP connections establish")
	assert_equal(peer_two.send_packet({"kind": "hello", "sender_team": 2, "role": "player"}), "", "second team sends its hello")
	assert_equal(peer_three.send_packet({"kind": "hello", "sender_team": 3, "role": "player"}), "", "third team sends its hello")
	var host_events: Array[Dictionary] = []
	var two_events: Array[Dictionary] = []
	var three_events: Array[Dictionary] = []
	for attempt in range(200):
		host_events.append_array(host.poll_events())
		two_events.append_array(peer_two.poll_events())
		three_events.append_array(peer_three.poll_events())
		if host.connected_teams().size() == 2 and _has_packet(host_events, 2) and _has_packet(host_events, 3) and _has_packet(two_events, 3) and _has_packet(three_events, 2):
			break
		OS.delay_msec(1)
	assert_equal(host.connected_teams(), [2, 3], "host binds each connection to the team in its first hello")
	assert_true(_has_packet(two_events, 3) and _has_packet(three_events, 2), "server relays one client's packets to other clients")
	assert_equal(host.send_packet({"kind": "hello", "sender_team": 1, "role": "player"}), "", "host broadcasts to both clients")
	for attempt in range(200):
		two_events.append_array(peer_two.poll_events())
		three_events.append_array(peer_three.poll_events())
		if _has_packet(two_events, 1) and _has_packet(three_events, 1):
			break
		OS.delay_msec(1)
	assert_true(_has_packet(two_events, 1) and _has_packet(three_events, 1), "host packets reach both TCP clients")
	var utf8_message := {"kind": "chat", "sender_team": 2, "text": "На помощь"}
	assert_equal(peer_two.send_packet(utf8_message), "", "UTF-8 chat travels over TCP")
	for attempt in range(200):
		host_events.append_array(host.poll_events())
		three_events.append_array(peer_three.poll_events())
		if _has_text(host_events, "На помощь") and _has_text(three_events, "На помощь"):
			break
		OS.delay_msec(1)
	assert_true(_has_text(host_events, "На помощь") and _has_text(three_events, "На помощь"), "framing preserves UTF-8 and packet boundaries")
	var spectator = Relay.new()
	assert_equal(spectator.connect_client("127.0.0.1", port), "", "read-only spectator connects before gameplay")
	for attempt in range(200):
		host.poll_events()
		if spectator.connection_ready() and host.peers.size() == 3:
			break
		OS.delay_msec(1)
	assert_equal(spectator.send_packet({"kind": "hello", "sender_team": 0, "role": "spectator"}), "", "spectator identifies its read-only role")
	for attempt in range(200):
		host_events.append_array(host.poll_events())
		if _has_packet(host_events, 0):
			break
		OS.delay_msec(1)
	assert_equal(host.connected_teams(), [2, 3], "spectator does not consume a player slot")
	host.send_packet({"kind": "chat", "sender_team": 1, "text": "Наблюдение"})
	var spectator_events: Array[Dictionary] = []
	for attempt in range(200):
		spectator_events.append_array(spectator.poll_events())
		if _has_text(spectator_events, "Наблюдение"):
			break
		OS.delay_msec(1)
	assert_true(_has_text(spectator_events, "Наблюдение"), "spectator receives the public channel")
	peer_two.send_packet({"kind": "frame", "sender_team": 3, "tick": 1, "commands": []})
	for attempt in range(200):
		host_events.append_array(host.poll_events())
		if host.connected_teams().size() == 1:
			break
		OS.delay_msec(1)
	assert_equal(host.connected_teams(), [3], "spoofed sender disconnects only its own connection")
	assert_true(_has_disconnection(host_events, 2), "disconnect is surfaced to lockstep policy")
	peer_two.close()
	peer_three.close()
	spectator.close()
	host.close()
	finish()


func _has_packet(events: Array[Dictionary], sender: int) -> bool:
	return events.any(func(event): return String(event.get("kind", "")) == "packet" and int(event.get("packet", {}).get("sender_team", -1)) == sender)


func _has_text(events: Array[Dictionary], message: String) -> bool:
	return events.any(func(event): return String(event.get("kind", "")) == "packet" and String(event.get("packet", {}).get("text", "")) == message)


func _has_disconnection(events: Array[Dictionary], team: int) -> bool:
	return events.any(func(event): return String(event.get("kind", "")) == "disconnected" and int(event.get("team", -1)) == team)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P12 real TCP relay integration tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
