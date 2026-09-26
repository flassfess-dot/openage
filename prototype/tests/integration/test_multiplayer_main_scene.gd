extends SceneTree

const Commands := preload("res://scripts/commands.gd")
const GameScene := preload("res://main.tscn")
const MultiplayerLobby := preload("res://scripts/multiplayer_lobby.gd")
const ReplaySystem := preload("res://scripts/replay_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var lobby = MultiplayerLobby.new()
	var error: String = lobby.configure(2, {"map_size_id": "compact", "map_type_id": "grasslands", "seed": 59137})
	assert_equal(error, "", "two-player launcher lobby configures")
	if not error.is_empty():
		finish()
		return
	var invited = MultiplayerLobby.new()
	assert_equal(invited.load_invite(lobby.invite_code()), "", "joining scene imports the same match")
	var built: Dictionary = lobby.build_match()
	var joined: Dictionary = invited.build_match()
	assert_equal(built.get("identity", ""), joined.get("identity", ""), "both launchers choose the same deterministic identity")
	if not bool(built.get("valid", false)) or not bool(joined.get("valid", false)):
		failures.append("networked generated match did not build")
		finish()
		return
	var host = GameScene.instantiate()
	var client = GameScene.instantiate()
	for game in [host, client]:
		game.match_path = String(built["identity"])
		game.match_definition_override = built["definition"].duplicate(true)
		game.map_definition_override = built["map_data"].duplicate(true)
		game.network_port = 39763
	host.network_role = "host"
	host.local_player_team = 1
	client.network_role = "join"
	client.local_player_team = 2
	client.network_address = "127.0.0.1"
	root.add_child(host)
	root.add_child(client)
	for frame in range(900):
		await process_frame
		if host.network_session != null and client.network_session != null and host.network_session.phase == "running" and client.network_session.phase == "running":
			break
	assert_true(host.network_session != null and client.network_session != null, "both game scenes own a lockstep session")
	if host.network_session == null or client.network_session == null:
		host.queue_free()
		client.queue_free()
		finish()
		return
	assert_equal(host.network_session.phase, "running", "host reaches live multiplayer")
	assert_equal(client.network_session.phase, "running", "client reaches live multiplayer")
	assert_true(host.network_chat_input != null and client.network_chat_input != null, "both scenes expose a chat entry")
	var host_id := _first_unit_id(host, 1)
	var client_id := _first_unit_id(client, 2)
	var host_move = null
	var client_move = null
	assert_true(host_id > 0 and client_id > 0, "both teams have controllable workers")
	if host_id > 0 and client_id > 0:
		host_move = Commands.MoveCommand.new(host.game_controller.tick_index + 1, [host_id], Vector2(5, 5))
		client_move = Commands.MoveCommand.new(client.game_controller.tick_index + 1, [client_id], Vector2(8, 8))
		host.enqueue_with_feedback(host_move, "move", "")
		client.enqueue_with_feedback(client_move, "move", "")
	host._submit_network_chat("/all Привет")
	host._submit_network_chat("/pop 75")
	for frame in range(900):
		await process_frame
		if host.game_controller.tick_index >= 40 and client.game_controller.tick_index >= 40:
			break
	assert_true(host.game_controller.tick_index >= 40 and client.game_controller.tick_index >= 40, "both scenes advance through live network frames")
	var verifier := ReplaySystem.new()
	assert_equal(verifier.world_state_hash(host.simulation_world, host.game_controller.tick_index, host.game_controller), verifier.world_state_hash(client.simulation_world, client.game_controller.tick_index, client.game_controller), "rendered host and client scenes keep identical canonical state")
	assert_equal(host.network_session.phase, "running", "host has no desync")
	assert_equal(client.network_session.phase, "running", "client has no desync")
	if host_move != null and client_move != null:
		assert_true(int(host_move.sequence_id) > 0 and int(client_move.sequence_id) > 0, "local UI orders recover their authoritative network sequence for feedback")
	assert_true(client.network_session.chat_messages.any(func(packet): return String(packet.get("text", "")) == "Привет"), "public chat reaches the other player")
	assert_equal(client.simulation_world.economy_system.get_population_limit(2), 75, "host's live population change reaches the client")
	host.network_relay.close()
	client.network_relay.close()
	host.queue_free()
	client.queue_free()
	await process_frame
	finish()


func _first_unit_id(game, team: int) -> int:
	for unit_value in game.simulation_world.get_units():
		var unit: Dictionary = unit_value
		if int(unit.get("team", 0)) == team and String(unit.get("kind", "")) == "villager":
			return int(unit.get("id", -1))
	return -1


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P12 host and join main scene live loopback tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
