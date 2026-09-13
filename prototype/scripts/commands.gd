class_name RoRCommands

class Command:
	var tick: int
	var command_id: int = 0
	var issuer_id: int = 0
	var sequence_id: int = 0
	var unit_ids: Array[int] = []
	var params: Dictionary = {}
	var _envelope_assigned: bool = false

	func _init(command_tick: int, command_unit_ids: Array[int], extra: Dictionary = {}) -> void:
		tick = command_tick
		unit_ids = command_unit_ids.duplicate()
		params = extra.duplicate(true)

	func assign_envelope(command_issuer_id: int, command_sequence_id: int) -> bool:
		if command_sequence_id <= 0:
			return false
		if _envelope_assigned:
			return issuer_id == command_issuer_id and sequence_id == command_sequence_id
		issuer_id = command_issuer_id
		sequence_id = command_sequence_id
		command_id = command_sequence_id
		_envelope_assigned = true
		return true

	func envelope() -> Dictionary:
		return {
			"issuer_id": issuer_id,
			"sequence_id": sequence_id,
			"tick": tick,
			"type": command_type(),
		}

	func command_type() -> String:
		return "base"


class MoveCommand extends Command:
	var target: Vector2

	func _init(command_tick: int, command_unit_ids: Array[int], world_target: Vector2) -> void:
		super(command_tick, command_unit_ids, {"target": world_target})
		target = world_target

	func command_type() -> String:
		return "move"


class FormationMoveCommand extends MoveCommand:
	var formation: String
	var forward: Vector2

	func _init(command_tick: int, command_unit_ids: Array[int], world_target: Vector2, formation_name: String, world_forward: Vector2 = Vector2.ZERO) -> void:
		super(command_tick, command_unit_ids, world_target)
		formation = formation_name
		forward = world_forward.normalized() if world_forward.length_squared() > 0.0001 else Vector2.ZERO
		params["formation"] = formation_name
		params["forward"] = forward

	func command_type() -> String:
		return "formation_move"


class AttackCommand extends Command:
	var target_unit_id: int
	var target_entity_id: int

	func _init(command_tick: int, command_unit_ids: Array[int], target_id: int, policy: Dictionary = {}) -> void:
		var payload := {"target_unit_id": target_id, "target_entity_id": target_id}
		# Canonical target identifiers stay integers even after JSON decoded the
		# policy dictionary''s numeric values as floats.
		payload.merge(policy.duplicate(true), false)
		super(command_tick, command_unit_ids, payload)
		target_unit_id = target_id
		target_entity_id = target_id

	func command_type() -> String:
		return "attack"


class ConvertCommand extends Command:
	var target_entity_id: int

	func _init(command_tick: int, command_unit_ids: Array[int], target_id: int) -> void:
		super(command_tick, command_unit_ids, {"target_entity_id": target_id})
		target_entity_id = target_id

	func command_type() -> String:
		return "convert"


class HealCommand extends Command:
	var target_entity_id: int

	func _init(command_tick: int, command_unit_ids: Array[int], target_id: int) -> void:
		super(command_tick, command_unit_ids, {"target_entity_id": target_id})
		target_entity_id = target_id

	func command_type() -> String:
		return "heal"


class MartyrdomCommand extends Command:
	func _init(command_tick: int, command_unit_ids: Array[int]) -> void:
		super(command_tick, command_unit_ids, {})

	func command_type() -> String:
		return "martyrdom"


class AttackMoveCommand extends MoveCommand:
	func _init(command_tick: int, command_unit_ids: Array[int], world_target: Vector2) -> void:
		super(command_tick, command_unit_ids, world_target)

	func command_type() -> String:
		return "attack_move"


class StanceCommand extends Command:
	var stance: String

	func _init(command_tick: int, command_unit_ids: Array[int], stance_name: String) -> void:
		super(command_tick, command_unit_ids, {"stance": stance_name})
		stance = stance_name

	func command_type() -> String:
		return "stance"


class GatherCommand extends Command:
	var resource_id: int

	func _init(command_tick: int, command_unit_ids: Array[int], target_resource_id: int) -> void:
		super(command_tick, command_unit_ids, {"resource_id": target_resource_id})
		resource_id = target_resource_id

	func command_type() -> String:
		return "gather"


