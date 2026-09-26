extends SceneTree

const MultiplayerLobby := preload("res://scripts/multiplayer_lobby.gd")
const GameSaveArchive := preload("res://scripts/game_save_archive.gd")

var failures: Array[String] = []


func _initialize() -> void:
	for count in [2, 4, 8]:
		var lobby = MultiplayerLobby.new()
		var map_size := "large" if count == 8 else "standard"
		assert_equal(lobby.configure(count, {"map_size_id": map_size, "map_type_id": "coastal", "population_limit": 75, "victory_mode_id": "conquest", "seed": 41721}), "", "%d-player lobby accepts map and rule settings" % count)
		assert_equal(lobby.participant_teams().size(), count, "%d-player lobby exposes every remote human participant" % count)
		assert_equal(lobby.set_slot(2, 14, 1), "", "%d-player lobby permits civilization and alliance selection" % count)
		assert_equal(int(lobby.settings["players"][1].get("civilization_id", -1)), 14, "selected civilization is retained")
		assert_equal(int(lobby.settings["players"][1].get("alliance_id", -1)), 1, "selected alliance is retained")
		if count == 2:
			var built: Dictionary = lobby.build_match()
			assert_true(bool(built.get("valid", false)), "networked two-player lobby builds a deterministic match: %s" % [built.get("errors", [])])
			if bool(built.get("valid", false)):
				assert_true(bool(built["definition"].get("networked", false)), "match definition distinguishes remote participants from autonomous AI")
				assert_equal(String(built["definition"]["players"][1].get("controller", "")), "remote", "remote player is not assigned an AI planner")
				assert_equal(int(built["definition"]["players"][1].get("population_limit", 0)), 75, "lobby population setting reaches the match")
				assert_equal(String(built["definition"].get("victory_rules", [])[0].get("type", "")), "conquest", "lobby victory setting reaches the match")
			var invited = MultiplayerLobby.new()
			assert_equal(invited.load_invite(lobby.invite_code()), "", "joiner imports the host's complete lobby configuration")
			assert_equal(GameSaveArchive.fingerprint(invited.build_match().get("definition", {})), GameSaveArchive.fingerprint(built.get("definition", {})), "invitation produces the same deterministic match fingerprint")
		assert_equal(lobby.set_slot(count, 13, count, "ai"), "lobby_slot_invalid", "AI cannot silently occupy a remote frame without host authority")
		assert_equal(lobby.participant_teams().size(), count, "rejected AI slot leaves all network participants intact")
	var invalid := MultiplayerLobby.new()
	assert_equal(invalid.configure(1), "lobby_player_count_invalid", "lobby rejects fewer than two players")
	assert_equal(invalid.configure(8, {"map_size_id": "compact"}), "skirmish_map_player_capacity_exceeded", "lobby enforces map player capacity")
	assert_equal(invalid.load_invite("bad-code"), "lobby_invite_invalid", "joiner rejects malformed invitation codes")
	if failures.is_empty():
		print("P12 two-to-eight-player lobby settings tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
