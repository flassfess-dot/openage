extends SceneTree

const MatchRegistry := preload("res://scripts/match_registry.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var entries := MatchRegistry.entries()
	assert_equal(entries.size(), 11, "launcher exposes the prototype, nine frozen campaign verticals, and custom skirmish")
	assert_true(entries.all(func(entry): return bool(entry.get("available", false))), "every registered match is packaged in the development project")
	assert_equal(MatchRegistry.resolve("campaign_birth_of_rome").get("path"), "res://assets/generated/matches/birth-of-rome.json", "stable match id resolves to generated campaign data")
	assert_equal(MatchRegistry.resolve("campaign_pyrrhus_of_epirus").get("path"), "res://assets/generated/matches/pyrrhus-of-epirus.json", "second campaign mission resolves to its proven generated data")
	assert_equal(MatchRegistry.resolve("campaign_syracuse").get("path"), "res://assets/generated/matches/syracuse.json", "third campaign mission resolves to its proven generated data")
	assert_equal(MatchRegistry.resolve("campaign_metaurus").get("path"), "res://assets/generated/matches/metaurus.json", "fourth campaign mission resolves to generated campaign data")
	assert_equal(MatchRegistry.resolve("campaign_zama").get("path"), "res://assets/generated/matches/zama.json", "fifth campaign mission resolves to its proven generated data")
	assert_equal(MatchRegistry.resolve("campaign_mithridates").get("path"), "res://assets/generated/matches/mithridates.json", "sixth campaign mission resolves to its proven generated data")
	assert_equal(MatchRegistry.resolve("campaign_battle_of_mylae").get("path"), "res://assets/generated/matches/battle-of-mylae.json", "First Punic War artifact mission resolves to generated campaign data")
	assert_equal(entries.map(func(entry): return String(entry.get("id", ""))), ["prototype_skirmish", "campaign_birth_of_rome", "campaign_pyrrhus_of_epirus", "campaign_syracuse", "campaign_metaurus", "campaign_zama", "campaign_mithridates", "campaign_struggle_for_sicily", "campaign_battle_of_mylae", "campaign_battle_of_tunes", "custom_skirmish"], "launcher preserves frozen campaign order and appends custom skirmish")
	assert_equal(MatchRegistry.requested_match(PackedStringArray(["--match=prototype_skirmish"])).get("id"), "prototype_skirmish", "command-line launch supports an explicit match id")
	assert_equal(MatchRegistry.requested_match(PackedStringArray(["--match=custom_skirmish"])).get("kind"), "custom_skirmish", "command-line launch resolves generated skirmish without a file path")
	assert_true(MatchRegistry.resolve("missing").is_empty(), "unknown match ids never fall back silently")
	_finish("I12-020G match registry tests passed")


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
