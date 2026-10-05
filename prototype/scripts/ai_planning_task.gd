class_name RoRAiPlanningTask
extends RefCounted

const AiPlayer := preload("res://scripts/ai_player.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Data := preload("res://scripts/isolated_task_data.gd")

static func capture(ai, snapshot: Dictionary, tick: int) -> Dictionary:
	var settings: Dictionary = Data.copy(ai.economic_policy)
	for field in ["enabled", "formation_name", "profile", "initial_attack_delay", "attack_separation", "minimum_attack_group_size", "maximum_attack_group_size", "enemy_response_distance", "use_workers_in_attack_groups"]:
		var key := String(field)
		if key == "formation_name":
			key = "formation"
		elif key in ["initial_attack_delay", "attack_separation"]:
			key += "_ticks"
		settings[key] = ai.get(field)
	settings["economic_interval_ticks"] = ai.economic_interval
	settings["military_interval_ticks"] = ai.military_interval
	return {"definition": {"team": ai.team, "ai": settings, "source_ai": Data.copy(ai.source_contract)}, "state": Data.copy(ai.canonical_state()), "snapshot": Data.copy(snapshot), "tick": tick}

static func run(input: Dictionary) -> Dictionary:
	var ai := AiPlayer.new(input["definition"])
	if not ai.restore_state(input["state"]):
		return {"valid": false}
	var commands := ai.collect_commands(input["snapshot"], int(input["tick"]))
	var proposals: Array = []
	var codec := Replay.new()
	for command in commands:
		proposals.append({"tick": int(command.tick), "type": String(command.command_type()), "unit_ids": command.unit_ids.duplicate(), "params": codec.encode_variant(command.params, false)})
	return {"valid": true, "commands": proposals, "state": ai.canonical_state()}

static func decode_commands(output: Dictionary) -> Array:
	var codec := Replay.new()
	var commands: Array = []
	for record in output.get("commands", []):
		var command = codec.command_from_record(record)
		if command == null:
			return []
		commands.append(command)
	return commands
