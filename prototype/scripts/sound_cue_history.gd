class_name RoRSoundCueHistory
extends RefCounted

const MAX_CUES := 5
const TARGET_COOLDOWN_TICKS := 40

var cues: Array[Dictionary] = []
var next_index := 0
var last_sequence := 0


func reset() -> void:
	cues.clear()
	next_index = 0
	last_sequence = 0


func consume_distress(signals: Array, observer_team: int, current_tick: int) -> Array[Dictionary]:
	var admitted: Array[Dictionary] = []
	if observer_team <= 0:
		return admitted
	for signal_value in signals:
		if not signal_value is Dictionary:
			continue
		var distress: Dictionary = signal_value
		var sequence := int(distress.get("sequence", 0))
		if sequence <= last_sequence:
			continue
		last_sequence = sequence
		# Only the owner may use the target's authoritative position. Enemy
		# distress records must never become a fog-bypassing camera cue.
		if int(distress.get("target_team", 0)) != observer_team:
			continue
		var target_id := int(distress.get("target_id", -1))
		var position_value: Variant = distress.get("position")
		if target_id < 0 or not position_value is Vector2 or not Vector2(position_value).is_finite():
			continue
		if cues.any(func(existing): return int(existing.get("target_id", -1)) == target_id and current_tick - int(existing.get("tick", 0)) < TARGET_COOLDOWN_TICKS):
			continue
		var cue := {"sequence": sequence, "target_id": target_id, "kind": "under_attack", "position": Vector2(position_value), "tick": current_tick}
		cues.push_front(cue)
		if cues.size() > MAX_CUES:
			cues.resize(MAX_CUES)
		next_index = 0
		admitted.append(cue.duplicate(true))
	return admitted


func next_cue() -> Dictionary:
	if cues.is_empty():
		return {}
	var cue: Dictionary = cues[next_index].duplicate(true)
	next_index = (next_index + 1) % cues.size()
	return cue


func snapshot() -> Array:
	return cues.duplicate(true)


static func empty_state() -> Dictionary:
	return {"cues": [], "next_index": 0, "last_sequence": 0}


func canonical_state() -> Dictionary:
	return {"cues": cues.duplicate(true), "next_index": next_index, "last_sequence": last_sequence}


func restore_state(state: Dictionary, current_tick: int) -> bool:
	var source: Variant = state.get("cues")
	if not source is Array or source.size() > MAX_CUES or current_tick < 0:
		return false
	var restored: Array[Dictionary] = []
	var previous_sequence := 2147483647
	for cue_value in source:
		if not cue_value is Dictionary:
			return false
		var cue: Dictionary = cue_value
		var sequence := int(cue.get("sequence", 0))
		var cue_tick := int(cue.get("tick", -1))
		var position: Variant = cue.get("position")
		if sequence <= 0 or sequence >= previous_sequence or int(cue.get("target_id", -1)) < 0 or String(cue.get("kind", "")) != "under_attack" or not position is Vector2 or not Vector2(position).is_finite() or cue_tick < 0 or cue_tick > current_tick:
			return false
		previous_sequence = sequence
		restored.append({"sequence": sequence, "target_id": int(cue.get("target_id", -1)), "kind": "under_attack", "position": Vector2(position), "tick": cue_tick})
	var restored_index := int(state.get("next_index", -1))
	var restored_last_sequence := int(state.get("last_sequence", -1))
	if restored_index < 0 or (restored.is_empty() and restored_index != 0) or (not restored.is_empty() and restored_index >= restored.size()) or restored_last_sequence < 0 or (not restored.is_empty() and restored_last_sequence < int(restored[0].get("sequence", 0))):
		return false
	cues = restored
	next_index = restored_index
	last_sequence = restored_last_sequence
	return true
