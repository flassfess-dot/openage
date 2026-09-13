class_name RoRReplaySystem
extends RefCounted

const Commands := preload("res://scripts/commands.gd")
const SimulationSnapshot := preload("res://scripts/simulation_snapshot.gd")
const FORMAT_VERSION: int = 2
const LEGACY_FORMAT_VERSION: int = 1

var simulation_seed: int = 1
var command_records: Array = []
var state_hashes: Array = []
var playback_cursor: int = 0


func begin(seed_value: int) -> void:
	simulation_seed = seed_value
	command_records.clear()
	state_hashes.clear()
	playback_cursor = 0


func record_command(command) -> void:
	command_records.append({
		"tick": int(command.tick),
		"issuer_id": int(command.issuer_id),
		"sequence_id": int(command.sequence_id),
		"type": String(command.command_type()),
		"unit_ids": command.unit_ids.duplicate(),
		"params": encode_variant(command.params),
	})
	command_records.sort_custom(_record_less)


func record_state(tick: int, world, controller = null) -> String:
	var digest := world_state_hash(world, tick, controller)
	state_hashes.append({"tick": tick, "sha256": digest})
	return digest


func commands_through_tick(tick: int) -> Array:
	var result: Array = []
	while playback_cursor < command_records.size() and int(command_records[playback_cursor]["tick"]) <= tick:
		result.append(command_from_record(command_records[playback_cursor]))
		playback_cursor += 1
	return result


func reset_playback() -> void:
	playback_cursor = 0


func expected_hash_at(tick: int) -> String:
	for item in state_hashes:
		if int(item.get("tick", -1)) == tick:
			return String(item.get("sha256", ""))
	return ""


func to_dictionary() -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"simulation_seed": simulation_seed,
		"commands": command_records.duplicate(true),
		"state_hashes": state_hashes.duplicate(true),
	}


func to_json() -> String:
	return JSON.stringify(to_dictionary(), "\t")


func load_dictionary(data: Dictionary) -> bool:
	var source_version := int(data.get("format_version", -1))
	if source_version not in [LEGACY_FORMAT_VERSION, FORMAT_VERSION]:
		return false
	simulation_seed = int(data.get("simulation_seed", 1))
	command_records = data.get("commands", []).duplicate(true)
	state_hashes = data.get("state_hashes", []).duplicate(true)
	for index in range(command_records.size()):
		var record: Dictionary = command_records[index]
		# Version 1 did not serialize an envelope. File order is the only
		# recoverable ordering contract for legacy replays.
		if int(record.get("sequence_id", 0)) <= 0:
			record["sequence_id"] = index + 1
		if not record.has("issuer_id"):
			record["issuer_id"] = 0
	command_records.sort_custom(_record_less)
	playback_cursor = 0
	return true


func _record_less(left: Dictionary, right: Dictionary) -> bool:
	if int(left.get("tick", 0)) != int(right.get("tick", 0)):
		return int(left.get("tick", 0)) < int(right.get("tick", 0))
	if int(left.get("sequence_id", 0)) != int(right.get("sequence_id", 0)):
		return int(left.get("sequence_id", 0)) < int(right.get("sequence_id", 0))
	if int(left.get("issuer_id", 0)) != int(right.get("issuer_id", 0)):
		return int(left.get("issuer_id", 0)) < int(right.get("issuer_id", 0))
	return String(left.get("type", "")) < String(right.get("type", ""))


func load_json(text: String) -> bool:
	var parsed = JSON.parse_string(text)
	return parsed is Dictionary and load_dictionary(parsed)


