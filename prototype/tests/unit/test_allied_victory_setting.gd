extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const VictorySystem := preload("res://scripts/victory_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	assert_equal(settings.get("allied_victory_enabled"), false, "generated skirmish requires an explicit allied-victory choice")
	settings["allied_victory_enabled"] = true
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "enabled allied-victory setting builds")
	if bool(built.get("valid", false)):
		assert_equal(built.get("definition", {}).get("allied_victory_enabled"), true, "setting crosses the match-definition boundary")
	var invalid := settings.duplicate(true)
	invalid["allied_victory_enabled"] = "yes"
	assert_true(SkirmishSettings.normalize(invalid).get("errors", []).has("skirmish_allied_victory_invalid"), "ambiguous allied-victory value is rejected")

	var relations := {1: {2: "ally"}, 2: {1: "ally"}, 3: {1: "enemy", 2: "enemy"}}
	var context := {
		"teams": [1, 2, 3],
		"participant_count": 3,
		"player_states": {1: {"status": "active"}, 2: {"status": "active"}, 3: {"status": "defeated"}},
		"conquest_presence": {1: true, 2: true},
		"relations": relations,
	}
	var victory = VictorySystem.new()
	victory.configure([{"type": "conquest"}], false)
	assert_equal(victory.update(0.05, context).get("over"), false, "alliance alone cannot complete conquest")
	victory.configure([{"type": "conquest"}], true)
	assert_equal(victory.update(0.05, context).get("winner_teams"), [1, 2], "explicit allied victory awards the mutual surviving side")
	victory.configure([{"type": "conquest"}], true)
	context["relations"][2][1] = "neutral"
	assert_equal(victory.update(0.05, context).get("over"), false, "one-way alliance cannot create an allied victory")
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P07 allied-victory setting passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
