extends SceneTree
const Queue := preload("res://scripts/ai_decision_queue.gd")
const Task := preload("res://scripts/ai_planning_task.gd")
const Coordinator := preload("res://scripts/isolated_task_coordinator.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Replay := preload("res://scripts/replay_system.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
var failures: Array[String] = []
var captures := 0

func _initialize() -> void:
	var ai := Ai.new({"team": 2})
	ai.source_city_plan.center = Vector2(3.141591375, 4.135798765)
	var coordinator := Coordinator.new()
	coordinator.enabled = false
	var queue := Queue.new()
	queue.begin([ai], 2, 10, Callable(self, "capture"))
	queue.poll(coordinator, 2, 1)
	var expected: Dictionary = queue.records[0]["output"]
	var saved := queue.canonical_state()
	var codec := Replay.new()
	var archive := Archive.create("fixture", {"players": []}, 5, "0".repeat(64), {}, [ai.canonical_state()], {}, {"ai_decisions": saved})
	var persisted: Dictionary = JSON.parse_string(JSON.stringify(archive, "", true, true))
	var saved_ai := Ai.new({"team": 2})
	check(saved_ai.restore_state(codec.decode_variant(persisted["ai_states"])[0]) and saved_ai.canonical_state() == ai.canonical_state(), "AI archive preserves fractional state without hash quantization")
	var decoded: Dictionary = codec.decode_variant(persisted["controller_state"])["ai_decisions"]
	var restored := Queue.new()
	check(restored.restore_state(decoded, [saved_ai], 5, Callable(self, "capture")), "mid-calculation state survives JSON save encoding")
	check(restored.source_tick == 2 and restored.apply_tick == 10, "load preserves snapshot and application boundaries")
	var input: Dictionary = restored.records[0]["input"]
	check(input["snapshot"]["navigation"]["land"][0] == Vector2(3.125, 4.375), "binary payload preserves exact vector coordinates")
	check(input["snapshot"]["navigation"]["unit_regions"].get(7) == 3, "binary payload preserves integer dictionary keys")
	check(input["snapshot"]["fog_cells"] == PackedByteArray([0, 1, 2]), "packed fog array retains type and data")
	var count_before := captures
	var status := restored.poll(coordinator, 5, 2)
	check(status["ready"] and captures == count_before, "restored input is resubmitted without recapturing newer world facts")
	check(restored.records[0]["output"] == expected, "recalculation after loading preserves commands and AI state")
	check(restored.gate(status, 6)["ready"] and not restored.gate(status, 6)["planned"], "loading does not apply pending commands early")
	check(restored.gate(status, 10)["ready"], "loading retains the original deadline")
	var invalid := saved.duplicate(true)
	invalid["records"][0]["input"] = Marshalls.raw_to_base64(var_to_bytes({"tick": 11, "definition": {"team": 2}, "state": ai.canonical_state(), "snapshot": {}}))
	check(not Queue.new().restore_state(invalid, [ai], 5, Callable(self, "capture")), "a payload with a different target tick is rejected")
	invalid = saved.duplicate(true)
	invalid["records"].append(invalid["records"][0])
	check(not Queue.new().restore_state(invalid, [ai], 5, Callable(self, "capture")), "duplicate player records cannot reorder or duplicate publication")
	check(not Queue.new().restore_state(saved, [ai], 10, Callable(self, "capture")), "an already expired target is rejected")
	var uncaptured := Queue.new()
	uncaptured.begin([ai], 2, 10, Callable(self, "capture"))
	check(Queue.new().restore_state(uncaptured.canonical_state(), [ai], 2, Callable(self, "capture")), "save during bounded capture can resume at its frozen boundary")
	check(not Queue.new().restore_state(uncaptured.canonical_state(), [ai], 5, Callable(self, "capture")), "missing older facts cannot be silently rebuilt from a newer world")
	check(Queue.new().restore_state({}, [ai], 5, Callable(self, "capture")), "older saves without a pending queue remain supported")
	queue.cancel(coordinator)
	restored.cancel(coordinator)
	coordinator.shutdown()
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func capture(ai, tick: int) -> Dictionary:
	captures += 1
	return Task.capture(ai, {"tick": 2, "observer_team": ai.team, "map_size": Vector2i(12, 12), "player_state": {"team": ai.team, "allies": [ai.team]}, "units": [], "buildings": [], "resources": [], "navigation": {"land": [Vector2(3.125, 4.375)], "unit_regions": {7: 3}}, "fog_cells": PackedByteArray([0, 1, 2])}, tick)

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