func command_from_record(record: Dictionary):
	var tick := int(record.get("tick", 0))
	var ids: Array[int] = []
	for value in record.get("unit_ids", []):
		ids.append(int(value))
	var params: Dictionary = decode_variant(record.get("params", {}))
	var command = null
	match String(record.get("type", "")):
		"move":
			command = Commands.MoveCommand.new(tick, ids, params.get("target", Vector2.ZERO))
		"formation_move":
			command = Commands.FormationMoveCommand.new(tick, ids, params.get("target", Vector2.ZERO), String(params.get("formation", "RECTANGLE")), params.get("forward", Vector2.ZERO))
		"attack_move":
			command = Commands.AttackMoveCommand.new(tick, ids, params.get("target", Vector2.ZERO))
		"attack":
			command = Commands.AttackCommand.new(tick, ids, int(params.get("target_entity_id", params.get("target_unit_id", -1))), params)
		"convert":
			command = Commands.ConvertCommand.new(tick, ids, int(params.get("target_entity_id", -1)))
		"heal":
			command = Commands.HealCommand.new(tick, ids, int(params.get("target_entity_id", -1)))
		"martyrdom":
			command = Commands.MartyrdomCommand.new(tick, ids)
		"gather":
			command = Commands.GatherCommand.new(tick, ids, int(params.get("resource_id", -1)))
		"return_resources":
			command = Commands.ReturnResourcesCommand.new(tick, ids, int(params.get("target_building_id", -1)))
		"board":
			command = Commands.BoardCommand.new(tick, ids, int(params.get("transport_id", -1)))
		"unload":
			var passenger_ids: Array[int] = []
			for passenger_id in params.get("passenger_ids", []):
				passenger_ids.append(int(passenger_id))
			command = Commands.UnloadCommand.new(tick, ids, params.get("target", Vector2.ZERO), passenger_ids)
		"set_trade_resource":
			command = Commands.SetTradeResourceCommand.new(tick, ids, int(params.get("resource_type_id", -1)))
		"trade":
			command = Commands.TradeCommand.new(tick, ids, int(params.get("target_dock_id", -1)))
		"build":
			command = Commands.BuildCommand.new(tick, ids, String(params.get("building_type", "")), params.get("target", Vector2.ZERO))
		"train":
			command = Commands.TrainCommand.new(tick, ids, String(params.get("unit_type", "")), int(params.get("team", 1)), params.get("target", Vector2.ZERO))
		"research":
			command = Commands.ResearchCommand.new(tick, ids, String(params.get("technology", "")))
		"cancel_production":
			command = Commands.CancelProductionCommand.new(tick, ids, int(params.get("queue_index", 0)))
		"repair":
			command = Commands.RepairCommand.new(tick, ids, int(params.get("target_building_id", -1)))
		"stance":
			command = Commands.StanceCommand.new(tick, ids, String(params.get("stance", "passive")))
		"hold":
			command = Commands.HoldCommand.new(tick, ids)
		"stop":
			command = Commands.StopCommand.new(tick, ids)
		"resign":
			command = Commands.ResignCommand.new(tick)
	if command != null:
		command.assign_envelope(int(record.get("issuer_id", 0)), int(record.get("sequence_id", 0)))
	return command


func encode_variant(value: Variant) -> Variant:
	if value is Vector2:
		return {"__vector2": [quantize(value.x), quantize(value.y)]}
	if value is Vector2i:
		return {"__vector2i": [value.x, value.y]}
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort_custom(func(left, right): return str(left) < str(right))
		for key in keys:
			result[str(key)] = encode_variant(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(encode_variant(item))
		return result
	if value is float:
		return quantize(value)
	return value


func decode_variant(value: Variant) -> Variant:
	if value is Dictionary:
		if value.has("__vector2"):
			return Vector2(float(value["__vector2"][0]), float(value["__vector2"][1]))
		if value.has("__vector2i"):
			return Vector2i(int(value["__vector2i"][0]), int(value["__vector2i"][1]))
		var result: Dictionary = {}
		for key in value:
			result[key] = decode_variant(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(decode_variant(item))
		return result
	return value


func world_state_hash(world, tick: int, controller = null) -> String:
	var snapshot := world_snapshot(world, tick, controller)
	var canonical := JSON.stringify(encode_variant(snapshot))
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(canonical.to_utf8_buffer())
	return hashing.finish().hex_encode()


func world_snapshot(world, tick: int, controller = null) -> Dictionary:
	return SimulationSnapshot.canonical(world, tick, controller)


func quantize(value: float) -> float:
	return snappedf(value, 0.000001)
