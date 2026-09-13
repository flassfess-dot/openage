class_name RoRSourceAiScenarioLedger
extends RefCounted

const AiPlayer := preload("res://scripts/ai_player.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")

const PUBLIC_COMMAND_TYPES := [
	"attack",
	"attack_move",
	"build",
	"formation_move",
	"gather",
	"move",
	"research",
	"return_resources",
	"train",
]


static func probe(world, controller, definition: Dictionary, next_tick: int = 1) -> Dictionary:
	var players: Array = definition.get("players", []).filter(func(player):
		return String(player.get("controller", "ai")) == "ai" and bool(player.get("ai", {}).get("enabled", true))
	)
	players.sort_custom(func(left, right): return int(left.get("team", 0)) < int(right.get("team", 0)))
	var profiles: Array = []
	var issued: Array[Dictionary] = []
	var command_type_counts: Dictionary = {}
	var snapshot_milliseconds := 0
	var planning_milliseconds := 0

	for player_value in players:
		var player: Dictionary = player_value
		var ai = AiPlayer.new(player)
		var snapshot_started := Time.get_ticks_msec()
		var snapshot := SimulationSnapshot.presentation(world, controller.tick_index, int(ai.team), ai.presentation_options())
		snapshot_milliseconds += Time.get_ticks_msec() - snapshot_started
		var planning_started := Time.get_ticks_msec()
		var commands: Array = ai.collect_commands(snapshot, next_tick)
		planning_milliseconds += Time.get_ticks_msec() - planning_started
		var command_types: Array[String] = []
		for command in commands:
			var command_type := String(command.command_type())
			command_types.append(command_type)
			command_type_counts[command_type] = int(command_type_counts.get(command_type, 0)) + 1
			controller.enqueue_command(command, true, int(ai.team))
			issued.append({"team": int(ai.team), "command": command, "command_type": command_type})
		command_types.sort()
		var source_contract: Dictionary = player.get("source_ai", {})
		var runtime_support: Dictionary = source_contract.get("runtime_support", {})
		profiles.append({
			"team": int(ai.team),
			"profile": String(ai.profile),
			"normalization_status": String(source_contract.get("status", "")),
			"build_order_status": String(source_contract.get("build_order_status", "")),
			"pending_strategic_number_ids": _sorted_ints(runtime_support.get("pending_strategic_number_ids", [])),
			"pending_rule_directives": _sorted_strings(runtime_support.get("pending_rule_directives", [])),
			"command_types": command_types,
			"command_count": command_types.size(),
			"canonical_state": ai.canonical_state(),
		})

	var local_team := int(definition.get("local_team", 1))
	var first_ai_team := int(players[0].get("team", 2)) if not players.is_empty() else 2
	controller.advance_frame(0.05, local_team, first_ai_team)
	var accepted_count := 0
	var rejected_count := 0
	var rejection_reasons: Dictionary = {}
	for issued_value in issued:
		var issued_command: Dictionary = issued_value
		var command = issued_command["command"]
		var result: Dictionary = controller.get_command_result(int(command.sequence_id))
		if bool(result.get("accepted", false)):
			accepted_count += 1
		else:
			rejected_count += 1
			var reason := String(result.get("reason", "missing_result"))
			rejection_reasons[reason] = int(rejection_reasons.get(reason, 0)) + 1

	return {
		"match_id": String(definition.get("id", "")),
		"source_sha256": String(definition.get("source", {}).get("scenario_sha256", definition.get("scenario_source", {}).get("scenario_sha256", ""))),
		"profile_count": profiles.size(),
		"profiles": profiles,
		"issued_command_count": issued.size(),
		"accepted_command_count": accepted_count,
		"rejected_command_count": rejected_count,
		"rejection_reasons": rejection_reasons,
		"command_type_counts": command_type_counts,
		"snapshot_milliseconds": snapshot_milliseconds,
		"planning_milliseconds": planning_milliseconds,
	}


static func validate_probe(probe_result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if String(probe_result.get("match_id", "")).is_empty():
		errors.append("match_id_missing")
	if int(probe_result.get("profile_count", 0)) != probe_result.get("profiles", []).size():
		errors.append("profile_count_mismatch")
	if int(probe_result.get("issued_command_count", 0)) != int(probe_result.get("accepted_command_count", 0)) + int(probe_result.get("rejected_command_count", 0)):
		errors.append("command_result_count_mismatch")
	for profile_value in probe_result.get("profiles", []):
		var profile: Dictionary = profile_value
		if int(profile.get("team", 0)) <= 0:
			errors.append("profile_team_invalid")
		if String(profile.get("profile", "")) != "source_campaign_v1":
			errors.append("profile_not_source_campaign:%d" % int(profile.get("team", 0)))
		for command_type in profile.get("command_types", []):
			if String(command_type) not in PUBLIC_COMMAND_TYPES:
				errors.append("non_public_command:%s" % String(command_type))
	return errors


static func stable_projection(probe_result: Dictionary) -> Dictionary:
	var projected_profiles: Array = []
	for profile_value in probe_result.get("profiles", []):
		var profile: Dictionary = profile_value
		var profile_command_type_counts: Dictionary = {}
		for command_type_value in profile.get("command_types", []):
			var command_type := String(command_type_value)
			profile_command_type_counts[command_type] = int(profile_command_type_counts.get(command_type, 0)) + 1
		projected_profiles.append({
			"team": int(profile.get("team", 0)),
			"profile": String(profile.get("profile", "")),
			"normalization_status": String(profile.get("normalization_status", "")),
			"build_order_status": String(profile.get("build_order_status", "")),
			"pending_strategic_number_ids": profile.get("pending_strategic_number_ids", []),
			"pending_rule_directives": profile.get("pending_rule_directives", []),
			"command_type_counts": profile_command_type_counts,
			"command_count": int(profile.get("command_count", 0)),
		})
	return {
		"match_id": String(probe_result.get("match_id", "")),
		"source_sha256": String(probe_result.get("source_sha256", "")),
		"profile_count": int(probe_result.get("profile_count", 0)),
		"profiles": projected_profiles,
		"issued_command_count": int(probe_result.get("issued_command_count", 0)),
		"accepted_command_count": int(probe_result.get("accepted_command_count", 0)),
		"rejected_command_count": int(probe_result.get("rejected_command_count", 0)),
		"rejection_reasons": probe_result.get("rejection_reasons", {}),
		"command_type_counts": probe_result.get("command_type_counts", {}),
	}


static func _sorted_ints(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value in values:
		result.append(int(value))
	result.sort()
	return result


static func _sorted_strings(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	result.sort()
	return result
