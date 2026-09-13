extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")
const PresentationModel := preload("res://scripts/scenario_presentation_model.gd")
const ResourceCatalog := preload("res://scripts/resource_catalog.gd")

const MATCH_PATH := "res://assets/generated/matches/birth-of-rome.json"

var failures: Array[String] = []


func _initialize() -> void:
	var definition := MatchDefinition.load_json(MATCH_PATH)
	var catalog := ResourceCatalog.new()
	catalog.load()
	var builder := PresentationModel.new()
	builder.configure(catalog.localization, catalog.object_catalog_data)
	var participant: Dictionary = definition.get("scenario_definition", {}).get("participants", [])[0]
	var first_condition: Dictionary = participant.get("groups", [])[0].get("conditions", [])[0]
	var state := {
		"participant": participant,
		"condition_states": {String(first_condition["id"]): {"achieved": true, "current": 1, "required": 1}},
		"result": {"over": false, "winner_team": -1, "reason": ""},
	}
	var model := builder.build(definition, state, 1, "ru")
	assert_true(bool(model.get("visible", false)), "local scenario participant produces presentation")
	assert_equal(model.get("objectives", []).size(), 1, "twelve equivalent source conditions are summarized as one objective")
	var objective: Dictionary = model.get("objectives", [])[0]
	assert_equal(int(objective.get("current", -1)), 1, "summary counts achieved target areas")
	assert_equal(int(objective.get("required", -1)), 12, "summary retains all twelve source target areas")
	assert_true(String(objective.get("label", "")).contains("Укрепленная вышка"), "objective name comes from source localization")

	state["result"] = {"over": true, "winner_team": 1, "reason": "scenario"}
	assert_equal(builder.build(definition, state, 1, "ru").get("outcome"), "victory", "local winning team maps to victory presentation")
	state["result"] = {"over": true, "winner_team": 2, "reason": "scenario"}
	assert_equal(builder.build(definition, state, 1, "ru").get("outcome"), "defeat", "opponent winning team maps to defeat presentation")
	_finish("I12-020D scenario presentation model tests passed")


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
