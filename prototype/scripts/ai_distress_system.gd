class_name RoRAiDistressSystem
extends RefCounted

const SIGNAL_LIFETIME_SECONDS := 4.0
const MAX_ACTIVE_SIGNALS := 4096

var next_sequence: int = 1
var signals_by_target_id: Dictionary = {}


func reset() -> void:
	next_sequence = 1
	signals_by_target_id.clear()


func record(attacker: Dictionary, target: Dictionary) -> void:
	var attacker_id := int(attacker.get("id", -1))
	var attacker_team := int(attacker.get("team", 0))
	var target_id := int(target.get("id", -1))
	var target_team := int(target.get("team", 0))
	if attacker_id < 0 or target_id < 0 or attacker_team <= 0 or target_team <= 0 or attacker_team == target_team:
		return
	signals_by_target_id[target_id] = {
		"sequence": next_sequence,
		"target_team": target_team,
		"target_id": target_id,
		"attacker_team": attacker_team,
		"attacker_id": attacker_id,
		"position": Vector2(target.get("pos", Vector2.ZERO)),
		"remaining_seconds": SIGNAL_LIFETIME_SECONDS,
	}
	next_sequence += 1
	_evict_oldest_if_needed()


func advance(context: Dictionary) -> void:
	var delta := float(context.get("delta", 0.0))
	var expired: Array[int] = []
	var target_ids: Array = signals_by_target_id.keys()
	target_ids.sort()
	for target_id_value in target_ids:
		var target_id := int(target_id_value)
		var distress: Dictionary = signals_by_target_id[target_id]
		distress["remaining_seconds"] = float(distress.get("remaining_seconds", 0.0)) - maxf(0.0, delta)
		if float(distress["remaining_seconds"]) <= 0.0:
			expired.append(target_id)
	for target_id in expired:
		signals_by_target_id.erase(target_id)


func presentation_for_team(team: int) -> Array:
	var result: Array = []
	for distress_value in signals_by_target_id.values():
		var distress: Dictionary = distress_value
		if int(distress.get("target_team", 0)) == team:
			result.append(distress.duplicate(true))
	_sort_signals(result)
	return result


func canonical_state() -> Dictionary:
	var signals: Array = []
	for distress_value in signals_by_target_id.values():
		signals.append(distress_value.duplicate(true))
	_sort_signals(signals)
	return {
		"next_sequence": next_sequence,
		"signals": signals,
	}


func _evict_oldest_if_needed() -> void:
	if signals_by_target_id.size() <= MAX_ACTIVE_SIGNALS:
		return
	var oldest_target_id := -1
	var oldest_sequence := 9223372036854775807
	for target_id_value in signals_by_target_id.keys():
		var target_id := int(target_id_value)
		var sequence := int(signals_by_target_id[target_id].get("sequence", 0))
		if sequence < oldest_sequence or (sequence == oldest_sequence and target_id < oldest_target_id):
			oldest_sequence = sequence
			oldest_target_id = target_id
	if oldest_target_id >= 0:
		signals_by_target_id.erase(oldest_target_id)


func _sort_signals(signals: Array) -> void:
	signals.sort_custom(func(left, right):
		var left_sequence := int(left.get("sequence", 0))
		var right_sequence := int(right.get("sequence", 0))
		if left_sequence != right_sequence:
			return left_sequence < right_sequence
		return int(left.get("target_id", -1)) < int(right.get("target_id", -1))
	)
