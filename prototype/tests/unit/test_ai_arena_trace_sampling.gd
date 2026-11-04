extends SceneTree
const Recorder := preload("res://tools/ai_arena_runner.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var duplicate: Dictionary = {}
	var selected := {"id":"develop","facts":{"age":100,"workers":7}}
	var candidates: Array = [{"id":"develop","utility":12.0}]
	for sampled_tick in range(1, 10001): Recorder.record_strategy_trace(duplicate, 1, sampled_tick, 1, selected, candidates)
	var result: Dictionary = Recorder.strategy_trace_snapshot(duplicate)
	check(result["rows"].size() == 1 and int(result["sampling"]["observed_distinct_inputs"]) == 1, "Preparation polls duplicated one strategic decision")
	check(int(result["sampling"]["duplicates_skipped"]) == 9999 and int(result["rows"][0]["tick"]) == 1, "Recorder confused sampling time with decision time")
	Recorder.record_strategy_trace(duplicate, 80, 83, 1, selected, candidates)
	check(Recorder.strategy_trace_snapshot(duplicate)["rows"].size() == 2, "A later genuine decision with unchanged features was lost")
	selected["facts"]["workers"] = 99
	candidates[0]["utility"] = -500.0
	result = Recorder.strategy_trace_snapshot(duplicate)
	check(int(result["rows"][0]["facts"]["workers"]) == 7 and float(result["rows"][0]["candidates"][0]["utility"]) == 12.0, "Recorded input aliases live policy dictionaries")
	result["rows"][0]["facts"]["workers"] = -1
	check(int(Recorder.strategy_trace_snapshot(duplicate)["rows"][0]["facts"]["workers"]) == 7, "Exported rows can mutate the recorder")
	var a: Dictionary = {}
	var b: Dictionary = {}
	seed(77123)
	var expected_random := randi()
	seed(77123)
	var total := Recorder.STRATEGY_TRACE_LIMIT * 8 + 17
	for index in range(1, total + 1):
		var choice := {"id":"develop","facts":{"workers":index}}
		var options: Array = [{"id":"develop","utility":float(index)}]
		Recorder.record_strategy_trace(a, index * 80, index * 80 + 2, 1, choice, options)
		Recorder.record_strategy_trace(b, index * 80, index * 80 + 2, 1, choice, options)
		if index % 1000 == 0: check(a.get("samples", []).size() <= Recorder.STRATEGY_TRACE_LIMIT - 2, "Recorder storage exceeded its bound")
	check(randi() == expected_random, "Recording changed the policy RNG stream")
	var full: Dictionary = Recorder.strategy_trace_snapshot(a)
	check(full == Recorder.strategy_trace_snapshot(b), "Identical input produced different samples")
	var rows: Array = full["rows"]
	check(rows.size() <= Recorder.STRATEGY_TRACE_LIMIT, "Export exceeded its capacity")
	check(int(rows[0]["decision_sample"]) == 1 and int(rows[-1]["decision_sample"]) == total, "First or late decisions disappeared after thinning")
	check(rows.any(func(row): return absf(float(row["decision_sample"]) - float(total) * 0.5) < float(full["sampling"]["thinning_stride"]) * 2.0), "Middle of the match disappeared after thinning")
	for index in range(1, rows.size()): check(int(rows[index]["decision_sample"]) > int(rows[index - 1]["decision_sample"]), "Sample order or identity is invalid")
	check(int(full["sampling"]["observed_distinct_inputs"]) == total and int(full["sampling"]["last_decision_tick"]) == total * 80, "Coverage metadata does not describe actual captured decisions")
	var empty: Dictionary = {}
	Recorder.record_strategy_trace(empty, -1000, 1, 1, selected, candidates)
	Recorder.record_strategy_trace(empty, 1, 1, 1, {}, [])
	check(Recorder.strategy_trace_snapshot(empty)["rows"].is_empty(), "Uninitialized director output became training data")
	if failures == 0: print("Arena strategy trace duplicate, ownership, temporal coverage, capacity, determinism and RNG checks passed")
	quit(0 if failures == 0 else 1)