class ReturnResourcesCommand extends Command:
	var target_building_id: int

	func _init(command_tick: int, command_unit_ids: Array[int], target_id: int = -1) -> void:
		super(command_tick, command_unit_ids, {"target_building_id": target_id})
		target_building_id = target_id

	func command_type() -> String:
		return "return_resources"


class BoardCommand extends Command:
	var transport_id: int

	func _init(command_tick: int, passenger_ids: Array[int], target_transport_id: int) -> void:
		super(command_tick, passenger_ids, {"transport_id": target_transport_id})
		transport_id = target_transport_id

	func command_type() -> String:
		return "board"


class UnloadCommand extends Command:
	var target: Vector2
	var passenger_ids: Array[int]

	func _init(command_tick: int, transport_ids: Array[int], world_target: Vector2, selected_passenger_ids: Array[int] = []) -> void:
		super(command_tick, transport_ids, {"target": world_target, "passenger_ids": selected_passenger_ids.duplicate()})
		target = world_target
		passenger_ids = selected_passenger_ids.duplicate()

	func command_type() -> String:
		return "unload"


class SetTradeResourceCommand extends Command:
	var resource_type_id: int

	func _init(command_tick: int, trader_ids: Array[int], input_resource_type_id: int) -> void:
		super(command_tick, trader_ids, {"resource_type_id": input_resource_type_id})
		resource_type_id = input_resource_type_id

	func command_type() -> String:
		return "set_trade_resource"


class TradeCommand extends Command:
	var target_dock_id: int

	func _init(command_tick: int, trader_ids: Array[int], target_id: int) -> void:
		super(command_tick, trader_ids, {"target_dock_id": target_id})
		target_dock_id = target_id

	func command_type() -> String:
		return "trade"


class BuildCommand extends Command:
	var building_type: String
	var target: Vector2

	func _init(command_tick: int, command_unit_ids: Array[int], building: String, world_target: Vector2 = Vector2.ZERO) -> void:
		super(command_tick, command_unit_ids, {"building_type": building, "target": world_target})
		building_type = building
		target = world_target

	func command_type() -> String:
		return "build"


class TrainCommand extends Command:
	var unit_type: String
	var team: int
	var target: Vector2

	func _init(command_tick: int, command_unit_ids: Array[int], unit: String, player_team: int = 1, spawn_target: Vector2 = Vector2.ZERO) -> void:
		super(command_tick, command_unit_ids, {"unit_type": unit, "team": player_team, "target": spawn_target})
		unit_type = unit
		team = player_team
		target = spawn_target

	func command_type() -> String:
		return "train"


class ResearchCommand extends Command:
	var technology: String

	func _init(command_tick: int, command_unit_ids: Array[int], tech: String) -> void:
		super(command_tick, command_unit_ids, {"technology": tech})
		technology = tech

	func command_type() -> String:
		return "research"


class CancelProductionCommand extends Command:
	var queue_index: int

	func _init(command_tick: int, building_ids: Array[int], index: int = 0) -> void:
		super(command_tick, building_ids, {"queue_index": index})
		queue_index = index

	func command_type() -> String:
		return "cancel_production"


class RepairCommand extends Command:
	var target_building_id: int

	func _init(command_tick: int, command_unit_ids: Array[int], target_id: int) -> void:
		super(command_tick, command_unit_ids, {"target_building_id": target_id})
		target_building_id = target_id

	func command_type() -> String:
		return "repair"


class HoldCommand extends Command:
	func _init(command_tick: int, command_unit_ids: Array[int]) -> void:
		super(command_tick, command_unit_ids, {})

	func command_type() -> String:
		return "hold"


class StopCommand extends Command:
	func _init(command_tick: int, command_unit_ids: Array[int]) -> void:
		super(command_tick, command_unit_ids, {})

	func command_type() -> String:
		return "stop"


class ResignCommand extends Command:
	func _init(command_tick: int) -> void:
		super(command_tick, [], {})

	func command_type() -> String:
		return "resign"

