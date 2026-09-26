extends SceneTree

const HudViewModel := preload("res://scripts/hud_view_model.gd")
const InterfaceLayout := preload("res://scripts/interface_layout.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var model := {"population": {"current": 23, "cap": 25}, "queue": [{"status": "blocked_population"}]}
	var status: Dictionary = HudViewModel.status_indicators({"match_elapsed_seconds": 3661.0}, model)
	assert_equal(status["population_text"], "23/25", "population uses the authoritative HUD count and limit")
	assert_equal(status["clock_text"], "01:01:01", "clock formats elapsed match time")
	assert_true(status["blocked"] and status["blink_on"], "ready population-blocked queue enters lit blink phase")
	status = HudViewModel.status_indicators({"match_elapsed_seconds": 3661.6}, model)
	assert_true(status["blocked"] and not status["blink_on"], "blocked indicator alternates to unlit phase")
	model["queue"] = [{"status": "training"}]
	status = HudViewModel.status_indicators({"match_elapsed_seconds": 3661.6}, model)
	assert_true(not status["blocked"] and status["blink_on"], "non-ready queue never blinks")
	status = HudViewModel.status_indicators({"match_elapsed_seconds": 3661.6, "player_state": {"blocked_population_queues": 1}}, model)
	assert_true(status["blocked"] and not status["blink_on"], "off-screen owned blocked queue also drives the global indicator")
	for size in [Vector2(640, 480), Vector2(800, 600), Vector2(1024, 768), Vector2(1280, 720), Vector2(1920, 800)]:
		var layout := InterfaceLayout.for_viewport(size)
		var overlay: Rect2 = layout["status_overlay"]
		assert_true(layout["world"].encloses(overlay), "status indicator stays in the world area at %s" % size)
		for region_name in ["top", "bottom", "command", "selection", "minimap"]:
			assert_true(not overlay.intersects(layout[region_name]), "status indicator does not cover %s at %s" % [region_name, size])
	if failures.is_empty():
		print("P08 population/timer and L3 layout tests passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])
