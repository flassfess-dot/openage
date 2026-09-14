extends SceneTree

const MatchDefinition := preload("res://scripts/match_definition.gd")

const MATCH_PATHS := [
	"res://assets/generated/matches/struggle-for-sicily.json",
	"res://assets/generated/matches/battle-of-mylae.json",
	"res://assets/generated/matches/battle-of-tunes.json",
]

var failures: Array[String] = []


func _initialize() -> void:
	var matches: Array = MATCH_PATHS.map(func(path): return MatchDefinition.load_json(path))
	assert_true(matches.all(func(value): return bool(value.get("valid", false))), "all First Punic War definitions satisfy MatchDefinition")
	verify_sicily(matches[0])
	verify_mylae(matches[1])
	verify_tunes(matches[2])
	var matrix = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_waves/first_punic_war_campaign.json"))
	assert_equal(int(matrix.get("summary", {}).get("launcher_ready_count", 0)), 3, "campaign audit publishes all three mechanically ready missions")
	assert_equal(int(matrix.get("summary", {}).get("blocked_count", -1)), 0, "campaign audit has no hidden launcher blocker")
	_finish("I12-020N First Punic War imported contract tests passed")


func verify_sicily(definition: Dictionary) -> void:
	var conditions: Array = definition.get("scenario_definition", {}).get("participants", [])[0].get("groups", [])[0].get("conditions", [])
	assert_equal(conditions.map(func(value): return String(value.get("type", ""))), ["destroy_count", "destroy_count"], "Sicily preserves both DestroyMultiple conditions")
	assert_equal(conditions.map(func(value): return int(value.get("required_count", 0))), [3, 6], "Sicily preserves exact Slinger and Axeman counts")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_legacy_victory_condition_count", -1)), 0, "Sicily has no deferred victory command")


func verify_mylae(definition: Dictionary) -> void:
	var artifacts: Array = definition.get("entities", []).filter(func(value): return int(value.get("source_unit_id", -1)) == 159)
	assert_equal(artifacts.size(), 2, "Mylae imports both exact source artifacts as mobile entities")
	assert_true(artifacts.all(func(value): return String(value.get("kind", "")) == "artifact" and int(value.get("team", -1)) == 0), "Mylae artifacts start neutral")
	var conditions: Array = definition.get("scenario_definition", {}).get("participants", [])[0].get("groups", [])[0].get("conditions", [])
	assert_true(conditions.all(func(value): return String(value.get("type", "")) == "bring_object_to_area"), "Mylae preserves both BringToArea conditions")
	var fallback_ai: Array = definition.get("players", []).filter(func(value): return String(value.get("ai", {}).get("profile", "")) == "source_random_fallback")
	assert_equal(fallback_ai.size(), 1, "source Random/Empty player receives an explicit active generic fallback")


func verify_tunes(definition: Dictionary) -> void:
	var towers: Array = definition.get("entities", []).filter(func(value): return int(value.get("source_unit_id", -1)) == 69)
	assert_equal(towers.size(), 4, "Tunes imports all four source Guard Towers through the tower archetype")
	var integrated_ai: Array = definition.get("players", []).filter(func(value): return int(value.get("team", 0)) == 4)
	assert_true(integrated_ai.size() == 1 and bool(integrated_ai[0].get("ai", {}).get("enabled", false)), "integrated zero-valued source AI profile remains active")
	assert_equal(int(definition.get("gaps", {}).get("unsupported_object_count", -1)), 0, "Tunes has no unsupported simulation object")


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
