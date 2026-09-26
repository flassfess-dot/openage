extends SceneTree

const SkirmishSettings := preload("res://scripts/skirmish_settings.gd")
const SimulationWorld := preload("res://scripts/simulation_world.gd")
const VictorySystem := preload("res://scripts/victory_system.gd")
const ScenarioOverlay := preload("res://scripts/scenario_overlay.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var settings := SkirmishSettings.default_settings()
	settings["victory_mode_id"] = "standard"
	var built := SkirmishSettings.build(settings)
	assert_true(bool(built.get("valid", false)), "Standard match and objective locations build: %s" % [built.get("errors", [])])
	if not bool(built.get("valid", false)):
		finish()
		return
	var definition: Dictionary = built["definition"]
	var rules: Array = definition.get("victory_rules", [])
	assert_equal(rules.map(func(rule): return String(rule.get("type", ""))), ["conquest", "artifacts", "ruins", "wonder"], "Standard combines the four authoritative paths")
	for rule_value in rules:
		if String(rule_value.get("type", "")) != "conquest":
			assert_equal(float(rule_value.get("hold_seconds", -1)), 900.0, "Standard hold period uses the source fifteen-minute countdown")
	var objectives: Array = definition.get("entities", []).filter(func(entity): return String(entity.get("kind", "")) in ["artifact", "ruin"])
	assert_equal(objectives.size(), 4, "generated Standard has capturable artifacts and ruins")
	assert_equal(objectives.filter(func(entity): return String(entity.get("kind", "")) == "artifact").size(), 2, "artifacts are mobile capturable units")
	assert_equal(objectives.filter(func(entity): return String(entity.get("kind", "")) == "ruin").size(), 2, "ruins are capturable map objectives")
	assert_true(objectives.filter(func(entity): return String(entity.get("kind", "")) == "ruin").all(func(entity): return int(entity.get("graphic_id", -1)) == 8), "generated ruins retain the source presentation asset")

	var context := {
		"teams": [1, 2],
		"participant_count": 2,
		"player_states": {1: {"status": "active"}, 2: {"status": "active"}},
		"conquest_presence": {1: true, 2: true},
		"relations": {1: {2: "enemy"}, 2: {1: "enemy"}},
		"objectives": [
			{"category": "artifact", "team": 1, "active": true},
			{"category": "artifact", "team": 1, "active": true},
			{"category": "ruin", "team": 0, "active": true},
			{"category": "ruin", "team": 0, "active": true},
			{"category": "wonder", "team": 2, "active": true, "completed": false},
		],
	}
	var victory = VictorySystem.new()
	victory.configure(rules, false)
	assert_equal(victory.update(899.0, context).get("over"), false, "artifact control requires the full hold period")
	assert_equal(victory.update(1.0, context).get("reason"), "artifacts", "Standard artifact path ends through one outcome")
	context["objectives"][1]["team"] = 2
	context["objectives"][2]["team"] = 2
	context["objectives"][3]["team"] = 2
	victory.configure(rules, false)
	assert_equal(victory.update(900.0, context).get("reason"), "ruins", "Standard ruin path uses the same outcome")
	context["objectives"][3]["team"] = 1
	context["objectives"][4]["completed"] = true
	victory.configure(rules, false)
	assert_equal(victory.update(900.0, context).get("reason"), "wonder", "Standard Wonder path uses the same outcome")

	var world = SimulationWorld.new(Vector2i(16, 16))
	world.navigation_grid.configure_terrain(func(_cell): return "grass")
	var ruin: Dictionary = world.add_victory_object("ruin", Vector2(5.5, 5.5), 0)
	world.add_unit(1, "clubman", Vector2(5.5, 5.7), false)
	world.update_capturable_objectives()
	assert_equal(ruin.get("team"), 1, "nearby unit captures a neutral generated ruin")
	assert_equal(world.victory_system.objective_summary.get("ruin", {}).get("by_team", {}).get(1), 1, "capture updates indexed victory ownership")
	var overlay = ScenarioOverlay.new()
	overlay.configure({"title": "Skirmish"}, null, {})
	overlay.set_snapshot({
		"observer_team": 2,
		"scenario": {},
		"match_result": {"over": true, "winner_team": 1, "winner_teams": [1, 2], "reason": "conquest"},
	})
	assert_true(overlay.result_layer.visible and overlay.is_blocking(), "ordinary skirmish opens a final outcome screen")
	assert_equal(overlay.result_title.text, "ПОБЕДА", "allied winner sees victory rather than primary-team-only defeat")
	overlay._dismiss_result()
	assert_true(not overlay.is_blocking(), "finished skirmish can be observed after dismissing the result")
	overlay.free()
	finish()


func assert_true(value: bool, context: String) -> void:
	if not value:
		failures.append("%s: expected true" % context)


func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [context, expected, actual])


func finish() -> void:
	if failures.is_empty():
		print("P07 Standard victory conditions passed")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)
