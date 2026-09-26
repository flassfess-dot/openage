class_name RoRLockstepTcpRelay
extends RefCounted

# A newline is safe as a record delimiter because JSON escapes newlines in strings.
# Bytes are buffered until a complete record arrives, so split UTF-8 codepoints are safe.
const MAX_PACKET_BYTES := 65536

var mode := "closed"
var server: TCPServer
var upstream: StreamPeerTCP
var upstream_buffer := PackedByteArray()
var peers: Array[Dictionary] = []
var allowed_teams: Array[int] = []
var host_team: int = 1


func start_server(port: int, participants: Array[int], local_host_team: int = 1, bind_address: String = "127.0.0.1") -> String:
	if mode != "closed" or port < 1 or port > 65535 or local_host_team not in participants:
		return "relay_configuration_invalid"
	var listener := TCPServer.new()
	if listener.listen(port, bind_address) != OK:
		return "relay_listen_failed"
	server = listener
	mode = "server"
	allowed_teams = participants.duplicate()
	host_team = local_host_team
	return ""


func connect_client(address: String, port: int) -> String:
	if mode != "closed" or address.is_empty() or port < 1 or port > 65535:
		return "relay_configuration_invalid"
	var stream := StreamPeerTCP.new()
	if stream.connect_to_host(address, port) != OK:
		return "relay_connect_failed"
	upstream = stream
	mode = "client"
	return ""


func connected_teams() -> Array[int]:
	var result: Array[int] = []
	for peer in peers:
		if int(peer.get("team", -1)) > 0:
			result.append(int(peer["team"]))
	result.sort()
	return result


func connection_ready() -> bool:
	if mode == "server":
		return server != null and server.is_listening()
	if mode == "client" and upstream != null:
		upstream.poll()
		return upstream.get_status() == StreamPeerTCP.STATUS_CONNECTED
	return false


func send_packet(packet: Dictionary) -> String:
	var bytes := _wire_bytes(packet)
	if bytes.is_empty():
		return "relay_packet_too_large"
	if mode == "client":
		if not connection_ready() or upstream.put_data(bytes) != OK:
			return "relay_send_failed"
		return ""
	if mode == "server":
		if peers.is_empty():
			return "relay_no_peers"
		for peer in peers:
			var stream: StreamPeerTCP = peer["stream"]
			if stream.get_status() == StreamPeerTCP.STATUS_CONNECTED and stream.put_data(bytes) != OK:
				return "relay_send_failed"
		return ""
	return "relay_not_connected"


func poll_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if mode == "server":
		while server.is_connection_available():
			peers.append({"stream": server.take_connection(), "buffer": PackedByteArray(), "team": -1})
		for index in range(peers.size() - 1, -1, -1):
			var peer: Dictionary = peers[index]
			var stream: StreamPeerTCP = peer["stream"]
			stream.poll()
			if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				_discard_peer(index, events)
				continue
			var packets := _read_packets(stream, peer, events)
			if bool(peer.get("invalid", false)):
				_discard_peer(index, events)
				continue
			for packet in packets:
				if not _accept_client_packet(peer, packet):
					events.append({"kind": "transport_error", "reason": "relay_sender_invalid"})
					peer["invalid"] = true
					break
				events.append({"kind": "packet", "packet": packet})
				var bytes := _wire_bytes(packet)
				for other_peer in peers:
					if other_peer == peer:
						continue
					var other_stream: StreamPeerTCP = other_peer["stream"]
					if other_stream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
						other_stream.put_data(bytes)
			if bool(peer.get("invalid", false)):
				_discard_peer(index, events)
	elif mode == "client" and upstream != null:
		upstream.poll()
		if upstream.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			var holder := {"buffer": upstream_buffer}
			for packet in _read_packets(upstream, holder, events):
				events.append({"kind": "packet", "packet": packet})
			upstream_buffer = holder["buffer"]
			if bool(holder.get("invalid", false)):
				close()
		elif upstream.get_status() == StreamPeerTCP.STATUS_ERROR or upstream.get_status() == StreamPeerTCP.STATUS_NONE:
			events.append({"kind": "disconnected", "team": host_team})
			close()
	return events


func close() -> void:
	if upstream != null:
		upstream.disconnect_from_host()
	upstream = null
	if server != null:
		server.stop()
	server = null
	for peer in peers:
		var stream: StreamPeerTCP = peer["stream"]
		stream.disconnect_from_host()
	peers.clear()
	upstream_buffer.clear()
	mode = "closed"


func _accept_client_packet(peer: Dictionary, packet: Dictionary) -> bool:
	var sender := int(packet.get("sender_team", -1))
	if int(peer.get("team", -1)) >= 0:
		return sender == int(peer["team"])
	if String(packet.get("kind", "")) != "hello":
		return false
	if sender == 0 and String(packet.get("role", "")) == "spectator":
		peer["team"] = 0
		return true
	if sender == host_team or sender not in allowed_teams or String(packet.get("role", "")) != "player" or sender in connected_teams():
		return false
	peer["team"] = sender
	return true


func _discard_peer(index: int, events: Array[Dictionary]) -> void:
	var peer: Dictionary = peers[index]
	var stream: StreamPeerTCP = peer["stream"]
	stream.disconnect_from_host()
	var team := int(peer.get("team", -1))
	peers.remove_at(index)
	if team > 0:
		events.append({"kind": "disconnected", "team": team})


func _read_packets(stream: StreamPeerTCP, holder: Dictionary, events: Array[Dictionary]) -> Array[Dictionary]:
	var packets: Array[Dictionary] = []
	var available := stream.get_available_bytes()
	if available > 0:
		var result: Array = stream.get_data(available)
		if int(result[0]) != OK:
			holder["invalid"] = true
			return packets
		var buffer: PackedByteArray = holder["buffer"]
		buffer.append_array(result[1])
		holder["buffer"] = buffer
	var buffer: PackedByteArray = holder["buffer"]
	while true:
		var delimiter := buffer.find(10)
		if delimiter < 0:
			break
		if delimiter > MAX_PACKET_BYTES:
			holder["invalid"] = true
			break
		var decoded: Variant = JSON.parse_string(buffer.slice(0, delimiter).get_string_from_utf8())
		buffer = buffer.slice(delimiter + 1)
		if not decoded is Dictionary:
			holder["invalid"] = true
			break
		packets.append(decoded)
	holder["buffer"] = buffer
	if buffer.size() > MAX_PACKET_BYTES:
		holder["invalid"] = true
	if bool(holder.get("invalid", false)):
		events.append({"kind": "transport_error", "reason": "relay_packet_invalid"})
	return packets


static func _wire_bytes(packet: Dictionary) -> PackedByteArray:
	var bytes := (JSON.stringify(packet) + "\n").to_utf8_buffer()
	return bytes if bytes.size() <= MAX_PACKET_BYTES else PackedByteArray()
