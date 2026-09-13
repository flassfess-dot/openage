class_name RoRCommandResult
extends RefCounted


static func accepted(command, applied_tick: int, details: Dictionary = {}) -> Dictionary:
	return _create(command, applied_tick, true, "", details)


static func rejected(command, applied_tick: int, reason: String, details: Dictionary = {}) -> Dictionary:
	return _create(command, applied_tick, false, reason, details)


static func _create(command, applied_tick: int, was_accepted: bool, reason: String, details: Dictionary) -> Dictionary:
	return {
		"accepted": was_accepted,
		"reason": reason,
		"applied_tick": applied_tick,
		"command_tick": int(command.tick),
		"command_type": String(command.command_type()),
		"issuer_id": int(command.issuer_id),
		"sequence_id": int(command.sequence_id),
		"details": details.duplicate(true),
	}
