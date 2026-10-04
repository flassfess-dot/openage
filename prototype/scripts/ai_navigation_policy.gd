class_name RoRAiNavigationPolicy
extends RefCounted
const Commands := preload("res://scripts/commands.gd")
const FAILURE_REASONS := ["no_path", "no_group_route", "stuck_stopped_nearest_valid", "target_unreachable", "boarding_shore_unreachable"]
const BASE_RETRY_TICKS := 80
const MAX_RETRY_TICKS := 1200
var failures: Dictionary = {}

static func is_failure(reason: String) -> bool:
	return reason.trim_prefix("combat_complete:") in FAILURE_REASONS

func recovery_commands(snapshot: Dictionary, tick: int, reserved: Dictionary) -> Array:
	var result: Array = []
	var positions: Dictionary = snapshot.get("navigation", {}).get("recovery_positions", {})
	for unit in snapshot.get("units", []):
		var id := int(unit.get("id", -1))
		if reserved.has(id) or not positions.has(id) or int(unit.get("team", 0)) != int(snapshot.get("observer_team", -1)) or float(unit.get("hp", 0.0)) <= 0.0:
			continue
		if String(unit.get("task", "idle")) not in ["idle", "hold"] or not is_failure(String(unit.get("diagnostic_reason", ""))):
			continue
		result.append(Commands.MoveCommand.new(tick, [id], Vector2(positions[id])))
		reserved[id] = true
		if failures.has(id):
			failures[id]["retry_tick"] = tick + BASE_RETRY_TICKS
	return result


func reserved_units(snapshot: Dictionary, tick: int) -> Dictionary:
	var reserved := {}
	var live := {}
	for unit in snapshot.get("units", []):
		if int(unit.get("team", 0)) != int(snapshot.get("observer_team", -1)) or float(unit.get("hp", 0.0)) <= 0: continue
		var id := int(unit["id"])
		live[id] = true
		var cell := Vector2i(Vector2(unit.get("pos", Vector2.ZERO)).floor())
		var previous: Dictionary = failures.get(id, {})
		if not previous.is_empty() and previous["cell"] != cell:
			failures.erase(id)
			previous = {}
		if not is_failure(String(unit.get("diagnostic_reason", ""))) or String(unit.get("task", "idle")) not in ["idle", "hold"]: continue
		var request := int(unit.get("path_request_id", 0))
		if previous.is_empty() or int(previous["request"]) != request:
			var attempts := mini(5, int(previous.get("attempts", 0)) + 1)
			previous = {"cell": cell, "request": request, "attempts": attempts, "retry_tick": tick + mini(MAX_RETRY_TICKS, BASE_RETRY_TICKS * (1 << (attempts - 1)))}
			failures[id] = previous
		if tick < int(previous["retry_tick"]): reserved[id] = true
	for id in failures.keys():
		if not live.has(id): failures.erase(id)
	return reserved

func canonical_state() -> Array:
	var result := []
	var ids := failures.keys()
	ids.sort()
	for id in ids: result.append({"id": id, "failure": failures[id].duplicate(true)})
	return result

func restore_state(records: Array) -> bool:
	var restored := {}
	for record in records:
		if not record is Dictionary or not record.get("failure") is Dictionary: return false
		var failure: Dictionary = record["failure"]
		if int(record.get("id", -1)) < 0 or not failure.get("cell") is Vector2i or int(failure.get("attempts", 0)) not in range(1, 6) or int(failure.get("retry_tick", -1)) < 0: return false
		restored[int(record["id"])] = failure.duplicate(true)
	failures = restored
	return true
