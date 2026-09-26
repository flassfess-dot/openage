extends SceneTree

const SoundCueHistory := preload("res://scripts/sound_cue_history.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var history := SoundCueHistory.new()
	assert_equal(history.next_cue(), {}, "Home has no target before a legal alert")
	assert_equal(history.consume_distress([distress_signal(1, 2, 10, Vector2(9, 9))], 1, 10).size(), 0, "enemy distress cannot reveal a hidden position")
	assert_equal(history.snapshot().size(), 0, "rejected alert never enters the camera history")
	assert_equal(history.consume_distress([distress_signal(2, 1, 10, Vector2(2, 3))], 1, 10).size(), 1, "own attacked position becomes an audible cue")
	assert_equal(history.consume_distress([distress_signal(3, 1, 10, Vector2(3, 3))], 1, 11).size(), 0, "rapid alerts for one target are throttled")
	assert_equal(history.consume_distress([distress_signal(4, 1, 10, Vector2(4, 3))], 1, 50).size(), 1, "target may alert again after the cooldown")
	for index in range(5, 10):
		history.consume_distress([distress_signal(index, 1, 10 + index, Vector2(index, 5))], 1, 50 + index)
	assert_equal(history.snapshot().size(), 5, "history retains only the latest five positions")
	assert_equal(int(history.next_cue()["sequence"]), 9, "Home begins at the newest event")
	assert_equal(int(history.next_cue()["sequence"]), 8, "Home cycles backward through recent events")
	for _index in range(3):
		history.next_cue()
	assert_equal(int(history.next_cue()["sequence"]), 9, "Home wraps after the fifth event")
	var saved_state: Dictionary = history.canonical_state()
	var restored := SoundCueHistory.new()
	assert_equal(restored.restore_state(saved_state, 60), true, "sound-cue history restores from a versioned save")
	assert_equal(restored.canonical_state(), saved_state, "cue order, sequence watermark and Home cursor survive a round trip")
	assert_equal(restored.next_cue(), history.next_cue(), "restored Home selection continues at the same cue")
	assert_equal(restored.consume_distress([distress_signal(9, 1, 99, Vector2(7, 7))], 1, 61).size(), 0, "restored sequence watermark suppresses duplicate alerts")
	var invalid_state := saved_state.duplicate(true)
	invalid_state["cues"][0]["tick"] = 999
	var before_invalid: Dictionary = restored.canonical_state()
	assert_equal(restored.restore_state(invalid_state, 60), false, "future-dated cue state is rejected before loading")
	assert_equal(restored.canonical_state(), before_invalid, "rejected cue state leaves the live history unchanged")
	history.reset()
	assert_equal(history.snapshot().size(), 0, "new match clears old positional knowledge")
	if failures.is_empty():
		print("P08 fog-safe sound cue history tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func distress_signal(sequence: int, team: int, target_id: int, position: Vector2) -> Dictionary:
	return {"sequence": sequence, "target_team": team, "target_id": target_id, "position": position}


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
