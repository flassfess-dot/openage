extends SceneTree

const GenerationJob := preload("res://scripts/skirmish_generation_job.gd")
const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["map_size_id"] = "compact"
	settings["players"][0]["civilization_id"] = 0
	settings["players"][1]["civilization_id"] = 0
	var job = GenerationJob.new()
	assert_true(job.start(settings), "background generation starts")
	var deadline := Time.get_ticks_msec() + 60000
	var maximum_progress := 0.0
	var observed_stage := ""
	while Time.get_ticks_msec() < deadline:
		var snapshot: Dictionary = job.snapshot()
		maximum_progress = maxf(maximum_progress, float(snapshot.get("progress", 0.0)))
		observed_stage = String(snapshot.get("stage", observed_stage))
		if bool(snapshot.get("complete", false)):
			break
		await process_frame
	var final_snapshot: Dictionary = job.snapshot()
	assert_true(bool(final_snapshot.get("complete", false)), "background generation finishes before its deadline")
	var result: Dictionary = job.take_result()
	assert_true(bool(result.get("valid", false)), "background generation returns a valid match")
	assert_true(maximum_progress > 0.0, "background generation reports intermediate progress")
	assert_equal(float(final_snapshot.get("progress", 0.0)), 1.0, "background generation reports completion")
	assert_true(not observed_stage.is_empty(), "background generation reports a user-facing stage")
	if bool(result.get("valid", false)):
		for player_value in result["definition"]["players"]:
			assert_true(int(player_value["civilization_id"]) in range(1, 17), "random civilization resolves before the match starts")
	job.shutdown()
	_finish("Skirmish generation job tests passed")


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func _finish(success_message: String) -> void:
	if failures.is_empty():
		print(success_message)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
